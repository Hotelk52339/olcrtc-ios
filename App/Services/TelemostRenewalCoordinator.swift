import Foundation
import SwiftUI

// #465: the side-effecting half of automatic room renewal. `TelemostRenewalPolicy`
// decides WHETHER and WHEN; this drives the SSH and the stores.
//
// Owned by MainTabView, next to `UpdateChecker` and the subscription refresh,
// because renewal has to keep working while the user is anywhere in the app —
// including never opening Manage VPS again. It holds its OWN `Provisioner`, the
// per-owner pattern ServersView and LogsView already follow.
//
// Deliberately NOT shared with the manual button in ServersView: that path has
// to drive a sheet through create → apply → done/failed and report a hazard
// before the user commits. This one runs unattended and reports only through the
// log and a single published warning. The orchestration they share is ~15 lines;
// unifying it would mean threading UI phases through a service, and ServersView
// has already blown the SwiftUI type-checker budget three times in this repo.
@MainActor
final class TelemostRenewalCoordinator: ObservableObject {

    /// Set when the room is nearly gone and no free moment appeared, so the user
    /// has to be told. Cleared as soon as a renewal succeeds.
    @Published private(set) var warning: Warning?

    struct Warning: Identifiable, Equatable {
        let id: UUID              // the record whose room is expiring
        let minutesLeft: Int
        let recordName: String
    }

    private let connections: ConnectionStore
    private let tunnel: TunnelManager
    private let hosts: ServerHostStore
    private let provisioner = Provisioner()

    /// Guards against two checks overlapping — `.task` fires per appearance and
    /// the loop below ticks on its own.
    private var running = false

    /// #465: how often to re-ask the policy. The decision is cheap (no I/O) and
    /// the answer changes as the tunnel goes idle, so asking often is what makes
    /// "wait for a quiet moment" actually find one.
    private static let tick: Duration = .seconds(15 * 60)

    init(connections: ConnectionStore, tunnel: TunnelManager, hosts: ServerHostStore) {
        self.connections = connections
        self.tunnel      = tunnel
        self.hosts       = hosts
    }

    // MARK: - Entry points

    /// Long-lived loop started from MainTabView. Sleeps and re-checks rather than
    /// returning when there is nothing to do — an id-less `.task` never restarts,
    /// so returning would end renewal for the rest of the session.
    func run() async {
        while !Task.isCancelled {
            await checkNow()
            try? await Task.sleep(for: Self.tick)
        }
    }

    /// One pass over every telemost record. Also called when the app comes back
    /// to the foreground, where the interesting case is a phone that spent the
    /// night asleep and woke up with hours already burned.
    func checkNow() async {
        guard !running else { return }
        running = true
        defer { running = false }

        for record in telemostRecords() {
            if await act(on: record) { return }   // one renewal per pass — each restarts a container
        }
    }

    /// The user answered the expiry warning. Renews the warned record even though
    /// the tunnel is in use — they just told us the drop is acceptable.
    func renewFromWarning() async {
        guard let id = warning?.id,
              let record = connections.connections.first(where: { $0.id == id })
        else { warning = nil; return }
        warning = nil
        _ = await renew(record)
    }

    /// #469: the alert captures the record id while its content is built, so the
    /// renew no longer depends on `warning` surviving SwiftUI's dismissal write
    /// (which lands before a deferred Task runs).
    func renew(recordID id: UUID) async {
        warning = nil
        guard let record = connections.connections.first(where: { $0.id == id }) else { return }
        _ = await renew(record)
    }

    /// Dismiss without renewing. The policy will raise it again on a later pass
    /// only if the record changes — a warning the user has already refused should
    /// not reappear every quarter hour.
    func dismissWarning() { warning = nil }

    // MARK: - Deciding

    private func telemostRecords() -> [ConnectionRecord] {
        connections.connections.filter {
            if case .olcrtc(let p) = $0.details { return p.carrier == "telemost" }
            return false
        }
    }

    func input(for record: ConnectionRecord, now: Date = Date()) -> TelemostRenewalPolicy.Input {
        guard case .olcrtc(let params) = record.details else {
            return .init(now: now, roomCreatedAt: nil, isRidingThisRoom: false,
                         lastTunnelActivity: nil, alternativeRecordID: nil,
                         hasYandexSession: false)
        }
        let riding = tunnel.connectedRecord?.id == record.id
        return .init(
            now:                 now,
            roomCreatedAt:       params.roomCreatedAt,
            isRidingThisRoom:    riding,
            lastTunnelActivity:  TunnelManager.lastTunnelActivityDate,
            alternativeRecordID: alternative(to: record)?.id,
            hasYandexSession:    YandexSessionStore.hasStoredSession())
    }

    /// Another saved protocol on the SAME host. Resolved from local records, NOT
    /// from an SSH scan: this runs unattended and must not open a connection just
    /// to ask a question it can answer offline.
    private func alternative(to record: ConnectionRecord) -> ConnectionRecord? {
        guard let host = host(of: record) else { return nil }
        let siblingIDs = ([host.lastConnectionID] + (host.extraConnectionIDs ?? []))
            .compactMap { $0 }
            .filter { $0 != record.id }
        return siblingIDs
            .compactMap { id in connections.connections.first { $0.id == id } }
            .first { rec in
                if case .olcrtc(let p) = rec.details { return p.carrier != "telemost" }
                return false
            }
    }

