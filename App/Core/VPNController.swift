import Foundation
import NetworkExtension

// MARK: - VPNController (#vpn)
//
// Main-app control plane for the system-VPN (packet-tunnel) mode. In VPN mode
// the app never runs the Go core itself — the olcrtc-tunnel extension does —
// so this controller only drives NETunnelProviderManager: save the
// configuration, start/stop the tunnel, observe status, and exchange
// stats/log messages with the provider.
//
// Deliberately self-contained: it does not touch TunnelManager or OlcrtcEngine —
// TunnelManager's `.vpn` mode branch delegates here (#vpn), and the user-facing
// strings go through L10n (`vpnSettingsEntryName`, `vpnCapabilityUnavailable_fmt`).
//
// The manager flow below follows vpn-impl-decisions.md Q4 exactly:
//   1. loadAllFromPreferences, reuse managers.first (NEVER create duplicates —
//      each extra save adds another entry under Settings > VPN).
//   2. Fresh NETunnelProviderProtocol: providerBundleIdentifier of the appex,
//      a non-nil serverAddress (save fails on nil), providerConfiguration from
//      VPNConfig (String/Int values only).
//   3. isEnabled = true, then saveToPreferences. THE FIRST SAVE on a device
//      shows the system consent alert ("OlcRTC" Would Like to Add VPN
//      Configurations). User denial — or a build whose Network Extension
//      entitlement was stripped by free-Apple-ID re-signing — surfaces HERE as
//      an error; that is the runtime capability gate (iOS offers no way to
//      introspect your own entitlements), captured into `capability`.
//   4. loadFromPreferences AGAIN — MANDATORY. Skipping it makes
//      startVPNTunnel throw NEVPNErrorDomain .configurationInvalid
//      ("Missing protocol or protocol has invalid type").
//   5. Subscribe .NEVPNStatusDidChange on manager.connection BEFORE starting.
//   6. startVPNTunnel(options: nil).

@MainActor
final class VPNController: ObservableObject {

    // MARK: Types

    /// Whether this install can use the system VPN at all. `.unknown` until
    /// the first saveToPreferences attempt (probing eagerly would itself fire
    /// the consent alert, so the probe is lazy by design); `.unavailable`
    /// carries a human-readable reason (consent denied / entitlement stripped
    /// by free-Apple-ID sideload signing → the UI should fall back to proxy
    /// mode).
    enum VPNCapability: Equatable {
        case unknown
        case available
        case unavailable(String)
    }

    /// NEVPNStatus mirrored into an Equatable value type the UI (and later
    /// TunnelManager's mode branch) can switch over without importing
    /// NetworkExtension semantics.
    enum Status: String, Equatable {
        case invalid, disconnected, connecting, connected, reasserting, disconnecting

        init(_ status: NEVPNStatus) {
            switch status {
            case .invalid:       self = .invalid
            case .disconnected:  self = .disconnected
            case .connecting:    self = .connecting
            case .connected:     self = .connected
            case .reasserting:   self = .reasserting
            case .disconnecting: self = .disconnecting
            @unknown default:    self = .invalid
            }
        }
    }

    struct VPNControllerError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // MARK: Constants

    /// Bundle id of the packet-tunnel appex (project.yml target olcrtc-tunnel).
    /// Derived from the app's own bundle id — the appex is always
    /// `<app id>.tunnel`. A hard-coded literal breaks VPN mode in any rebuild
    /// under a different bundle id (a fork signed with its own team): the
    /// system finds no such provider and the tunnel silently stays disconnected.
    static let providerBundleIdentifier =
        (Bundle.main.bundleIdentifier ?? "io.github.hotelk52339.olcrtc-ios") + ".tunnel"

    /// Shown under Settings > VPN next to the toggle.
    private static var localizedDescription: String { L10n.vpnSettingsEntryName.localized() }

    // MARK: Published state

