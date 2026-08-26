import SwiftUI

// MARK: - ServersView
//
// Third tab. Manages SSH credentials for VPS hosts where we can install /
// uninstall olcrtc, plus triggers those operations from the device.
//
// #258: SINGLE-SOURCE display model (replaces the old dual-source
// `statusIconInfo`, which read `provisioner.status` + per-host `readiness`
// together and wrote optimistic base states mid-flight — the cause of the
// "status jumps"). A host now shows exactly ONE of:
//   • .base(HostBase)            — what the server IS; set ONLY by a confirmed probe
//   • .running(op, phase, note)  — what we're DOING; steady amber, phases advance
//                                  forward only, never touches base state
//   • .failed(op, phase, msg)    — an op threw; shown over the last base, with Retry
// The dot stays amber for the whole operation and changes colour exactly once,
// at the terminal probe result (`.animation(.easeInOut, value: display)`).
//
// Status / phase strings here are hardcoded English to match this file's existing
// convention (the old statusIconInfo did the same); menu/action labels reuse the
// existing L10n cases. Promoting these to L10n is a separate cleanup.

struct ServersView: View {
    @ObservedObject var serverStore: ServerHostStore
    @ObservedObject var connections: ConnectionStore
    /// #339: "Container logs" routes to the Logs tab through this app-level
    /// router (MainTabView switches the tab, LogsView consumes).
    /// #334 was: `let logsRouter` — now observed so the card reacts to
    /// `fetchingHostID` and shows a busy indicator during a container-log fetch.
    @ObservedObject var logsRouter: LogsRouter
    /// Per-tab lifecycle, NOT a shared singleton — intentional split from
    /// `TunnelManager.shared` / `SettingsStore.shared` / `LogStore.shared`.
    @StateObject  private var provisioner = Provisioner()
    /// #419: bot registry (shared with Settings). The per-server bot sheet picks
    /// a bot from it; the token is read from the Keychain at deploy time.
    @ObservedObject var botStore: BotStore
    /// #452: the tunnel, so a protocol row on the host card can connect directly
    /// ("pick which protocol to tunnel through, right from Manage VPS").
    @ObservedObject var tunnel: TunnelManager

    @State private var showAdd        = false
    @State private var editHost       : ServerHost?
    @State private var installFor     : ServerHost?
    // #452 was: reconfigureFor : ServerHost? — now a targeted request (container
    // + record + seed values), so a protocol row reconfigures ITS container.
    @State private var reconfigureRequest : ReconfigureRequest?
    @State private var botConfigFor   : ServerHost?   // #419: per-server bot sheet
    // #339 was: logsPayload (ContainerLogsPayload?) — the container-logs sheet
    // is gone; the action routes to the Logs tab instead.
    // #258 was: readiness[id] + activeHostID (two competing display sources).
    // Now a single per-host display state; base is only ever set from a probe.
    @State private var display        : [UUID: HostDisplay] = [:]
    @State private var vpsStats       : [UUID: SSHRunner.VPSStats] = [:]
    @State private var pingLatencies  : [UUID: Double?] = [:]   // ms, nil=unreachable, absent=not pinged
    // #374: when each host was last probed, so the periodic sweep only re-pings
    // hosts whose last ping is older than the interval (instead of every host
    // every tick). Absent → never pinged → due immediately.
    @State private var lastPing       : [UUID: Date] = [:]
    @State private var scanFor        : ServerHost?
    @State private var foundContainers: [SSHRunner.FoundContainer] = []
    @State private var shareConn      : ConnectionRecord?   // #304: share the host's linked connection
    @State private var shareFullAccess: FullAccessShareRequest?   // #135: full-access (SSH) share
    @State private var alertText           : String?
    @State private var removeHost          : ServerHost?
    @State private var uninstallConfirmHost    : ServerHost?
    @State private var deepUninstallConfirmHost: ServerHost?
    @State private var rebootConfirmHost       : ServerHost?
    // #303: confirm before recovering/adding a ConnectionRecord from an
    // already-installed-but-unlinked host (#302 auto-detect with no
    // lastConnectionID).
    @State private var recoverConfirmHost      : ServerHost?
    // #314: fallback when #303 recovery finds server.yaml unreadable or
    // unparseable — confirm before rotating ~/.olcrtc_key (destructive for
    // every other client of that server).
    @State private var rotateKeyConfirmHost    : ServerHost?
    // boc #452: multi-carrier host card. `carrierRows` caches the per-host
    // protocol list (SSHRunner.CarrierInfo, from provisioner.listCarriers);
    // the request states drive the add-protocol sheet, the remove confirm and
    // the per-row recover confirm; `carrierBusyHostID` serializes the
    // outside-`run` protocol ops (add/remove/sibling start/stop), mirroring
    // how rotateKey/recoverConnection run without a HostOp.
    @State private var carrierRows          : [UUID: [SSHRunner.CarrierInfo]] = [:]
    @State private var addProtocolFor       : ServerHost?
    @State private var removeCarrierConfirm : CarrierRemoveRequest?
    @State private var recoverRowRequest    : CarrierRecoverRequest?
    @State private var carrierBusyHostID    : UUID?
    // eoc #452
    // #374 was: pingTimer (Timer?) — a repeating Timer that re-pinged EVERY
    // host every tick, even mid-op. Replaced by a structured `.task` sweep loop
    // (autoPingLoop) tied to the view lifecycle, which cancels cleanly on
    // disappear (no manual invalidate needed) and only re-pings stale hosts.

    @ObservedObject private var settings = SettingsStore.shared