    private func host(of record: ConnectionRecord) -> ServerHost? {
        hosts.hosts.first {
            $0.lastConnectionID == record.id || ($0.extraConnectionIDs ?? []).contains(record.id)
        }
    }

    // MARK: - Acting

    /// Returns true when it did something that restarts a container, so the
    /// caller stops for this pass.
    private func act(on record: ConnectionRecord) async -> Bool {
        switch TelemostRenewalPolicy.decide(input(for: record)) {
        case .doNothing, .ageUnknown, .waitForIdle:
            return false

        case .warnExpiringSoon(let minutes):
            // Only speaks up once per record — re-publishing an identical warning
            // on every tick would turn a useful alert into wallpaper.
            if warning?.id != record.id {
                warning = Warning(id: record.id, minutesLeft: minutes, recordName: record.name)
                LogStore.shared.log(.provisioning,
                    "⚠︎ Telemost room for \(record.name) expires in ~\(minutes) min " +
                    "and the tunnel is in use — waiting for the user")
            }
            return false

        case .switchThenRenew(let altID):
            guard let alt = connections.connections.first(where: { $0.id == altID }) else { return false }
            LogStore.shared.log(.provisioning,
                "▶ Moving the tunnel to \(alt.name) before renewing the telemost room")
            // #469 was: `tunnel.disconnect()` then `connect` — `connect` now
            // switches by itself, and does so only after the old engine has
            // really stopped (the manual pair raced its own teardown).
            tunnel.connect(record: alt)
            // Renew on the NEXT pass: the move has to actually land first, and
            // this way the policy re-checks against reality instead of against
            // an assumption about what the reconnect did.
            return true

        case .renewNow, .renewExpired:
            return await renew(record)
        }
    }

    private func renew(_ record: ConnectionRecord) async -> Bool {
        guard case .olcrtc(let params) = record.details,
              let host = host(of: record),
              let secret = hosts.secret(for: host),
              let container = containerName(for: record, host: host)
        else { return false }

        // #470: the user is running an SSH op on this host right now (install,
        // rotation, reconfigure). Two sessions restarting the same container is
        // how a half-written config survives. Try again on the next pass — the
        // policy starts five hours before the room expires, so there is time.
        guard !Provisioner.busyHostIDs.contains(host.id) else {
            LogStore.shared.log(.provisioning,
                "• Telemost renewal for \(record.name) deferred — the server is busy with another operation")
            return false
        }

        let room: TelemostRoom
        do {
            room = try await TelemostRoomService.createRoom()
        } catch {
            // The reason, never the credential.
            LogStore.shared.log(.provisioning,
                "✗ Automatic Telemost renewal could not create a room: \(error.localizedDescription)")
            return false
        }
        LogStore.shared.log(.provisioning,
            "✓ Automatic renewal: new Telemost room \(room.id.prefix(8))…")

        // Move the record FIRST. Applying the room restarts the container, which
        // kills the command carrying it when the tunnel runs through that room —
        // the write lands, the confirmation does not. Recording the new room only
        // on the success path would leave the record pointing at a room that is
        // expired by definition. Same reasoning as ServersView.applyRoomLocally.
        var moved = params
        moved.roomID        = room.id
        moved.roomCreatedAt = Date()
        var updated = record
        updated.details = .olcrtc(moved)
        connections.update(updated)

        let wasRiding = tunnel.connectedRecord?.id == record.id
        do {
            _ = try await provisioner.reconfigure(
                on: host, secret: secret, containerName: container,
                options: InstallOptions(carrier:   params.carrier,
                                        transport: params.transport,
                                        roomID:    room.id))
            LogStore.shared.log(.provisioning, "✓ Server moved to the new Telemost room")
        } catch {
            // Expected when renewing the protocol the command itself is riding.
            LogStore.shared.log(.provisioning,
                "• Telemost renewal command ended early (\(error.localizedDescription)) — " +
                "the room was written before the restart; reconnecting to confirm")
        }

        warning = nil
        if wasRiding {
            // `TunnelManager.lastRecord` is a connect-time snapshot, so without
            // the disconnect the reconnect loop would keep dialling the room that
            // just expired (OLC-1014).
            // #469 was: disconnect() + connect() — see `TunnelManager.connect`.
            // A same-record connect while live is idempotent, so the fresh room
            // has to go through an explicit teardown: disconnect, then dial once
            // the engine is down (`connect` waits for that itself now).
            tunnel.disconnect()
            if let fresh = connections.connections.first(where: { $0.id == record.id }) {
                tunnel.connect(record: fresh)
            }
        }
        return true
    }

    /// The container this record's protocol runs in. The primary keeps the name
    /// the install gave it; a sibling carrier is `<base>-<carrier>` (#452).
    private func containerName(for record: ConnectionRecord, host: ServerHost) -> String? {
        guard let base = host.lastContainerName else { return nil }
        guard host.lastConnectionID == record.id else {
            guard case .olcrtc(let p) = record.details else { return nil }
            return SSHRunner.siblingContainerName(base: base, carrier: p.carrier)
        }
        return base
    }
}