    @Published private(set) var status: Status = .invalid
    @Published private(set) var capability: VPNCapability = .unknown
    /// Last provider-reported disconnect reason (iOS fetchLastDisconnectError),
    /// filled when the tunnel drops without a local stop() call.
    @Published private(set) var lastDisconnectReason: String?

    // MARK: Private state

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    /// Set while stop() is in flight so an expected .disconnected does not
    /// trigger a disconnect-error fetch.
    private var stopRequested = false

    deinit {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    }

    // MARK: Capability probe (lazy, side-effect free)

    /// Refreshes `capability` WITHOUT saving anything: if a tunnel
    /// configuration already exists in preferences, a previous save succeeded,
    /// so the entitlement provably works. An empty result stays `.unknown` —
    /// the definitive probe is the first real start(), because a dry-run save
    /// would itself pop the system consent alert.
    func probeCapability() async {
        guard capability == .unknown else { return }
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences() else { return }
        if !managers.isEmpty { capability = .available }
        // boc #469 was: the managers were read for the capability bit and
        // discarded, so a tunnel that was ALREADY running — the app relaunched
        // under it, or it was started from iOS Settings — was invisible: the
        // hero said "Disconnected" while the whole device was tunnelled, and
        // the only way to stop it was Settings > VPN. Adopt the first manager,
        // observe it, and publish its real status so the bridge sees the truth.
        if manager == nil, let existing = managers.first {
            manager = existing
            observeStatus(of: existing)
            status = Status(existing.connection.status)
        }
        // eoc #469
    }

    // MARK: Start

    /// Saves (or updates) the tunnel configuration and starts the VPN.
    /// Throws on save/start failure; save failures caused by a missing NE
    /// entitlement or denied consent also flip `capability` to `.unavailable`.
    func start(_ config: VPNConfig) async throws {
        // 1. Reuse-first-or-create.
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        // 2. Protocol configuration.
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.providerBundleIdentifier
        // serverAddress must be non-nil or the save fails; a WebRTC carrier
        // has no stable server IP, so show the room (it appears in Settings).
        proto.serverAddress = config.roomID.isEmpty ? "olcrtc" : config.roomID
        proto.providerConfiguration = config.providerConfiguration()
        manager.protocolConfiguration = proto
        manager.localizedDescription = Self.localizedDescription
        manager.isEnabled = true
        // On-demand deliberately OFF: the tunnel only runs when the user asks.

        // 3. Save — the capability gate.
        do {
            try await manager.saveToPreferences()
        } catch {
            if let reason = Self.capabilityFailureReason(error) {
                capability = .unavailable(reason)
                throw VPNControllerError(reason)
            }
            throw error
        }
        capability = .available

        // 4. Mandatory re-load after every save.
        try await manager.loadFromPreferences()
        self.manager = manager

        // 5. Observe BEFORE starting so no transition is missed.
        observeStatus(of: manager)
        stopRequested = false
        lastDisconnectReason = nil
        status = Status(manager.connection.status)

        // 6. Go.
        try manager.connection.startVPNTunnel(options: nil)
    }

    // MARK: Stop

    /// Asks the provider to stop (provider receives stopTunnel(.userInitiated)).
    /// Status flows back through the .NEVPNStatusDidChange observer.
    func stop() {
        stopRequested = true
        manager?.connection.stopVPNTunnel()
    }

    // boc #470: `providerConfiguration` keeps the room key and the WB token in
    // the system's VPN profile for as long as the profile exists — a secret at
    // rest outside the Keychain, long after the session ended. Blank the two
    // once the tunnel is down. `start()` writes the full configuration before
    // every launch, so nothing depends on them surviving; and this re-saves an
    // EXISTING profile (never `removeFromPreferences`, which would re-prompt
    // for consent).
    private func scrubStoredSecrets() {
        guard let manager, manager.connection.status == .disconnected,
              let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              var config = proto.providerConfiguration, !config.isEmpty else { return }
        let names = VPNConfig.secretConfigKeys
        // Nothing to do when they are already blank — a save per status change
        // would be pointless churn against the system's preferences store.
        guard names.contains(where: { !((config[$0] as? String) ?? "").isEmpty }) else { return }
        for name in names { config[name] = "" }
        proto.providerConfiguration = config
        manager.protocolConfiguration = proto
        Task { try? await manager.saveToPreferences() }
    }
    // eoc #470