    private var coreStack: some View {
        NavigationStack {
            List {
                matrixSection

                if serverStore.hosts.isEmpty {
                    emptyState
                } else {
                    ForEach(serverStore.hosts) { host in
                        hostCard(host)
                    }
                    .onDelete { serverStore.remove(at: $0) }
                }
            }
            .navigationTitle(L10n.serversTitle.localized())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // #359: icon-only "+" needs an a11y label (reused newServerTitle).
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L10n.newServerTitle.localized())
                }
            }
            // #374: structured sweep loop tied to the view lifecycle — SwiftUI
            // cancels it when the view disappears, replacing the old
            // onAppear-start / onDisappear-invalidate Timer pair.
            .task { await autoPingLoop() }
            // #258: route the provisioner's progress stream into the running host's
            // phase/subtitle ONLY — never the base state or the dot colour.
            .onChange(of: provisioner.status) { _, status in
                guard case .running(let msg) = status else { return }
                advancePhase(note: msg)
            }
            .sheet(isPresented: $showAdd) {
                // #295: pass every existing label so the sheet can reject a
                // duplicate (case-insensitive / sanitised-prefix) name.
                // #451: the sheet now returns an SSHSecret (password OR key).
                AddServerHostView(otherLabels: serverStore.hosts.map(\.label)) { host, secret in
                    serverStore.add(host, secret: secret)
                }
            }
            .sheet(item: $editHost) { host in
                // #451: prefill all credential kinds; `password(for:)` returns
                // the key text for key hosts, so gate it on authMethod and use
                // the dedicated accessors for the key fields.
                AddServerHostView(existing: host,
                                  existingPassword: host.authMethod == .privateKey
                                      ? nil : serverStore.password(for: host),
                                  existingKey: serverStore.privateKey(for: host),
                                  existingPassphrase: serverStore.keyPassphrase(for: host),
                                  otherLabels: serverStore.hosts.filter { $0.id != host.id }.map(\.label)) { updated, secret in
                    serverStore.update(updated, secret: secret)
                }
            }
            .sheet(item: $installFor) { host in
                // #452: multi-protocol install plan (primary + extras).
                InstallOptionsView { primary, extras in
                    Task { await install(host, primary: primary, extras: extras) }
                }
            }
            .sheet(item: $reconfigureRequest) { req in
                // #452: targeted at one protocol's container (value snapshot,
                // #330 rule) and seeded from its current carrier/transport/room.
                ReconfigureOptionsView(initialCarrier: req.initialCarrier,
                                       initialTransport: req.initialTransport,
                                       initialRoom: req.initialRoom) { options in
                    Task {
                        await reconfigure(req.host, containerName: req.containerName,
                                          recordID: req.recordID, options: options)
                    }
                }
            }
            // #419: per-server bot settings sheet. #451: passes the SSHSecret.
            .sheet(item: $botConfigFor) { host in
                BotSettingsView(host: host, botStore: botStore,
                                provisioner: provisioner,
                                secret: serverStore.secret(for: host))
            }
            // #339 was: .sheet(item: $logsPayload) { ContainerLogsView(payload:) }
            .sheet(item: $scanFor) { host in
                containerScanSheet(host: host)
            }
            // #304: "Share connection" moved here from the Connections tab.
            .sheet(item: $shareConn) { conn in
                ShareConnectionView(conn: conn)
            }
            // #135: full-access (co-admin) share — the same sheet, with the SSH
            // payload that unlocks the destructive opt-in section.
            .sheet(item: $shareFullAccess) { req in
                ShareConnectionView(conn: req.conn, fullAccess: req.payload)
            }
            .alert(L10n.okPrompt.localized(), isPresented: Binding(
                get: { alertText != nil },
                set: { if !$0 { alertText = nil } }
            )) {
                Button(L10n.ok.localized()) { alertText = nil }
            } message: {
                Text(alertText ?? "")
            }
            .confirmationDialog(
                removeHost.map { L10n.removeHostConfirmTitle.formatted($0.label) } ?? "",
                isPresented: Binding(
                    get: { removeHost != nil },
                    set: { if !$0 { removeHost = nil } }
                ),
                titleVisibility: .visible,
                presenting: removeHost
            ) { host in
                Button(L10n.actionRemoveFromList.localized(), role: .destructive) {
                    removeFromList(host)
                    removeHost = nil
                }
                Button(L10n.cancel.localized(), role: .cancel) { removeHost = nil }
            } message: { _ in
                Text(L10n.removeHostConfirmMessage.localized())
            }
            .confirmationDialog(
                L10n.uninstallConfirmTitle.localized(),
                isPresented: Binding(
                    get: { uninstallConfirmHost != nil },
                    set: { if !$0 { uninstallConfirmHost = nil } }
                ),
                titleVisibility: .visible,
                presenting: uninstallConfirmHost
            ) { host in
                Button(L10n.actionUninstall.localized(), role: .destructive) {
                    uninstallConfirmHost = nil
                    Task { await uninstall(host) }
                }
                Button(L10n.cancel.localized(), role: .cancel) { uninstallConfirmHost = nil }
            } message: { _ in
                Text(L10n.uninstallConfirmBody.localized())
            }
            .confirmationDialog(
                L10n.actionDeepUninstall.localized(),
                isPresented: Binding(
                    get: { deepUninstallConfirmHost != nil },
                    set: { if !$0 { deepUninstallConfirmHost = nil } }
                ),
                titleVisibility: .visible,
                presenting: deepUninstallConfirmHost
            ) { host in
                Button(L10n.actionDeepUninstall.localized(), role: .destructive) {
                    deepUninstallConfirmHost = nil
                    Task { await deepUninstall(host, removeImage: false) }
                }
                Button(L10n.cancel.localized(), role: .cancel) { deepUninstallConfirmHost = nil }
            } message: { _ in
                Text(L10n.deepUninstallConfirmBody.localized())
            }
            .confirmationDialog(
                L10n.rebootConfirmTitle.localized(),
                isPresented: Binding(
                    get: { rebootConfirmHost != nil },
                    set: { if !$0 { rebootConfirmHost = nil } }
                ),
                titleVisibility: .visible,
                presenting: rebootConfirmHost
            ) { host in
                Button(L10n.actionReboot.localized(), role: .destructive) {
                    rebootConfirmHost = nil
                    Task { await reboot(host) }
                }
                Button(L10n.cancel.localized(), role: .cancel) { rebootConfirmHost = nil }
            } message: { _ in
                Text(L10n.rebootConfirmBody.localized())
            }
            // #303: recover/add a ConnectionRecord from this host's deployed
            // server.yaml — read-only on the server, only adds locally.
            .confirmationDialog(
                L10n.recoverConfirmTitle.localized(),
                isPresented: Binding(
                    get: { recoverConfirmHost != nil },
                    set: { if !$0 { recoverConfirmHost = nil } }
                ),
                titleVisibility: .visible,
                presenting: recoverConfirmHost
            ) { host in
                Button(L10n.recoverConfirmAction.localized()) {
                    recoverConfirmHost = nil
                    Task { await recoverConnection(host) }
                }
                Button(L10n.cancel.localized(), role: .cancel) { recoverConfirmHost = nil }
            } message: { _ in
                Text(L10n.recoverConfirmBody.localized())
            }
            // #314: #303's fallback branch — server.yaml was unreadable or
            // unparseable, so offer to generate a new key (rotate ~/.olcrtc_key,
            // repair server.yaml, restart) instead of just failing. Destructive:
            // the new key cuts off every other client of this server.
            .confirmationDialog(
                L10n.rotateKeyConfirmTitle.localized(),
                isPresented: Binding(
                    get: { rotateKeyConfirmHost != nil },
                    set: { if !$0 { rotateKeyConfirmHost = nil } }
                ),
                titleVisibility: .visible,
                presenting: rotateKeyConfirmHost
            ) { host in
                Button(L10n.rotateKeyConfirmAction.localized(), role: .destructive) {
                    rotateKeyConfirmHost = nil
                    Task { await rotateKey(host) }
                }
                Button(L10n.cancel.localized(), role: .cancel) { rotateKeyConfirmHost = nil }
            } message: { _ in
                Text(L10n.rotateKeyConfirmBody.localized())
            }
        }
    }

    var body: some View {
        // #452: the multi-carrier modals (add-protocol sheet, remove/recover
        // confirms) are split off the main chain — with them inline the Swift
        // type-checker timed out on ServersView.body ("unable to type-check
        // this expression in reasonable time").
        carrierModals(coreStack)
    }

    @ViewBuilder
    private func carrierModals(_ content: some View) -> some View {
        content
            .sheet(item: $addProtocolFor) { host in
                InstallOptionsView(limitToCarriers: missingCarriers(host),
                                   singleOnly: true) { options, _ in
                    Task { await addCarrier(host, options: options) }
                }
            }
            .confirmationDialog(
                removeCarrierConfirm.map {
                    L10n.removeProtocolConfirmTitle_fmt.formatted(
                        CarrierTransportMatrix.carrierLabel($0.row.provider))
                } ?? "",
                isPresented: Binding(
                    get: { removeCarrierConfirm != nil },
                    set: { if !$0 { removeCarrierConfirm = nil } }
                ),
                titleVisibility: .visible,
                presenting: removeCarrierConfirm
            ) { req in
                Button(L10n.removeProtocolAction.localized(), role: .destructive) {
                    removeCarrierConfirm = nil
                    Task { await removeCarrier(req.host, row: req.row) }
                }
                Button(L10n.cancel.localized(), role: .cancel) { removeCarrierConfirm = nil }
            } message: { _ in
                Text(L10n.removeProtocolConfirmBody.localized())
            }
            .confirmationDialog(
                L10n.recoverConfirmTitle.localized(),
                isPresented: Binding(
                    get: { recoverRowRequest != nil },
                    set: { if !$0 { recoverRowRequest = nil } }
                ),
                titleVisibility: .visible,
                presenting: recoverRowRequest
            ) { req in
                Button(L10n.recoverConfirmAction.localized()) {
                    recoverRowRequest = nil
                    Task {
                        await recoverConnection(req.host, containerName: req.container,
                                                configFile: req.file, asExtra: !req.isPrimary)
                    }
                }
                Button(L10n.cancel.localized(), role: .cancel) { recoverRowRequest = nil }
            } message: { _ in
                Text(L10n.recoverConfirmBody.localized())
            }
    }

    private func removeFromList(_ host: ServerHost) {
        if let idx = serverStore.hosts.firstIndex(where: { $0.id == host.id }) {
            serverStore.remove(at: IndexSet([idx]))
        }
    }

    // MARK: Compatibility matrix

    private var matrixSection: some View {
        Section {
            OlcCard { MatrixView() }
                .olcCardRow()
        } header: {
            Text(L10n.carrierTransportMatrix.localized())
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        Section {
            // #258: shared OlcEmptyState with a primary CTA (was a bare VStack).
            OlcEmptyState(systemImage: "externaldrive.connected.to.line.below",
                          title: L10n.emptyNoServers.localized(),
                          hint: L10n.emptyNoServersHint.localized(),
                          ctaTitle: L10n.newServerTitle.localized()) {
                showAdd = true
            }
            .olcCardRow()
        }
    }

    // MARK: Display-state helpers (single source of truth)

    /// The host's current display state. Before any probe, seed a conservative
    /// base from persisted data: a known container → `.stopped` (so Start/Stop and
    /// the metrics surface, and we never offer a reinstall by mistake); otherwise
    /// `.unknown` ("tap Check"). Never asserts a running container without a probe.
    private func displayState(_ host: ServerHost) -> HostDisplay {
        display[host.id] ?? .base(.seed(lastContainerName: host.lastContainerName))
    }

    /// The base under whatever is currently shown (running/failed keep the base
    /// they started from). Drives the menu / button shape.
    private func currentBase(_ host: ServerHost) -> HostBase { displayState(host).base }

    private func hasContainer(_ host: ServerHost) -> Bool { currentBase(host).hasContainer }
    private func isRunning(_ host: ServerHost)   -> Bool { currentBase(host) == .running }

    /// #304: the ConnectionRecord this host installed/owns (by `lastConnectionID`),
    /// if still present — drives the "Share connection" item on the server card.
    private func linkedConnection(_ host: ServerHost) -> ConnectionRecord? {
        guard let id = host.lastConnectionID else { return nil }
        return connections.connections.first { $0.id == id }
    }

    /// #135: builds the full-access (co-admin) share request for a host + its
    /// linked connection — the connection URI plus the SSH host/port/login and
    /// the password read live from the Keychain (ServerHostStore → KeychainHelper).
    /// Returns nil when no password is stored, so the destructive item silently
    /// no-ops rather than sharing a credential-less, useless blob.
    /// #451: key-auth hosts NEVER produce a request — a full-access link would
    /// have to embed the private key (a far bigger blast radius than a
    /// password, and beyond QR capacity); the menu item explains instead
    /// (see menuItems), and this guard is the defence-in-depth backstop.
    private func fullAccessRequest(_ host: ServerHost, conn: ConnectionRecord) -> FullAccessShareRequest? {
        guard host.authMethod != .privateKey,
              let password = serverStore.password(for: host) else { return nil }
        let uri: String
        switch conn.details {
        case .olcrtc(let p): uri = OlcrtcURI.encode(p)
        }
        let payload = FullAccessShare(
            uri: uri,
            label: host.label,
            sshHost: host.host,
            sshPort: host.port,
            sshUsername: host.username,
            sshPassword: password)
        return FullAccessShareRequest(conn: conn, payload: payload)
    }

    /// Any host mid-operation. Operations are serialized (one provisioner), so we
    /// disable every card's actions while one runs — this also keeps `runningHostID`
    /// unambiguous for phase routing.
    private var anyBusy: Bool { display.values.contains { $0.isRunning } }
    private var actionsDisabled: Bool { anyBusy || provisioner.status.isRunning }
    private var runningHostID: UUID? { display.first { $0.value.isRunning }?.key }

    // MARK: The ONE operation driver
    //
    // Sets `.running`, lets `work` do the SSH work + the confirming probe (the
    // ONLY thing that returns a base), then makes a SINGLE terminal assignment:
    // `.base` on success, `.failed` on throw. `work` must not write `display`.

    private func run(_ op: HostOp, on host: ServerHost,
                     _ work: @escaping (_ secret: SSHSecret) async throws -> HostBase?) async {
        guard !anyBusy else { return }
        let prev = currentBase(host)
        display[host.id] = .start(op, from: prev)

        guard let secret = secret(for: host) else {
            withAnimation(.easeInOut(duration: 0.35)) {
                display[host.id] = HostDisplay.start(op, from: prev)
                    .failed(message: missingCredentialMessage(host))
            }
            return
        }

        do {
            let resolved = try await work(secret)
            // One terminal change — the probe result is authoritative (no optimism);
            // else the op's nominal target; else keep the previous base (e.g. reboot).
            let base = HostDisplay.terminalBase(op: op, probed: resolved, previous: prev)
            withAnimation(.easeInOut(duration: 0.35)) { display[host.id] = .base(base) }
        } catch {
            let current = display[host.id] ?? .start(op, from: prev)
            withAnimation(.easeInOut(duration: 0.35)) {
                display[host.id] = current.failed(message: error.localizedDescription)
            }
        }
    }

    /// Maps a provisioner progress message onto the running host: phase forward
    /// (monotonic, capped) + subtitle = the live message. Never touches base/dot.
    private func advancePhase(note: String) {
        guard let id = runningHostID else { return }
        display[id] = display[id]?.advanced(note: note)
    }

    /// Re-runs the failed op. Returns to the previous base first, then dispatches
    /// (sheet-driven ops reopen their sheet so the user reconfirms options).
    private func retry(_ op: HostOp, on host: ServerHost) async {
        if let restored = display[host.id]?.retryBase() { display[host.id] = restored }
        switch op {
        case .check:         await checkServer(host)
        case .start:         await startContainer(host)
        case .stop:          await stop(host)
        case .update:        await update(host)
        case .reboot:        await reboot(host)
        case .install:       installFor = host
        case .reconfigure:   reconfigureRequest = primaryReconfigureRequest(host)   // #452
        case .uninstall:     uninstallConfirmHost = host
        case .deepUninstall: deepUninstallConfirmHost = host
        }
    }

    // MARK: Auto-ping
    //
    // #374: a single structured sweep loop replaces the old repeating Timer
    // that re-pinged EVERY host every tick (even mid-SSH-op, even when nothing
    // had changed). Each pass:
    //   • does an immediate first ping of any never-pinged host;
    //   • when auto-ping is on, wakes every `interval` and re-pings ONLY hosts
    //     whose last ping is older than the interval (skipping fresh ones);
    //   • skips the periodic sweep entirely while an op is in flight
    //     (actionsDisabled) — checkServer already pings the host it touches;
    //   • staggers the per-host probes by a small delay so they don't all fire
    //     on the same instant.
    // The loop runs inside `.task`, so SwiftUI cancels it on disappear.

    /// Small per-host gap so a fleet doesn't fire every probe on one tick (#374).
    private static let pingStaggerSeconds: Double = 0.4

    /// How long the loop idles between checks while auto-ping is OFF or has no
    /// positive interval set — so flipping the toggle back ON resumes pinging
    /// within a few seconds instead of never (#395). Short enough to feel live,
    /// long enough not to spin.
    private static let autoPingIdlePollSeconds: Double = 5

    private func autoPingLoop() async {
        // Initial pass: ping every host that's never been pinged.
        await pingDueHosts(force: true)

        // #395 was: `guard … else { return }` — the loop exited *permanently*
        // when auto-ping was disabled (or its interval was 0), and the id-less
        // `.task` (body, line ~99) doesn't restart on a setting flip, so
        // re-enabling auto-ping on the same tab never resumed periodic pinging.
        // Now we sleep-and-recheck instead of returning, so a toggle flip is
        // picked up on the next idle poll. SwiftUI still cancels the whole `.task`
        // on view disappear (Task.sleep throws on cancel), keeping teardown clean.
        while !Task.isCancelled {
            guard settings.vpsAutoPingEnabled, settings.vpsAutoPingInterval > 0 else {
                // Disabled / no interval — idle briefly, then re-check the toggle.
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.autoPingIdlePollSeconds * 1_000_000_000))
                } catch {
                    return   // cancelled while idling
                }
                continue
            }
            let interval = TimeInterval(settings.vpsAutoPingInterval)
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return   // cancelled while sleeping
            }
            // Don't sweep on top of an in-flight SSH op — it would queue probes
            // against a host we're already talking to, and nothing's changed.
            guard !actionsDisabled else { continue }
            await pingDueHosts(force: false)
        }
    }

    /// Pings every host whose ping is stale (older than the configured
    /// interval) — or, with `force`, every host not yet pinged. Staggered.
    private func pingDueHosts(force: Bool) async {
        let interval = TimeInterval(settings.vpsAutoPingInterval)
        let now = Date()
        let due = serverStore.hosts.filter { host in
            guard let last = lastPing[host.id] else { return true }   // never pinged → due
            return force ? false : now.timeIntervalSince(last) >= interval
        }
        for (i, host) in due.enumerated() {
            if i > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.pingStaggerSeconds * 1_000_000_000))
                } catch {
                    return   // cancelled mid-stagger
                }
            }
            if Task.isCancelled { return }
            await doPing(host)
        }
    }

    private func doPing(_ host: ServerHost) async {
        let result = await NetPing.tcp(host: host.host, port: UInt16(host.port), timeout: 5)
        pingLatencies[host.id] = result.success ? result.ms : nil
        lastPing[host.id] = Date()   // #374: record so the sweep can skip fresh hosts
    }

    // MARK: Host card

    private func hostCard(_ host: ServerHost) -> some View {
        let state = displayState(host)
        return Section {
            OlcCard {
                VStack(alignment: .leading, spacing: 12) {
                    // Header: label + connection + the single complete action menu
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.label)
                                .font(.headline)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            // #337: mask the host for display when screenshot-safe
                            // mode is on (IP literals → •••.•••.•••.x; hostnames
                            // pass through). Display-only: host.host stays real.
                            Text("\(host.username)@\(IPMask.display(host.host, masked: settings.maskIPs)):\(String(host.port))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        OlcOverflowMenu(items: menuItems(host))
                            .disabled(actionsDisabled)
                    }

                    // #334: container-log fetch runs on the Logs tab (#339), so it
                    // isn't a HostOp and never reaches `statusRegion`. Surface its
                    // progress here from the router's published in-flight host.
                    containerLogBusyStrip(host)

                    statusRegion(host, state: state)

                    // #341 was: metrics only when idle on a container-bearing
                    // base — the card changed height with every state flip.
                    // Fixed footprint now: the strip is ALWAYS rendered ("—"
                    // placeholders, dimmed while an op runs).
                    metricsStrip(host, state: state)

                    // #452: per-protocol rows (multi-carrier host).
                    protocolsSection(host, state: state)

                    actionBar(host, state: state)
                }
                .animation(.easeInOut(duration: 0.35), value: state)
                // #334: fade the container-log busy strip in/out smoothly.
                .animation(.easeInOut(duration: 0.35), value: logsRouter.fetchingHostID)
            }
            // #452: lazy first load of the protocol rows (skipped while an op
            // holds the SSH lane; refreshed after every op anyway).
            .onAppear {
                guard carrierRows[host.id] == nil, host.lastContainerName != nil,
                      !actionsDisabled else { return }
                Task { await refreshCarriers(host.id) }
            }
            .olcCardRow()
        }
    }

    /// #334: a compact busy row shown only while THIS host's container-log
    /// fetch is in flight (on the Logs tab). Reuses the `.progress` status tone
    /// + OlcProgressBar, mirroring an in-card operation. The `.transition` +
    /// the card's own animation (keyed on `fetchingHostID` below) keep it from
    /// snapping in — see #335 for the start-jank lesson.
    @ViewBuilder
    private func containerLogBusyStrip(_ host: ServerHost) -> some View {
        if logsRouter.fetchingHostID == host.id {
            VStack(alignment: .leading, spacing: 8) {
                OlcStatusPill(tone: .progress,
                              title: L10n.actionContainerLogs.localized(),
                              subtitle: L10n.logsPhaseReceiving.localized()) {
                    ProgressView().controlSize(.small)
                }
                OlcProgressBar(fraction: 1)   // indeterminate-ish: the fetch has no fraction here
            }
            .transition(.opacity)
        }
    }

    // Status region — exactly one of: operation / error / base.
    // #341: fixed-height container (≈58pt) so the pill / pill+bar / failed
    // pill swap never changes the card height; the existing `.animation`
    // crossfades the content.
    // #335: the pill is now ALWAYS rendered in the same top slot — only its
    // tone/title/subtitle change — and the progress bar lives in a fixed-height
    // slot BELOW it that just fades its opacity. Previously the `.running` case
    // wrapped the pill in its own VStack while `.base`/`.failed` rendered a bare
    // pill, so when the op started the crossfade animated the pill from one
    // vertical anchor to another, overlapping the text for ~0.5s. One stable
    // pill position kills the overlap.
    @ViewBuilder
    private func statusRegion(_ host: ServerHost, state: HostDisplay) -> some View {
        let bar = statusBarFraction(state)
        VStack(alignment: .leading, spacing: 8) {
            OlcStatusPill(tone: statusTone(state),
                          title: statusTitle(state),
                          subtitle: statusSubtitle(state)) {
                if state.isRunning { ProgressView().controlSize(.small) }
            }
            // #338 was: ProgressView(value:total:).tint(amber) — extracted into
            // the shared OlcProgressBar (also used by the Logs fetch). The slot
            // is always present (fixed 4pt) so the pill above never reflows when
            // the bar appears/disappears; opacity carries the transition (#335).
            OlcProgressBar(fraction: bar ?? 0)
                .opacity(bar == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }

    // #335: per-state pill content, split out so the ONE pill above can render
    // any state without changing its position.
    private func statusTone(_ state: HostDisplay) -> OlcStatusTone {
        switch state {
        case .running:        return .progress
        case .failed:         return .error
        case .base(let b):    return b.tone
        }
    }
    private func statusTitle(_ state: HostDisplay) -> String {
        switch state {
        case .running(let op, _, _, _): return "\(op.verb)…"
        case .failed(let op, _, _, _):  return L10n.vpsOpFailed_fmt.formatted(op.verb)
        case .base(let b):              return b.title
        }
    }
    private func statusSubtitle(_ state: HostDisplay) -> String {
        switch state {
        case .running(let op, let phase, let note, _):
            return "\(note) · \(min(phase + 1, op.stepCount))/\(op.stepCount)"
        case .failed(_, let phase, let message, _):
            return "\(phase.replacingOccurrences(of: "…", with: "")) · \(message)"
        case .base(let b):
            return b.subtitle
        }
    }
    /// The progress fraction while running; nil when the bar slot is empty.
    private func statusBarFraction(_ state: HostDisplay) -> Double? {
        guard case .running(let op, let phase, _, _) = state else { return nil }
        return Double(min(phase + 1, op.stepCount)) / Double(max(op.stepCount, 1))
    }

    // #341 was: metricsRow — a conditional 4×OlcMetric two-deck row (17pt mono).
    // Now a one-line always-rendered strip: PING 27ms · DISK 36/40G · RAM
    // 241/2048M · UP 11d, dimmed while an op runs.
    private func metricsStrip(_ host: ServerHost, state: HostDisplay) -> some View {
        let stats = vpsStats[host.id]
        // #408: drop the "·" separators and pack the stats closer. The separators
        // plus their padding ate roughly a third of the row, squeezing the values
        // until they truncated ("4.4/4…", "501/19…"); the uppercase-tertiary label
        // vs. mono-primary value contrast already delineates each stat without a
        // glyph between them. #408 was: HStack(spacing: 8) with a `statDot` between
        // every OlcMiniStat.
        return HStack(spacing: 12) {
            pingMiniStat(host)
            // #346: labels through L10n (ru = en for the abbreviations); units
            // like "G"/"M"/"d" inside the values stay English.
            OlcMiniStat(label: L10n.vpsStatDisk.localized(), value: Self.shortUsage(stats?.disk))
            // #451: shortRAM, not shortUsage — a 2 GB VPS reports "407M/1967M"
            // and the 9-char "407/1967M" overflowed the 4-stat row on 375pt
            // phones, ellipsizing mid-value ("407/19…" — the reported bug).
            OlcMiniStat(label: L10n.vpsStatRAM.localized(),  value: Self.shortRAM(stats?.ram))
            OlcMiniStat(label: L10n.vpsStatUp.localized(),   value: Self.shortUptime(stats?.uptime))
            Spacer(minLength: 0)
        }
        .opacity(state.isRunning ? 0.45 : 1)
    }

    private func pingMiniStat(_ host: ServerHost) -> OlcMiniStat {
        switch pingLatencies[host.id] {
        case .some(.some(let ms)):
            // #346: "Ping" label through L10n (ru = en); "ms" stays English.
            return OlcMiniStat(label: L10n.vpsStatPing.localized(), value: String(format: "%.0fms", ms),
                               tone: ms < 100 ? Theme.Palette.green
                                   : ms < 300 ? Theme.Palette.orange : Theme.Palette.red)
        case .some(.none):
            return OlcMiniStat(label: L10n.vpsStatPing.localized(), value: "✕", tone: Theme.Palette.red)
        case .none:
            return OlcMiniStat(label: L10n.vpsStatPing.localized(), value: "—", tone: Theme.Palette.textTertiary)
        }
    }

    /// #341: compact a `df`/`free` "36G/40G" pair to "36/40G" (shared unit
    /// suffix hoisted to the right side); mixed units stay as-is. Internal
    /// static so the unit tests can pin the edge cases.
    static func shortUsage(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let u0 = parts[0].last, let u1 = parts[1].last,
              u0 == u1, u0.isLetter else { return s }
        return "\(parts[0].dropLast())/\(parts[1])"
    }

    /// #451: RAM-specific compaction. `free -m` reports MB, so a 2 GB VPS
    /// yields "407M/1967M" — shortUsage's "407/1967M" (9 mono chars) is the
    /// longest stat in the strip and the one that overflowed. When both sides
    /// are MB and the total is ≥ 1000M, convert to a shared-G form
    /// ("0.4/1.9G", 7 chars); smaller totals and anything unparseable fall
    /// through to shortUsage ("241/512M", "—", garbage passthrough).
    static func shortRAM(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              parts[0].hasSuffix("M"), parts[1].hasSuffix("M"),
              let used  = Double(parts[0].dropLast()),
              let total = Double(parts[1].dropLast()),
              total >= 1000
        else { return shortUsage(s) }
        return String(format: "%.1f/%.1fG", used / 1024, total / 1024)
    }

    /// #341: compact the `uptime` tail — "3 days" → "3d", "35 min" → "35m";
    /// the "H:MM" (<1 day) form stays as-is.
    static func shortUptime(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        return s.replacingOccurrences(of: " days", with: "d")
                .replacingOccurrences(of: " day",  with: "d")
                .replacingOccurrences(of: " min",  with: "m")
    }

    // Action bar — one contextual primary + three fixed icon-only quick
    // actions (#341: 44×44 tinted OlcIconButtons; was one antenna OlcButton).
    // Everything here is a subset of `menuItems`; nothing is card-exclusive.
    @ViewBuilder
    private func actionBar(_ host: ServerHost, state: HostDisplay) -> some View {
        HStack(spacing: 8) {
            primaryButton(host, state: state)
            OlcIconButton(systemImage: "antenna.radiowaves.left.and.right") {
                Task { await checkServer(host) }
            }
            .disabled(actionsDisabled)
            .accessibilityLabel(L10n.vpsCheckServer.localized())
            OlcIconButton(systemImage: "arrow.down.doc", tint: Theme.Palette.green) {
                logsRouter.request = .init(hostID: host.id, autofetch: true)   // #339 route
            }
            .disabled(actionsDisabled || !hasContainer(host))
            .accessibilityLabel(L10n.actionContainerLogs.localized())
            OlcIconButton(systemImage: "slider.horizontal.3", tint: Theme.Palette.orange) {
                reconfigureRequest = primaryReconfigureRequest(host)   // #452
            }
            .disabled(actionsDisabled || !hasContainer(host))
            .accessibilityLabel(L10n.actionChangeRoomTransport.localized())
            // #419: bot control — LAST in the row, available regardless of
            // container state. Adding it shrinks the fill-width primary button.
            // #427: robot glyph (custom asset — no robot SF Symbol). was: bubble.left.and.bubble.right
            OlcIconButton(assetImage: "RobotIcon", tint: Theme.Palette.accent) {
                botConfigFor = host
            }
            .disabled(actionsDisabled)
            .accessibilityLabel(L10n.botSheetTitle.localized())
        }
    }

    @ViewBuilder
    private func primaryButton(_ host: ServerHost, state: HostDisplay) -> some View {
        switch state {
        case .running:
            OlcButton(L10n.vpsWorking.localized(), role: .secondary, isBusy: true, fillWidth: true) {}
        case .failed(let op, _, _, _):
            OlcButton(L10n.actionRetry.localized(), systemImage: "arrow.clockwise",
                      role: .primary, fillWidth: true) {
                Task { await retry(op, on: host) }
            }
            .disabled(actionsDisabled)
        case .base(let b):
            if b.hasContainer {
                if b == .running {
                    OlcButton(L10n.actionStop.localized(), systemImage: "stop.fill",
                              role: .danger, fillWidth: true) {
                        Task { await stop(host) }
                    }
                    .disabled(actionsDisabled)
                } else {
                    OlcButton(L10n.actionStart.localized(), systemImage: "play.fill",
                              role: .primary, fillWidth: true) {
                        Task { await startContainer(host) }
                    }
                    .disabled(actionsDisabled)
                }
            } else {
                OlcButton(L10n.actionInstall.localized(), systemImage: "arrow.down.app",
                          role: .primary, fillWidth: true) {
                    installFor = host
                }
                .disabled(actionsDisabled)
            }
        }
    }

    // MARK: Overflow menu — the single COMPLETE action set
    //
    // #258: this is the source of truth. The card's primary + Check buttons are a
    // derived subset of these items (no more "MUST mirror card buttons" duplication).

    private func menuItems(_ host: ServerHost) -> [OlcMenuItem] {
        var items: [OlcMenuItem] = [
            .action(L10n.vpsCheckServer.localized(), systemImage: "antenna.radiowaves.left.and.right") {
                Task { await checkServer(host) }
            }
        ]

        if hasContainer(host) {
            if isRunning(host) {
                items.append(.action(L10n.actionStop.localized(), systemImage: "stop.fill", role: .destructive) {
                    Task { await stop(host) }
                })
            } else {
                items.append(.action(L10n.actionStart.localized(), systemImage: "play.fill") {
                    Task { await startContainer(host) }
                })
            }
            // #339 was: "Download container logs" → fetchLogs(host) + sheet.
            // Now routes to the Logs tab (Container category, this host) and
            // auto-starts the fetch there.
            items.append(.action(L10n.actionContainerLogs.localized(), systemImage: "arrow.down.doc") {
                logsRouter.request = .init(hostID: host.id, autofetch: true)
            })
            items.append(.action(L10n.actionChangeRoomTransport.localized(), systemImage: "slider.horizontal.3") {
                reconfigureRequest = primaryReconfigureRequest(host)   // #452
            })
            items.append(.action(L10n.actionUpdate.localized(), systemImage: "arrow.triangle.2.circlepath") {
                Task { await update(host) }
            })
            // #303: container is installed but no ConnectionRecord links to it —
            // surface the recovery action so the user can get a usable connection
            // without re-installing or losing the room/key.
            if host.lastConnectionID == nil {
                items.append(.action(L10n.actionRecoverConnection.localized(), systemImage: "arrow.counterclockwise.circle") {
                    recoverConfirmHost = host
                })
            }
            items.append(.divider)
            items.append(.action(L10n.actionUninstall.localized(), systemImage: "trash", role: .destructive) {
                uninstallConfirmHost = host
            })
        } else {
            items.append(.action(L10n.actionInstall.localized(), systemImage: "arrow.down.app") {
                installFor = host
            })
            items.append(.action(L10n.actionScanVPS.localized(), systemImage: "magnifyingglass") {
                Task { await scanContainers(host) }
            })
        }

        // #419: bot settings — available whether or not a container is installed.
        items.append(.divider)
        // #427: robot glyph (custom asset). was: systemImage "bubble.left.and.bubble.right"
        items.append(.action(L10n.botSheetTitle.localized(), assetImage: "RobotIcon") {
            botConfigFor = host
        })

        // Deep uninstall whenever there's something to wipe (Podman present).
        if currentBase(host) != .noPodman {
            items.append(.action(L10n.actionDeepUninstall.localized(), systemImage: "flame", role: .destructive) {
                deepUninstallConfirmHost = host
            })
        }

        // #304: share the connection this host owns (URI / QR), moved here from the
        // Connections tab — the connection is configured on this card.
        if let conn = linkedConnection(host) {
            items.append(.divider)
            items.append(.action(L10n.shareConnectionTitle.localized(), systemImage: "square.and.arrow.up") {
                shareConn = conn
            })
            // #135: full-access (co-admin) share — carries the SSH credentials so
            // the recipient can MANAGE the VPS. Destructive; warned in the sheet.
            // #451: DISABLED for key-auth hosts — the link would have to embed
            // the private key. The item stays visible but explains why instead
            // of sharing (an OlcMenuItem can't render a footer, so the tap IS
            // the explanation); the URI-only share above remains available.
            if host.authMethod == .privateKey {
                items.append(.action(L10n.shareFullAccessTitle.localized(), systemImage: "key.horizontal") {
                    alertText = L10n.shareFullAccessKeyHostUnavailable.localized()
                })
            } else {
                items.append(.action(L10n.shareFullAccessTitle.localized(), systemImage: "key.horizontal", role: .destructive) {
                    if let req = fullAccessRequest(host, conn: conn) { shareFullAccess = req }
                })
            }
        }

        items.append(.divider)
        items.append(.action(L10n.actionReboot.localized(), systemImage: "arrow.clockwise", role: .destructive) {
            rebootConfirmHost = host
        })
        items.append(.divider)
        items.append(.action(L10n.edit.localized(), systemImage: "pencil") { editHost = host })
        items.append(.action(L10n.actionRemoveFromList.localized(), systemImage: "minus.circle", role: .destructive) {
            removeHost = host
        })
        return items
    }

    // MARK: Actions (each drives the card through `run`; the probe sets base)

    /// #451 was: password(for:) → String?. The card's actions now resolve the
    /// full SSHSecret (password or private key + passphrase) from the store.
    private func secret(for host: ServerHost) -> SSHSecret? {
        serverStore.secret(for: host)
    }

    /// #451: method-appropriate "credential missing" message for the guards.
    private func missingCredentialMessage(_ host: ServerHost) -> String {
        host.authMethod == .privateKey
            ? L10n.alertKeyMissingShort.localized()
            : L10n.alertPasswordMissingShort.localized()
    }

    /// SSH status probe + TCP ping. The probe is the authoritative base setter.
    private func checkServer(_ host: ServerHost) async {
        Task { await doPing(host) }  // parallel TCP ping; updates the Ping metric
        await run(.check, on: host) { secret in
            let (rstate, stats) = try await provisioner.checkReadiness(
                on: host, secret: secret, containerName: host.lastContainerName)
            if let stats { vpsStats[host.id] = stats }
            var base = HostBase(rstate)
            // #302: a check on a host with no *known* container reports "image
            // cached, ready for reinstall" even when an olcrtc container already
            // exists (just stopped) — the user only saw it after manually tapping
            // "Look for olcrtc containers". Fold that scan into the check so an
            // existing container is auto-detected + adopted without the extra step.
            if host.lastContainerName == nil, !base.hasContainer,
               let found = try? await provisioner.scanContainers(on: host, secret: secret).first {
                var updated = host
                updated.lastContainerName = found.name
                serverStore.update(updated, password: nil)
                LogStore.shared.log(.provisioning, L10n.autoDetectedContainer_fmt.formatted(found.name))
                if case .running = found.status { base = .running } else { base = .stopped }
            }
            return base
        }
        await refreshCarriers(host.id)   // #452
    }

    // #452 was: install(_ host:options:) — single protocol. Now installs the
    // primary via srv.sh, then each additional protocol via add-carrier.sh
    // (sibling containers off the same deploy dir, shared key), creating one
    // ConnectionRecord per protocol.
    private func install(_ host: ServerHost, primary: InstallOptions, extras: [InstallOptions]) async {
        await run(.install, on: host) { secret in
            let result = try await provisioner.install(on: host, secret: secret, options: primary)
            let cfg = try OlcrtcURI.parse(result.uri)
            // #355 (audit A1): carry the vp8 + sei tuning the install URI may
            // encode (server-script format) instead of dropping them to
            // defaults; nil payload fields fall back to OlcrtcConnection's own
            // defaults, same as the recover path.
            // #401: via the shared Parsed → connection mapping.
            var params = OlcrtcConnection(from: cfg)
            // #436: the wbstream token isn't in the URI (upstream keeps it out), so
            // carry it from the install options onto the connection — the client
            // must send the same auth.token it just wrote into the server config.
            params.wbToken = primary.wbToken
            // #452: with extras every record (primary included) is suffixed by
            // its carrier, so the per-protocol connections stay tellable-apart.
            let record = ConnectionRecord(
                name: Self.recordName(host: host, carrier: primary.carrier, multi: !extras.isEmpty),
                details: .olcrtc(params))
            connections.add(record)
            var updated = host
            updated.lastContainerName = result.containerName
            updated.lastConnectionID  = record.id
            // boc #452: additional protocols — one add-carrier.sh run each. A
            // per-protocol failure skips just that protocol (collected into one
            // alert) instead of failing the whole install.
            var extraIDs: [UUID] = []
            var failedCarriers: [String] = []
            for extra in extras {
                do {
                    let extraResult = try await provisioner.addCarrier(
                        on: host, secret: secret,
                        baseContainer: result.containerName, options: extra)
                    let extraCfg = try OlcrtcURI.parse(extraResult.uri)
                    var extraParams = OlcrtcConnection(from: extraCfg)
                    extraParams.wbToken = extra.wbToken
                    let extraRecord = ConnectionRecord(
                        name: Self.recordName(host: host, carrier: extra.carrier, multi: true),
                        details: .olcrtc(extraParams))
                    connections.add(extraRecord)
                    extraIDs.append(extraRecord.id)
                    LogStore.shared.log(.provisioning,
                        "＋ protocol \(extra.carrier)/\(extra.transport) added → \(extraResult.containerName)")
                } catch {
                    failedCarriers.append(CarrierTransportMatrix.carrierLabel(extra.carrier))
                    LogStore.shared.log(.provisioning,
                        "✗ extra protocol \(extra.carrier) failed: \(error.localizedDescription)")
                }
            }
            updated.extraConnectionIDs = extraIDs.isEmpty ? nil : extraIDs
            serverStore.update(updated, password: nil)
            if !failedCarriers.isEmpty {
                alertText = L10n.installExtrasPartialFail_fmt.formatted(
                    failedCarriers.joined(separator: ", "))
            }
            // eoc #452
            // #258 was: readiness[id] = .containerRunning("just installed") (optimistic).
            // Confirm the real post-install state with a probe instead.
            let (rstate, stats) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: result.containerName)
            if let stats { vpsStats[host.id] = stats }
            return HostBase(rstate)
        }
        await refreshCarriers(host.id)   // #452
    }

    private func uninstall(_ host: ServerHost) async {
        await run(.uninstall, on: host) { secret in
            try await provisioner.uninstall(on: host, secret: secret,
                                            containerName: host.lastContainerName)
            // #452 was: inline lastConnectionID-only cleanup — the shared helper
            // also removes the extra-protocol records + the cached rows.
            serverStore.update(clearInstalledState(host), password: nil)
            return .imageReady   // container gone, image still cached (deterministic)
        }
    }

    private func update(_ host: ServerHost) async {
        await run(.update, on: host) { secret in
            // #451: the update script resolves a container even when none is
            // recorded (first olcrtc-server-* sweep) and reports it via
            // OLCRTC_UPDATE_CONTAINER — adopt it like checkServer's #302
            // auto-detect does. Previously the resolved name was discarded, so
            // the post-update probe was silently skipped for such hosts.
            let resolved = try await provisioner.update(on: host, secret: secret,
                                                        containerName: host.lastContainerName)
            var cname = host.lastContainerName
            if let resolved, !resolved.isEmpty, resolved != cname {
                var updated = host
                updated.lastContainerName = resolved
                serverStore.update(updated, password: nil)
                LogStore.shared.log(.provisioning, L10n.autoDetectedContainer_fmt.formatted(resolved))
                cname = resolved
            }
            guard let cname else { return nil }
            let (rstate, stats) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: cname)
            if let stats { vpsStats[host.id] = stats }
            return HostBase(rstate)
        }
        await refreshCarriers(host.id)   // #452
    }

    private func startContainer(_ host: ServerHost) async {
        await run(.start, on: host) { secret in
            guard let cname = host.lastContainerName else {
                throw ProvisionError.parseFailed(L10n.containerNotInstalled.localized())
            }
            // #258 was: readiness[id] = .containerRunning("starting…") before the probe.
            try await provisioner.start(on: host, secret: secret, containerName: cname)
            let (rstate, stats) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: cname)
            if let stats { vpsStats[host.id] = stats }
            return HostBase(rstate)
        }
        await refreshCarriers(host.id)   // #452
    }

    private func stop(_ host: ServerHost) async {
        await run(.stop, on: host) { secret in
            guard let cname = host.lastContainerName else {
                throw ProvisionError.parseFailed(L10n.containerNotInstalled.localized())
            }
            // #258 was: readiness[id] = .containerStopped("stopping…") before the probe.
            try await provisioner.stop(on: host, secret: secret, containerName: cname)
            let (rstate, stats) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: cname)
            if let stats { vpsStats[host.id] = stats }
            return HostBase(rstate)
        }
        await refreshCarriers(host.id)   // #452
    }

    private func deepUninstall(_ host: ServerHost, removeImage: Bool) async {
        await run(.deepUninstall, on: host) { secret in
            try await provisioner.deepUninstall(on: host, secret: secret,
                                                containerName: host.lastContainerName,
                                                removeImage: removeImage)
            // #452 was: inline lastConnectionID-only cleanup — the shared helper
            // also removes the extra-protocol records + the cached rows.
            serverStore.update(clearInstalledState(host), password: nil)
            let (rstate, _) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: nil)
            return HostBase(rstate)
        }
    }

    private func reboot(_ host: ServerHost) async {
        await run(.reboot, on: host) { secret in
            try await provisioner.reboot(on: host, secret: secret)
            return nil   // host going down; keep the previous base, user re-checks
        }
    }

    // #452 was: reconfigure(_ host:options:) targeting host.lastContainerName +
    // host.lastConnectionID. Now targets an explicit protocol container and its
    // resolved record, so each row on a multi-protocol host reconfigures ITS
    // own container.
    private func reconfigure(_ host: ServerHost, containerName: String,
                             recordID: UUID?, options: InstallOptions) async {
        await run(.reconfigure, on: host) { secret in
            let newURI = try await provisioner.reconfigure(on: host, secret: secret,
                                                           containerName: containerName, options: options)
            // Update the linked ConnectionRecord with the new room/transport.
            // #452 was: connID = host.lastConnectionID — now the record the
            // reconfigured row resolved to.
            if let uri = newURI,
               let connID = recordID,
               let existing = connections.connections.first(where: { $0.id == connID }),
               case .olcrtc(let oldParams) = existing.details,
               let cfg = try? OlcrtcURI.parse(uri) {
                // #355 (audit A1): carry the sei tuning through the rebuild —
                // these were dropped, resetting SEI to defaults on every
                // reconfigure. Mirror how vp8FPS/vp8BatchSize are preserved.
                // #451: wbToken tracks what reconfigure just wrote server-side
                // — the new token for wbstream, cleared for other carriers
                // (reconfigureScript deletes the auth.token line) — so client
                // and server auth stay in lock-step.
                let updated = OlcrtcConnection(
                    carrier:      cfg.carrier,
                    transport:    cfg.transport,
                    roomID:       cfg.roomID,
                    key:          cfg.key.isEmpty ? oldParams.key : cfg.key,
                    clientID:     cfg.clientID,
                    vp8FPS:       oldParams.vp8FPS,
                    vp8BatchSize: oldParams.vp8BatchSize,
                    socksUser:    oldParams.socksUser,
                    socksPass:    oldParams.socksPass,
                    wbToken:      cfg.carrier == "wbstream" ? options.wbToken : "",
                    seiFPS:       oldParams.seiFPS,
                    seiBatch:     oldParams.seiBatch,
                    seiFrag:      oldParams.seiFrag,
                    seiACK:       oldParams.seiACK
                )
                var updatedRecord = existing
                updatedRecord.details = .olcrtc(updated)
                connections.update(updatedRecord)
            }
            // #452: probe the PRIMARY container — the host base describes it,
            // and a sibling-row reconfigure must not flip the card's base to
            // the sibling's state.
            let (rstate, stats) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: host.lastContainerName ?? containerName)
            if let stats { vpsStats[host.id] = stats }
            return HostBase(rstate)
        }
        await refreshCarriers(host.id)   // #452
    }

    // MARK: #452 — Protocols on the host card (multi-carrier)
    //
    // One VPS can now run several olcrtc protocols side by side (sibling
    // containers off one deploy dir / one key — scripts/add-carrier.sh). The
    // card lists them as rows: status dot + carrier/transport + a row menu
    // (Connect / Start / Stop / Reconfigure / Recover / Remove). Rows come from
    // provisioner.listCarriers (SSHRunner.CarrierInfo) and refresh after every
    // op. Add/remove/sibling start/stop run OUTSIDE `run` — the host's base
    // state describes the PRIMARY container and doesn't change — following the
    // rotateKey/recoverConnection pattern, serialized by `carrierBusyHostID`.

    private func missingCarriers(_ host: ServerHost) -> [String] {
        guard let rows = carrierRows[host.id] else { return [] }
        let present = Set(rows.map(\.provider))
        return CarrierTransportMatrix.carriers.filter { !present.contains($0) }
    }

    /// Row → the ConnectionRecord to connect with: the host-linked records
    /// first (primary + extras), then any record matching carrier + room.
    private func connectionRecord(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> ConnectionRecord? {
        func matches(_ rec: ConnectionRecord) -> Bool {
            if case .olcrtc(let p) = rec.details {
                return p.carrier == row.provider && p.roomID == row.room
            }
            return false
        }
        let linkedIDs = [host.lastConnectionID].compactMap { $0 } + (host.extraConnectionIDs ?? [])
        for id in linkedIDs {
            if let rec = connections.connections.first(where: { $0.id == id }), matches(rec) {
                return rec
            }
        }
        return connections.connections.first(where: matches)
    }

    /// Whether the LIVE tunnel runs through this row's protocol (carrier+room).
    private func isLiveRow(_ row: SSHRunner.CarrierInfo) -> Bool {
        guard let rec = tunnel.connectedRecord, case .olcrtc(let p) = rec.details else { return false }
        return p.carrier == row.provider && p.roomID == row.room
    }

    private func connectVia(_ host: ServerHost, row: SSHRunner.CarrierInfo) {
        guard let record = connectionRecord(host, row: row) else {
            alertText = L10n.protocolRecordMissing.localized()
            return
        }
        LogStore.shared.log(.provisioning,
            "▶ Connect via \(row.provider)/\(row.transport) (host card)")
        // A live session through another record is handled by connect() itself
        // (it disconnects, then dials the new record).
        tunnel.connect(record: record)
    }

    @ViewBuilder
    private func protocolsSection(_ host: ServerHost, state: HostDisplay) -> some View {
        let rows = carrierRows[host.id] ?? []
        if hasContainer(host) || !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.protocolsSectionHeader.localized().uppercased())
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if carrierBusyHostID == host.id {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                    if !missingCarriers(host).isEmpty {
                        Button {
                            addProtocolFor = host
                        } label: {
                            Label(L10n.addProtocolAction.localized(), systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .disabled(actionsDisabled || carrierBusyHostID != nil)
                    }
                }
                ForEach(rows) { row in
                    carrierRowView(host, row: row)
                }
            }
            .opacity(state.isRunning ? 0.45 : 1)
        }
    }

    private func carrierRowView(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> some View {
        // #455: each protocol reads as a distinct chip-row. The LIVE one (the
        // tunnel currently runs through it) carries a restrained aurora wash +
        // cyan hairline and a slightly heavier label; the rest stay calm on a
        // faint neutral fill. Aurora is spent only here on "live" and on the
        // primary CTA — everything else on the card is quiet.
        let live = isLiveRow(row)
        return HStack(spacing: 10) {
            Circle()
                .fill(carrierStatusColor(row))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(CarrierTransportMatrix.carrierLabel(row.provider))
                        .font(.subheadline.weight(live ? .semibold : .regular))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if row.isPrimary {
                        Text(L10n.protocolPrimaryBadge.localized())
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Text(CarrierTransportMatrix.transportLabel(row.transport))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if live {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.signalCyan)   // #455: aurora, not plain green
                    .accessibilityLabel(L10n.protocolConnectedBadge.localized())
            }
            OlcOverflowMenu(items: carrierMenuItems(host, row: row))
                .disabled(actionsDisabled || carrierBusyHostID != nil)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(live ? AnyShapeStyle(Theme.Palette.auroraSoft)
                         : AnyShapeStyle(Theme.Palette.fill.opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if live {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.Palette.signalCyan.opacity(0.35), lineWidth: 1)
            }
        }
    }

    /// Same status→colour rule the container scan sheet uses (shortLabel-based,
    /// so it needs no knowledge of ContainerStatus's case payloads).
    private func carrierStatusColor(_ row: SSHRunner.CarrierInfo) -> Color {
        if row.status == .notFound { return Theme.Palette.textTertiary }
        return row.status.shortLabel.hasPrefix("Up") ? Theme.Palette.green : Theme.Palette.orange
    }

    private func carrierMenuItems(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> [OlcMenuItem] {
        var items: [OlcMenuItem] = [
            .action(L10n.protocolConnectAction.localized(), systemImage: "personalhotspot") {
                connectVia(host, row: row)
            }
        ]
        if row.status.shortLabel.hasPrefix("Up") {
            items.append(.action(L10n.actionStop.localized(), systemImage: "stop.fill", role: .destructive) {
                if row.isPrimary { Task { await stop(host) } }
                else             { Task { await stopCarrier(host, row: row) } }
            })
        } else {
            items.append(.action(L10n.actionStart.localized(), systemImage: "play.fill") {
                if row.isPrimary { Task { await startContainer(host) } }
                else             { Task { await startCarrier(host, row: row) } }
            })
        }
        items.append(.action(L10n.actionChangeRoomTransport.localized(), systemImage: "slider.horizontal.3") {
            reconfigureRequest = ReconfigureRequest(
                host: host, containerName: row.container,
                recordID: connectionRecord(host, row: row)?.id,
                initialCarrier: row.provider, initialTransport: row.transport,
                initialRoom: row.room)
        })
        if connectionRecord(host, row: row) == nil {
            items.append(.action(L10n.actionRecoverConnection.localized(), systemImage: "arrow.counterclockwise.circle") {
                recoverRowRequest = CarrierRecoverRequest(
                    host: host, container: row.container, file: row.file, isPrimary: row.isPrimary)
            })
        }
        if !row.isPrimary {
            items.append(.divider)
            items.append(.action(L10n.removeProtocolAction.localized(), systemImage: "trash", role: .destructive) {
                removeCarrierConfirm = CarrierRemoveRequest(host: host, row: row)
            })
        }
        return items
    }

    /// Passive rows refresh — logs failures, never alerts.
    private func refreshCarriers(_ hostID: UUID) async {
        guard let host = serverStore.hosts.first(where: { $0.id == hostID }),
              let cname = host.lastContainerName,
              let secret = secret(for: host) else { return }
        do {
            carrierRows[hostID] = try await provisioner.listCarriers(
                on: host, secret: secret, baseContainer: cname)
        } catch {
            LogStore.shared.log(.provisioning,
                "⚠ protocol list failed: \(error.localizedDescription)")
        }
    }

    private func addCarrier(_ host: ServerHost, options: InstallOptions) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        guard let cname = host.lastContainerName else {
            alertText = L10n.containerNotInstalled.localized(); return
        }
        carrierBusyHostID = host.id
        defer { carrierBusyHostID = nil }
        do {
            let result = try await provisioner.addCarrier(
                on: host, secret: secret, baseContainer: cname, options: options)
            let cfg = try OlcrtcURI.parse(result.uri)
            // #401: shared Parsed → connection mapping; #436: the wb token isn't
            // in the URI, carry it from the options (same as install).
            var params = OlcrtcConnection(from: cfg)
            params.wbToken = options.wbToken
            let record = ConnectionRecord(
                name: Self.recordName(host: host, carrier: options.carrier, multi: true),
                details: .olcrtc(params))
            connections.add(record)
            var updated = host
            updated.extraConnectionIDs = (updated.extraConnectionIDs ?? []) + [record.id]
            serverStore.update(updated, password: nil)
            LogStore.shared.log(.provisioning,
                "＋ protocol \(cfg.carrier)/\(cfg.transport) added → \(result.containerName)")
            alertText = L10n.protocolAdded_fmt.formatted(cfg.carrier, cfg.transport)
            await refreshCarriers(host.id)
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    private func removeCarrier(_ host: ServerHost, row: SSHRunner.CarrierInfo) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        guard let cname = host.lastContainerName else {
            alertText = L10n.containerNotInstalled.localized(); return
        }
        carrierBusyHostID = host.id
        defer { carrierBusyHostID = nil }
        do {
            try await provisioner.removeCarrier(
                on: host, secret: secret, baseContainer: cname, carrier: row.provider)
            if let record = connectionRecord(host, row: row) {
                connections.remove(id: record.id)
                var updated = host
                updated.extraConnectionIDs = (updated.extraConnectionIDs ?? []).filter { $0 != record.id }
                if updated.extraConnectionIDs?.isEmpty == true { updated.extraConnectionIDs = nil }
                serverStore.update(updated, password: nil)
            }
            LogStore.shared.log(.provisioning, "− protocol \(row.provider) removed")
            alertText = L10n.protocolRemoved_fmt.formatted(CarrierTransportMatrix.carrierLabel(row.provider))
            await refreshCarriers(host.id)
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    /// Start/Stop for a NON-primary protocol container — outside `run` (the
    /// host's base tracks the primary; a sibling flip doesn't change it).
    private func startCarrier(_ host: ServerHost, row: SSHRunner.CarrierInfo) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        carrierBusyHostID = host.id
        defer { carrierBusyHostID = nil }
        do {
            try await provisioner.start(on: host, secret: secret, containerName: row.container)
            await refreshCarriers(host.id)
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    private func stopCarrier(_ host: ServerHost, row: SSHRunner.CarrierInfo) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        carrierBusyHostID = host.id
        defer { carrierBusyHostID = nil }
        do {
            try await provisioner.stop(on: host, secret: secret, containerName: row.container)
            await refreshCarriers(host.id)
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    /// #452: shared uninstall cleanup — clears the container link and removes
    /// EVERY connection this host installed (primary + extra protocols) when
    /// the auto-remove setting is on. Returns the cleared host to persist.
    private func clearInstalledState(_ host: ServerHost) -> ServerHost {
        var updated = host
        updated.lastContainerName = nil
        let ids = [updated.lastConnectionID].compactMap { $0 } + (updated.extraConnectionIDs ?? [])
        if SettingsStore.shared.autoRemoveConnectionOnUninstall {
            for id in ids {
                if let conn = connections.connections.first(where: { $0.id == id }) {
                    connections.remove(id: id)
                    LogStore.shared.log(.provisioning, "Connection «\(conn.displayName)» also removed from list.")
                }
            }
        }
        updated.lastConnectionID   = nil
        updated.extraConnectionIDs = nil
        carrierRows[host.id] = nil
        return updated
    }

    /// #452: connection naming — a multi-protocol install suffixes every record
    /// with its carrier ("MyVPS · Telemost"); single-protocol keeps the label.
    static func recordName(host: ServerHost, carrier: String, multi: Bool) -> String {
        multi ? "\(host.label) · \(CarrierTransportMatrix.carrierLabel(carrier))" : host.label
    }

    /// Primary reconfigure entry (action bar / host menu / retry): targets the
    /// primary container, seeded from its row when the rows are loaded.
    private func primaryReconfigureRequest(_ host: ServerHost) -> ReconfigureRequest? {
        guard let cname = host.lastContainerName else { return nil }
        let row = carrierRows[host.id]?.first(where: { $0.isPrimary })
        return ReconfigureRequest(host: host, containerName: cname,
                                  recordID: host.lastConnectionID,
                                  initialCarrier: row?.provider,
                                  initialTransport: row?.transport,
                                  initialRoom: row?.room)
    }

    // MARK: Container scan (no base change → outside `run`)
    // #339 was: fetchLogs(_:) — ran provisioner.containerLogs and presented the
    // ContainerLogsPayload sheet; replaced by the Logs-tab route (the fetch now
    // runs inside LogsView with phase progress, #338).

    // #303: read the deployed server.yaml + ~/.olcrtc_key for `host`'s linked
    // container and add a ConnectionRecord from it — recovers a usable
    // connection when Connections is empty (new device / reinstall) but the
    // server is already running olcrtc. Read-only on the server.
    // #452: gained containerName/configFile/asExtra so a protocol row can
    // recover ITS config (server-<carrier>.yaml in the shared deploy dir); the
    // host-level entry keeps the old defaults (primary container, server.yaml,
    // links lastConnectionID).
    private func recoverConnection(_ host: ServerHost,
                                   containerName: String? = nil,
                                   configFile: String = "server.yaml",
                                   asExtra: Bool = false) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        guard let cname = containerName ?? host.lastContainerName else {
            alertText = L10n.containerNotInstalled.localized(); return
        }
        do {
            let cfg = try await provisioner.recoverConfig(on: host, secret: secret,
                                                          containerName: cname, configFile: configFile)
            // #303: default-struct values (30/10/1200/1) match OlcrtcConnection's
            // own seiFPS/seiBatch/seiFrag/seiACK defaults (App/Models/OlcrtcConnection.swift)
            // — used as a fallback only if the deployed server.yaml's sei: block
            // somehow lacked a field (shouldn't happen for srv.sh-written configs).
            // #401: NOT routed through OlcrtcConnection(from: Parsed) — `cfg` here is
            // an SSHRunner.RecoveredConfig (recovered server.yaml), not an
            // OlcrtcURI.Parsed, so it keeps its own explicit field mapping; clientID
            // is forced to "default" (a recovered server.yaml carries no client segment).
            let params = OlcrtcConnection(
                carrier:      cfg.carrier,
                transport:    cfg.transport,
                roomID:       cfg.roomID,
                key:          cfg.key,
                clientID:     "default",
                vp8FPS:       cfg.vp8FPS,
                vp8BatchSize: cfg.vp8BatchSize,
                seiFPS:       cfg.seiFPS   ?? 30,
                seiBatch:     cfg.seiBatch ?? 10,
                seiFrag:      cfg.seiFrag  ?? 1200,
                seiACK:       cfg.seiACK   ?? 1
            )
            // #452: an extra-protocol recover names + links the record like an
            // extra install would (carrier-suffixed name, extraConnectionIDs).
            let record = ConnectionRecord(
                name: Self.recordName(host: host, carrier: cfg.carrier, multi: asExtra),
                details: .olcrtc(params))
            connections.add(record)
            var updated = host
            if asExtra {
                updated.extraConnectionIDs = (updated.extraConnectionIDs ?? []) + [record.id]
            } else {
                updated.lastConnectionID = record.id
            }
            serverStore.update(updated, password: nil)
            alertText = L10n.recoverResultSuccess_fmt.formatted(cfg.carrier, cfg.transport)
        // boc #314: server.yaml unreadable/unparseable — the key/params can't
        // be extracted read-only, so offer the "generate new key" fallback
        // instead of a dead-end error alert. Other errors (SSH, network,
        // missing container) keep the plain alert below.
        } catch let error as SSHRunner.RecoverConfigError {
            LogStore.shared.log(.provisioning,
                "⚠ Recover unusable (\(error.localizedDescription)) — offering key rotation (#314)")
            rotateKeyConfirmHost = host
        // eoc #314
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    // #314: "generate new key" fallback for #303 — rotates ~/.olcrtc_key on the
    // VPS via scripts/rotate-key.sh (repairs server.yaml with srv.sh's exact
    // key/yaml semantics + restarts the container), then adds the resulting
    // connection exactly like a fresh install does (parse OLCRTC_URI=).
    private func rotateKey(_ host: ServerHost) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        guard let cname = host.lastContainerName else {
            alertText = L10n.containerNotInstalled.localized(); return
        }
        do {
            let result = try await provisioner.rotateKey(on: host, secret: secret, containerName: cname)
            let cfg = try OlcrtcURI.parse(result.uri)
            // vp8 tuning comes from the URI payload (salvaged server values may
            // differ from this app's global defaults). sei tuning can't round-trip
            // through OlcrtcURI.Parsed — defaults apply, same as the install path.
            // #401: shared Parsed → connection mapping (sei defaults 30/10/1200/1
            // == the struct's own defaults, so behavior is unchanged).
            let params = OlcrtcConnection(from: cfg)
            let record = ConnectionRecord(name: host.label, details: .olcrtc(params))
            connections.add(record)
            var updated = host
            updated.lastContainerName = result.containerName
            updated.lastConnectionID  = record.id
            serverStore.update(updated, password: nil)
            // boc #452: sibling protocol containers were restarted with the SAME
            // new key — refresh every matching record so a multi-protocol host
            // stays fully usable after a rotation.
            for sib in result.siblings {
                guard let sibCfg = try? OlcrtcURI.parse(sib.uri) else { continue }
                func matches(_ rec: ConnectionRecord) -> Bool {
                    if case .olcrtc(let p) = rec.details {
                        return p.carrier == sibCfg.carrier && p.roomID == sibCfg.roomID
                    }
                    return false
                }
                let linked = (updated.extraConnectionIDs ?? [])
                    .compactMap { id in connections.connections.first(where: { $0.id == id }) }
                    .first(where: matches)
                guard let match = linked ?? connections.connections.first(where: matches),
                      case .olcrtc(let old) = match.details else { continue }
                // Mirror the reconfigure merge (#355-style): only the key/room/
                // transport come from the URI; tuning + secrets are preserved.
                let refreshed = OlcrtcConnection(
                    carrier:      sibCfg.carrier,
                    transport:    sibCfg.transport,
                    roomID:       sibCfg.roomID,
                    key:          sibCfg.key.isEmpty ? old.key : sibCfg.key,
                    clientID:     sibCfg.clientID,
                    vp8FPS:       old.vp8FPS,
                    vp8BatchSize: old.vp8BatchSize,
                    socksUser:    old.socksUser,
                    socksPass:    old.socksPass,
                    wbToken:      old.wbToken,
                    seiFPS:       old.seiFPS,
                    seiBatch:     old.seiBatch,
                    seiFrag:      old.seiFrag,
                    seiACK:       old.seiACK
                )
                var updatedRecord = match
                updatedRecord.details = .olcrtc(refreshed)
                connections.update(updatedRecord)
            }
            // eoc #452
            alertText = L10n.rotateKeyResultAdded_fmt.formatted(cfg.carrier, cfg.transport)
            await refreshCarriers(host.id)   // #452
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    private func scanContainers(_ host: ServerHost) async {
        guard let secret = secret(for: host) else {
            alertText = missingCredentialMessage(host); return
        }
        do {
            let found = try await provisioner.scanContainers(on: host, secret: secret)
            foundContainers = found
            scanFor = host
        } catch {
            alertText = L10n.stateErrorPrefix_fmt.formatted(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func containerScanSheet(host: ServerHost) -> some View {
        NavigationStack {
            Group {
                if foundContainers.isEmpty {
                    Text(L10n.scanNoContainers.localized())
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(foundContainers) { container in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(container.name)
                                    .font(.system(.body, design: .monospaced))
                                HStack(spacing: 8) {
                                    Circle()
                                        // #350 was: Color.green / Color.orange — route through Theme.Palette.
                                        .fill(container.status == .notFound ? Color.secondary :
                                              container.status.shortLabel.hasPrefix("Up") ? Theme.Palette.green : Theme.Palette.orange)
                                        .frame(width: 8, height: 8)
                                    Text(container.status.shortLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !container.carrier.isEmpty {
                                        Text("· \(container.carrier)/\(container.transport)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                if !container.roomID.isEmpty {
                                    Text(L10n.roomPrefix_fmt.formatted(container.roomID))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button(L10n.scanRestoreAction.localized()) {
                                restoreContainer(container, on: host)
                            }
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle(L10n.actionScanVPS.localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone.localized()) { scanFor = nil }
                }
            }
        }
        .onDisappear { foundContainers = [] }
        .presentationDetents([.medium, .large])
    }

    private func restoreContainer(_ container: SSHRunner.FoundContainer, on host: ServerHost) {
        scanFor = nil
        var updated = host
        updated.lastContainerName = container.name
        serverStore.update(updated, password: nil)
        display[host.id] = .base(.stopped)   // container present; Check confirms run-state
        alertText = L10n.scanRestored_fmt.formatted(container.name)   // #346 was: "Restored: \(container.name)"
        Task { await refreshCarriers(host.id) }   // #452
    }
}

// #135: identifiable wrapper so the full-access share can drive a `.sheet(item:)`
// the same way `shareConn` does. Carries the connection (for the URI-only top of
// the sheet) plus the SSH payload that unlocks the destructive opt-in section.
struct FullAccessShareRequest: Identifiable {
    let id = UUID()
    let conn: ConnectionRecord
    let payload: FullAccessShare
}

// boc #452: multi-carrier request payloads — value snapshots (the #330 rule)
// driving one `.sheet(item:)` / `.confirmationDialog(presenting:)` each.

/// Reconfigure targeted at ONE protocol's container, with the row's current
/// values as sheet seeds and the record to update on success.
struct ReconfigureRequest: Identifiable {
    let host: ServerHost
    let containerName: String
    let recordID: UUID?
    let initialCarrier: String?
    let initialTransport: String?
    let initialRoom: String?
    var id: String { containerName }
}

struct CarrierRemoveRequest: Identifiable {
    let host: ServerHost
    let row: SSHRunner.CarrierInfo
    var id: String { row.container }
}

struct CarrierRecoverRequest: Identifiable {
    let host: ServerHost
    let container: String
    let file: String
    let isPrimary: Bool
    var id: String { container }
}
// eoc #452

// #340: both appearance variants.
#if DEBUG
#Preview("Manage VPS — Dark") {
    ServersView(serverStore: ServerHostStore(), connections: ConnectionStore(),
                logsRouter: LogsRouter(), botStore: BotStore(), tunnel: TunnelManager())
        .preferredColorScheme(.dark)
}
#Preview("Manage VPS — Light") {
    ServersView(serverStore: ServerHostStore(), connections: ConnectionStore(),
                logsRouter: LogsRouter(), botStore: BotStore(), tunnel: TunnelManager())
        .preferredColorScheme(.light)
}
#endif