    // MARK: Provider messages

    /// Provider stats via NETunnelProviderSession.sendProviderMessage
    /// (answered by PacketTunnelProvider.handleAppMessage "stats" with a JSON
    /// blob: state / running / tunnelActive / rxBytes / txBytes / uptime).
    /// nil when no session exists or the provider is not running.
    func stats() async -> Data? {
        await sendProviderMessage("stats")
    }

    /// Tail of the extension's in-process log ring buffer (UTF-8 text,
    /// newline-separated) via handleAppMessage "logs".
    func logsTail() async -> String? {
        guard let data = await sendProviderMessage("logs") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func sendProviderMessage(_ message: String) async -> Data? {
        guard let session = manager?.connection as? NETunnelProviderSession else { return nil }
        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(Data(message.utf8)) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                // Session not in a state that can deliver messages
                // (provider not running) — nothing to report.
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: Status observation

    private func observeStatus(of manager: NETunnelProviderManager) {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.statusDidChange() }
        }
    }

    private func statusDidChange() {
        guard let manager else { return }
        let previous = status
        let current = Status(manager.connection.status)
        status = current

        // Post-mortem for unexpected drops: the provider's startTunnel/
        // stopTunnel error (if any) is retained by the system and readable
        // after the fact (iOS 16+; deployment target is 17).
        let wasUp = previous == .connected || previous == .connecting || previous == .reasserting
        if current == .disconnected, wasUp, !stopRequested {
            fetchLastDisconnectError()
        }
        if current == .disconnected {
            stopRequested = false
            scrubStoredSecrets()   // #470
        }
    }

    private func fetchLastDisconnectError() {
        manager?.connection.fetchLastDisconnectError { [weak self] error in
            guard let error else { return }
            let reason = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastDisconnectReason = reason
                // #469: `status` was published BEFORE this fetch returned, so the
                // bridge (`TunnelManager.vpnStatusChanged`) mapped the drop with
                // `reason: nil` and the user always saw the generic "VPN tunnel
                // disconnected". Re-emit the same status now that the cause is
                // known; the bridge maps it again with the reason attached.
                if self.status == .disconnected {
                    let same = self.status
                    self.status = same
                }
            }
        }
    }

    // MARK: Capability error classification

    /// Maps a saveToPreferences failure to a "this install cannot do VPN"
    /// reason, or nil for ordinary transient errors. The missing-entitlement /
    /// consent-denied failure shapes observed in the wild:
    ///   - NEConfigurationErrorDomain code 10 ("permission denied") — the
    ///     private configuration-store domain used when the NE entitlement is
    ///     absent (free-Apple-ID re-signed builds).
    ///   - NEVPNErrorDomain code 5 (.configurationReadWriteFailed) — the same
    ///     failure surfaced through the public VPN error domain.
    ///   - Any error whose text says "permission denied" — belt and braces,
    ///     the domains above are not API-stable.
    static func capabilityFailureReason(_ error: Error) -> String? {
        let ns = error as NSError
        let permissionDenied =
            (ns.domain == "NEConfigurationErrorDomain" && ns.code == 10)
            || (ns.domain == NEVPNErrorDomain && ns.code == NEVPNError.Code.configurationReadWriteFailed.rawValue)
            || ns.localizedDescription.lowercased().contains("permission denied")
        guard permissionDenied else { return nil }
        return L10n.vpnCapabilityUnavailable_fmt.formatted(ns.localizedDescription)
    }
}
