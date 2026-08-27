import SwiftUI

// MARK: - ServersView
//
// #457: the SECOND of three tabs (Connect · Servers · Settings). Manages SSH
// credentials for the servers where we can install / uninstall olcrtc, plus
// triggers those operations from the device.
// #457 was: "Third tab" — it was the third of five before Config and Logs
// stopped being tabs.
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
    // boc #457: `@ObservedObject var logsRouter: LogsRouter` is gone with the
    // Logs TAB. Container logs become a pushed, subject-scoped destination
    // (`LogsView(subject: .container(host))`) owned by the navigation layer —
    // a push carries its context for free, so the cross-tab back-channel
    // (`LogsRouter.request` + `MainTabView.onChange { selectedTab = 3 }` +
    // `fetchingHostID` + this file's `containerLogBusyStrip`) has nothing left
    // to do. Nothing here invents a route in its place.
    // #457 was: @ObservedObject var logsRouter: LogsRouter
    // eoc #457
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
    // boc #456: when each host was last SSH-probed for readiness. Stamped on
    // BOTH the success and the failure path, so a dead host isn't hammered.
    @State private var lastProbe      : [UUID: Date] = [:]
    // #456 (audit): when a readiness probe last actually RETURNED a container
    // reading. Split from `lastProbe` (the attempt clock) because a FAILED probe
    // stamped `lastProbe` too — which told the card "checked just now" over the
    // previous, possibly hours-old, base, and suppressed the honest
    // "not checked yet" headline. This is the clock the card displays
    // (requirement 3: an age the user sees must be the age of the reading).
    @State private var lastProbeOK    : [UUID: Date] = [:]
    /// #456: re-entrancy guard for the on-entry refresh pass (requirement 4).
    @State private var entryRefreshing = false
    /// #456: an install about to run on a host that already carries olcrtc
    /// containers — scripts/srv.sh force-removes EVERY `olcrtc-server-*` before
    /// installing, so the user gets a choice instead of a silent wipe.
    @State private var installChoice  : InstallChoiceRequest?
    // eoc #456
    @State private var scanFor        : ServerHost?
    /// #457 (audit fix): the server whose container log is being pushed. The
    /// "Container logs" menu item was deleted with the Logs TAB, but its
    /// replacement push was never wired, so container logs became unreachable —
    /// a regression, not a simplification. Menu items are closures here, not
    /// links, so the push is driven by this optional.
    @State private var logsForHost    : ServerHost?
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
    /// #456: the ONE owner of measured evidence. Every green on this tab now
    /// traces back to a recent end-to-end probe recorded here — podman "Up"
    /// proves a process exists, nothing more (the user's telemost container was
    /// Up while its own logs read "session closed reason=liveness", in=0 out=0).
    /// Observed exactly like `settings`, so a probe result redraws the rows.
    @ObservedObject private var health = HealthCoordinator.shared

    private var coreStack: some View {
        NavigationStack {
            List {
                // #456 was: matrixSection — a build-time lab table shown as if it
                // described today. Deleted: the card carries measured evidence now.

                if serverStore.hosts.isEmpty {
                    emptyState
                } else {
                    ForEach(serverStore.hosts) { host in
                        hostCard(host)
                    }
                    .onDelete { serverStore.remove(at: $0) }
                }
            }
            // #457: the title stays a large title here (unlike Connect, whose
            // large title spent 34pt on the brand word "OlcRTC" above a 15pt
            // truth) — it names the content, not the brand.
            // #457 was: the app called one place three names — "Manage VPS"
            // (tab), "VPS list" (this title) and "the Servers tab" (the copy
            // that points here). Both table entries now read "Servers"/«Серверы»,
            // so the tab, the title and every reference agree.
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
            // boc #456: requirement 4 — entering Manage VPS re-checks by itself,
            // so the user never has to press a button to learn the truth. A
            // TabView child reliably gets `onAppear` per tab entry (LogsView's
            // #332 visibility gate relies on exactly that), so no selectedTab
            // plumbing from MainTabView is needed.
            .onAppear { Task { await refreshOnEntry() } }
            // Leaving the tab stops further probes; an in-flight native call
            // can't be interrupted, its result is simply discarded.
            .onDisappear { health.cancelAll() }
            // eoc #456
            // #258: route the provisioner's progress stream into the running host's
            // phase/subtitle ONLY — never the base state or the dot colour.
            .onChange(of: provisioner.status) { _, status in
                guard case .running(let msg) = status else { return }
                advancePhase(note: msg)
            }
        }
    }

    // #457 (audit fix): ServersView.coreStack carried 21 chained modifiers in a
    // single expression and CI failed with "unable to type-check this expression
    // in reasonable time" — the third time this file has hit that budget. The
    // chain is split by KIND: the List and its lifecycle stay in coreStack, the
    // presentation modifiers live in these wrappers. Same view, same order.
    @ViewBuilder
    private func hostSheets(_ content: some View) -> some View {
        content
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
            // #457 (audit fix): the destination behind the "Container logs" menu
            // item. A push, not a tab hop — the log opens already scoped to this
            // server, so nothing has to re-derive which host it was about.
            .navigationDestination(item: $logsForHost) { host in
                LogsView(subject: .container(host),
                         serverStore: serverStore,
                         connections: connections)
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
                // #456: also seeded with the wbstream token and the jitsi
                // instance the record already carries — a blank field here used
                // to DELETE the server's auth.token on confirm.
                ReconfigureOptionsView(initialCarrier: req.initialCarrier,
                                       initialTransport: req.initialTransport,
                                       initialRoom: req.initialRoom,
                                       initialWbToken: req.initialWbToken,
                                       initialJitsiBase: req.initialJitsiBase) { options in
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
    }

    @ViewBuilder
    private func hostConfirmations(_ content: some View) -> some View {
        content
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

    var body: some View {
        // #452: the multi-carrier modals (add-protocol sheet, remove/recover
        // confirms) are split off the main chain — with them inline the Swift
        // type-checker timed out on ServersView.body ("unable to type-check
        // this expression in reasonable time").
        // #457: three wrappers instead of one 21-modifier expression.
        carrierModals(hostConfirmations(hostSheets(coreStack)))
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
            // boc #456: requirement 8 — installing over an existing deployment
            // offers "use the existing one" instead of destroying it (and then
            // re-asking for the room ID the server already knows). Lives here,
            // with the other carrier modals, so `coreStack`'s modifier chain
            // stays inside the type-checker's budget.
            .confirmationDialog(
                installChoice.map {
                    L10n.installExistingFoundTitle_fmt.formatted($0.found.first?.name ?? "")
                } ?? "",
                isPresented: Binding(
                    get: { installChoice != nil },
                    set: { if !$0 { installChoice = nil } }
                ),
                titleVisibility: .visible,
                presenting: installChoice
            ) { req in
                Button(L10n.installUseExistingAction.localized()) {
                    installChoice = nil
                    adoptExisting(req)
                }
                Button(L10n.installReinstallAction.localized(), role: .destructive) {
                    installChoice = nil
                    installFor = req.host
                }
                Button(L10n.cancel.localized(), role: .cancel) { installChoice = nil }
            } message: { _ in
                Text(L10n.installExistingFoundBody.localized())
            }
            // eoc #456
    }

    private func removeFromList(_ host: ServerHost) {
        if let idx = serverStore.hosts.firstIndex(where: { $0.id == host.id }) {
            serverStore.remove(at: IndexSet([idx]))
        }
    }

    // #456 was: `matrixSection` — a Section wrapping MatrixView under the
    // "Carrier × Transport" header. Deleted with its call site above: the table
    // is a hand-synced snapshot of an upstream lab run at pin time, rendered as
    // if it described today's carriers. CarrierTransportMatrix itself stays —
    // the pickers still use it to gate impossible combos.

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

    // MARK: #456 — verified health (the ONE vocabulary for "is this OK?")
    //
    // podman "Up" only proves a process exists. It proved nothing about the
    // telemost node that shipped this task: Up-and-green while its own container
    // logs read "control unhealthy" → "session closed reason=liveness" and
    // "traffic: addr=www.google.com:443 in=0 out=0". Green here comes from
    // HealthCoordinator alone — a recent end-to-end probe through that node's own
    // SOCKS listener. Everything weaker renders neutral, never good.

    /// #456: every ConnectionRecord this host's protocol rows resolve to.
    private func hostRecords(_ host: ServerHost) -> [ConnectionRecord] {
        (carrierRows[host.id] ?? []).compactMap { connectionRecord(host, row: $0) }
    }

    /// #456: this host's protocols aggregated into one verdict (best evidence
    /// wins, but "couldn't check" never masquerades as "broken").
    private func hostHealth(_ host: ServerHost) -> HealthDisplay {
        health.summary(for: hostRecords(host).map(\.id))
    }

    /// #456: one protocol row's verdict. No record → nothing has ever been
    /// measured for it, which must LOOK like nothing, not like good.
    private func rowHealth(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> HealthDisplay {
        guard let rec = connectionRecord(host, row: row) else { return .never }
        return health.display(for: rec.id)
    }

    /// #456: the card headline. `reachable` is the TCP-22 verdict — ABSENT means
    /// "never pinged", which is not the same as unreachable, and neither is the
    /// same as "stopped" (requirement 2).
    private func headline(_ host: ServerHost, state: HostDisplay) -> HostHeadline {
        let reachable: Bool? = {
            switch pingLatencies[host.id] {
            case .some(.some): return true
            case .some(.none): return false
            case .none:        return nil
            }
        }()
        // #456 (audit) was: `lastProbe` — the ATTEMPT clock, stamped even when the
        // probe threw, so a failed auto-check made an hours-old base read as a
        // present-tense reading and skipped the honest `.notChecked` headline.
        let age = lastProbeOK[host.id].map { Date().timeIntervalSince($0) }
        return HostHeadline.reduce(display: state, reachable: reachable,
                                   lastProbeAge: age, health: hostHealth(host))
    }

    /// #456: protocol rows on this host with no usable evidence — never probed,
    /// or too old to be worth anything. Drives the "Check all" footer.
    private func unverifiedCount(_ host: ServerHost) -> Int {
        hostRecords(host).reduce(into: 0) { acc, rec in
            switch health.display(for: rec.id) {
            case .never, .stale: acc += 1
            default:             break
            }
        }
    }

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
    //
    // #457: the card itself now lives in App/Views/ServerCardView.swift and the
    // protocol row in App/Views/ProtocolRowView.swift. Everything below is glue —
    // it resolves state into plain values and hands them over. Nothing that
    // RENDERS may grow inside this file again: it has hit the Swift
    // type-checker's expression budget twice already (see `carrierModals`).
    //
    // #457 was: hostCard / hostCardTop / hostCardBottom / statusRegion /
    // processCaption / metricsStrip / pingMiniStat / actionBar / primaryButton /
    // protocolsSection / carrierRowView / carrierRowLead / healthSweepFooter /
    // containerLogBusyStrip — ~340 lines of view code in this file.

    private func hostCard(_ host: ServerHost) -> some View {
        Section {
            serverCard(host)
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

    /// #457: resolves one host into `ServerCardView`'s inputs. Arguments are
    /// listed in the struct's declaration order — Swift enforces that order for
    /// a memberwise init, and getting it wrong is a compile error.
    private func serverCard(_ host: ServerHost) -> ServerCardView {
        let state  = displayState(host)
        // #457 (requirement 2): the count the headline is allowed to be
        // optimistic about. `summary` reports the BEST evidence, so without this
        // a host with one working and one dead protocol reads as simply fine.
        let counts = health.failingCount(for: hostRecords(host).map(\.id))
        // A protocol-level op holds the SSH lane just like a HostOp does, so it
        // locks the host's actions too (they would collide on one connection).
        let locked = actionsDisabled || carrierBusyHostID != nil
        return ServerCardView(
            name:            host.label,
            addressLine:     addressLine(host),
            headline:        headline(host, state: state),
            progress:        statusBarFraction(state),
            processCaption:  processCaptionText(host, state: state),
            failingCount:    counts.failing,
            protocolCount:   counts.total,
            uncheckedCount:  unverifiedCount(host),
            metrics:         metrics(host),
            rows:            carrierRows[host.id] ?? [],
            rowsBusy:        carrierBusyHostID == host.id,
            canAddProtocol:  !missingCarriers(host).isEmpty,
            actionsDisabled: locked,
            primary:         primaryAction(state),
            menuItems:       menuItems(host),
            onPrimary:       { runPrimary(host, state: state) },
            onAddProtocol:   { addProtocolFor = host },
            onVerifyAll:     { health.verifyAll(hostRecords(host), using: tunnel) },
            row:             { rowView(host, row: $0) })
    }

    /// #337: mask the host for display when screenshot-safe mode is on (IP
    /// literals to bullets; hostnames pass through). Display-only — `host.host`
    /// stays real.
    private func addressLine(_ host: ServerHost) -> String {
        "\(host.username)@\(IPMask.display(host.host, masked: settings.maskIPs)):\(String(host.port))"
    }

    /// #457: one protocol row, resolved. The view is dumb; the resolution from a
    /// container to a saved connection stays here, where the stores are.
    private func rowView(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> ProtocolRowView {
        ProtocolRowView(
            title:             CarrierTransportMatrix.carrierLabel(row.provider),
            transport:         CarrierTransportMatrix.transportLabel(row.transport),
            isPrimary:         row.isPrimary,
            isLive:            isLiveRow(row),
            isRunningOnServer: Self.isUp(row.status),
            health:            rowHealth(host, row: row),
            menuDisabled:      actionsDisabled || carrierBusyHostID != nil,
            menuItems:         carrierMenuItems(host, row: row),
            onVerify:          { verifyRow(host, row: row) })
    }

    /// #457 was: `row.status.shortLabel.hasPrefix("Up")` repeated at three call
    /// sites — string-matching a label that is also user-visible text.
    /// `ContainerStatus.parse` already decided this; ask it instead.
    static func isUp(_ status: ContainerStatus) -> Bool {
        if case .running = status { return true }
        return false
    }

    /// #457: three container-lifecycle states, three DIFFERENT glyphs — running,
    /// present-but-stopped, and not-there-at-all were one dot in three hues.
    /// Neutral colour throughout: none of this is a health claim, and the label
    /// beside it already says "Up 3 hours" / "Exited (137) …" / "Not found".
    static func scanGlyph(_ status: ContainerStatus) -> String {
        switch status {
        case .running:  return "play.circle"
        case .stopped:  return "pause.circle"
        case .notFound: return "questionmark.circle"
        }
    }

    // MARK: The primary action
    //
    // #457: the card offers exactly ONE next step, and never one that no
    // evidence justifies.
    // #457 was: `primaryButton`'s `else` branch rendered a full-width **Install**
    // for every base without a container — INCLUDING `.unknown`, i.e. a server
    // nothing had ever read. `scripts/srv.sh` force-removes every
    // `olcrtc-server-*` container before installing, so one tap on a re-added
    // VPS destroyed a working deployment and every sibling protocol on it.
    // `.unknown` now offers **Check server**; Install appears only on a base a
    // real probe returned.

    private func primaryAction(_ state: HostDisplay) -> ServerPrimaryAction {
        switch state {
        case .running: return .busy
        case .failed:  return .retry
        case .base(let b):
            if b == .running  { return .stop }
            if b.hasContainer { return .start }
            if b == .unknown  { return .check }
            return .install
        }
    }

    private func runPrimary(_ host: ServerHost, state: HostDisplay) {
        switch state {
        case .running:
            break   // the button is a spinner; nothing to dispatch
        case .failed(let op, _, _, _):
            Task { await retry(op, on: host) }
        case .base(let b):
            if b == .running       { Task { await stop(host) } }
            else if b.hasContainer { Task { await startContainer(host) } }
            else if b == .unknown  { Task { await checkServer(host) } }
            else                   { Task { await beginInstall(host) } }
        }
    }

    // MARK: The process caption
    //
    // #456: podman's verdict as PLAIN TEXT with its own age — no coloured dot,
    // because "the process exists" is not a health claim.

    /// #457 was: `L10n.vpsProcessCaption_fmt.formatted(state.base.title, age)` —
    /// it interpolated `HostBase.title`, a string written to be a card HEADLINE,
    /// into "Server process: %@". Both `.imageReady` and `.noPodman` title
    /// "Ready to install", so the caption read "Server process: Ready to install"
    /// (nonsense for one of them, a false claim for the other), and `.unknown`
    /// read "Server process: Status unknown". The caption gets its own words.
    private func processCaptionText(_ host: ServerHost, state: HostDisplay) -> String {
        // #456 (audit): `lastProbeOK`, not `lastProbe` — the attempt clock is
        // stamped even when the probe threw, which dated the PREVIOUS reading to
        // "just now". With no reading at all the seeded base is a GUESS, so the
        // line says exactly that instead of dressing a guess up with an age.
        guard let probed = lastProbeOK[host.id] else { return L10n.vpsProcessUnread.localized() }
        return L10n.vpsProcessAge_fmt.formatted(
            Self.processWord(state.base), HealthAge.label(Date().timeIntervalSince(probed)))
    }

    /// #457: the caption's own small vocabulary — four plain facts about the
    /// server-side process, keyed off what a probe actually found.
    static func processWord(_ base: HostBase) -> String {
        switch base {
        case .running:              return L10n.vpsProcessRunning.localized()
        case .stopped:              return L10n.vpsProcessStopped.localized()
        case .imageReady, .noImage: return L10n.vpsProcessNothingInstalled.localized()
        case .noPodman:             return L10n.vpsProcessNotSetUp.localized()
        case .unknown:              return L10n.vpsProcessUnread.localized()
        }
    }

    /// The progress fraction while running; nil when the bar slot is empty.
    private func statusBarFraction(_ state: HostDisplay) -> Double? {
        guard case .running(let op, let phase, _, _) = state else { return nil }
        return Double(min(phase + 1, op.stepCount)) / Double(max(op.stepCount, 1))
    }

    // MARK: Metrics
    //
    // #457: the numbers describe the MACHINE, not whether anything on it works,
    // so the card draws them below the protocol rows. The formatting statics stay
    // on this type — `VPSStatFormattingTests` pins them by name.

    private func metrics(_ host: ServerHost) -> ServerCardMetrics {
        let stats = vpsStats[host.id]
        return ServerCardMetrics(
            ping:     pingValue(host),
            pingTone: pingTone(host),
            // #346: labels through L10n (ru = en for the abbreviations); units
            // like "G"/"M"/"d" inside the values stay English.
            disk:     Self.shortUsage(stats?.disk),
            // #451: shortRAM, not shortUsage — a 2 GB VPS reports "407M/1967M"
            // and the 9-char "407/1967M" overflowed the strip on 375pt phones.
            ram:      Self.shortRAM(stats?.ram),
            uptime:   Self.shortUptime(stats?.uptime))
    }

    private func pingValue(_ host: ServerHost) -> String {
        switch pingLatencies[host.id] {
        case .some(.some(let ms)): return String(format: "%.0fms", ms)
        case .some(.none):         return "✕"
        case .none:                return "—"
        }
    }

    /// #456 was: `ms < 100 ? green : ms < 300 ? orange : red` — an SSH round-trip
    /// says NOTHING about whether the tunnel passes traffic, and that green was
    /// one of the loudest false-green sources on this card. A reachable value is
    /// neutral; only the honest negative stays red.
    private func pingTone(_ host: ServerHost) -> Color {
        switch pingLatencies[host.id] {
        case .some(.some): return Theme.Palette.textPrimary
        case .some(.none): return Theme.Palette.red
        case .none:        return Theme.Palette.textTertiary
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
            // #457: container logs are now a PUSH scoped to this server, instead
            // of the old cross-tab teleport (set a router request → jump to tab 3
            // → the tab re-derives which host it was about). Same item, honest
            // destination: the log arrives already about THIS server.
            items.append(.action(L10n.actionContainerLogs.localized(),
                                 systemImage: "arrow.down.doc") {
                logsForHost = host
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
        } else if currentBase(host) != .unknown {
            // #457: `else if … != .unknown` — Install is offered only on a base a
            // real probe RETURNED, matching `primaryAction`. On a never-read
            // server the menu's first item ("Check server") is the whole offer.
            // #457 was: a bare `else`, so a server nothing had ever looked at
            // carried Install in the menu as well as on the button.
            items.append(.action(L10n.actionInstall.localized(), systemImage: "arrow.down.app") {
                // #456 was: installFor = host — scan first, then offer a choice.
                Task { await beginInstall(host) }
            })
        }
        // #456 was: the Scan item lived inside the `else` branch above, so it
        // vanished for good the moment a container was adopted — exactly when a
        // user wants to look for siblings created outside the app, or after the
        // recorded name went stale.
        items.append(.action(L10n.actionScanVPS.localized(), systemImage: "magnifyingglass") {
            Task { await scanContainers(host) }
        })

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

    // MARK: #456 — auto-refresh on tab entry (requirements 2, 3 and 4)
    //
    // The card used to show whatever the last manual Check left behind: an
    // hours-old "Running", or the pre-probe seed ("stopped") for a server that
    // was in fact up. Entering the tab now re-probes on its own, and a probe that
    // FAILS records "couldn't check" instead of inventing a stopped state.

    /// #456: how stale a host's SSH probe must be before entering the tab re-runs it.
    private static let entryProbeStaleSeconds: TimeInterval = 120

    private func refreshOnEntry() async {
        guard !entryRefreshing, !actionsDisabled else { return }
        entryRefreshing = true
        defer { entryRefreshing = false }
        let now = Date()
        let due = serverStore.hosts.filter {
            now.timeIntervalSince(lastProbe[$0.id] ?? .distantPast) >= Self.entryProbeStaleSeconds
        }
        for host in due {
            if Task.isCancelled { return }
            await silentProbe(host)
            await refreshCarriers(host.id)
        }
        // Returns immediately: the coordinator serialises the probes, caps the
        // pass and skips the room the live tunnel holds. Nodes it doesn't reach
        // stay honestly "not checked" (see ServerCardView's sweep note).
        health.verifyStale(serverStore.hosts.flatMap { hostRecords($0) }, using: tunnel)
    }

    /// #456: a readiness probe that NEVER lies. On success it sets the base, the
    /// stats and the display clock; on ANY failure it leaves ALL THREE alone, so
    /// the card keeps showing the last real reading WITH its true age and the
    /// TCP-22 verdict `doPing` just recorded — a network or SSH error must never
    /// be rendered as "stopped", nor as a fresh reading (requirements 2 and 3).
    /// Status-silent (`probeReadiness`, not `checkReadiness`), so it neither
    /// locks the card's buttons nor paints a progress bar.
    private func silentProbe(_ host: ServerHost) async {
        guard let secret = secret(for: host) else { return }
        await doPing(host)                       // refreshes pingLatencies + lastPing
        do {
            let (rstate, stats) = try await provisioner.probeReadiness(
                on: host, secret: secret, containerName: host.lastContainerName)
            if let stats { vpsStats[host.id] = stats }
            // Never clobber an op that started while we were awaiting the probe.
            if !(display[host.id]?.isRunning ?? false) {
                display[host.id] = .base(HostBase(rstate))
            }
            lastProbeOK[host.id] = Date()       // #456 (audit): a REAL container reading
        } catch {
            LogStore.shared.log(.provisioning, "⚠ auto-check failed: \(error.localizedDescription)")
            // boc #456 (audit)
            // #456 was: `pingLatencies[host.id] = nil` with the comment
            // «"couldn't check", NOT "stopped"». `pingLatencies` is
            // `[UUID: Double?]`, so assigning a bare `nil` REMOVES the key
            // (Swift's dictionary-of-optionals trap) — the opposite of the
            // intent. It (a) erased the honest TCP verdict `doPing` had just
            // recorded one line above, including the `.some(nil)` that is the
            // ONLY input producing `HostHeadline.unreachable`, so a VPS that was
            // genuinely unreachable stopped saying so, and (b) left `reachable`
            // as "never pinged". Nothing is written here now: `doPing` already
            // recorded the truth, and `lastProbeOK` is deliberately NOT stamped
            // so the card keeps saying how old the last REAL reading is.
            // eoc #456 (audit)
        }
        // Stamped on BOTH paths — the attempt clock (no hammering). The DISPLAY
        // clock is `lastProbeOK`, written only where a reading actually came back.
        lastProbe[host.id] = Date()
    }

    // MARK: #456 — ops must prove themselves
    //
    // "Installed" used to mean "the script printed a URI and podman says Up".
    // Every op that creates or changes a deployment now ends with a forced,
    // end-to-end verification of the record it produced. The op's terminal
    // HostBase is NOT blocked on it: the base stays the honest podman-level
    // fact, and health is the separate, honest claim beside it.

    /// #456: forced verification of ONE record, if it still exists.
    private func verifyRecord(_ id: UUID?) async {
        guard let id, let rec = connections.connections.first(where: { $0.id == id }) else { return }
        await health.verify(rec, using: tunnel, force: true)
    }

    /// #456: forced verification of every record this host links to (primary +
    /// extras), read back from the store so a just-finished install is included.
    /// The coordinator runs them one at a time.
    private func verifyLinked(_ hostID: UUID) async {
        guard let host = serverStore.hosts.first(where: { $0.id == hostID }) else { return }
        let ids = [host.lastConnectionID].compactMap { $0 } + (host.extraConnectionIDs ?? [])
        for id in ids { await verifyRecord(id) }
    }

    /// #456: the record this host's PRIMARY container serves, read fresh from
    /// the store (an op may have just linked it).
    private func primaryRecordID(_ hostID: UUID) -> UUID? {
        serverStore.hosts.first(where: { $0.id == hostID })?.lastConnectionID
    }

    /// #456: remember a room per carrier so install / reconfigure stop asking
    /// for what the app already knows (requirement 8). Auto-generated (empty)
    /// rooms are never stored.
    private func rememberRoom(_ options: InstallOptions) {
        let room = options.roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !room.isEmpty else { return }
        RoomMemory.remember(carrier: options.carrier, room: room)
    }

    /// SSH status probe + TCP ping. The probe is the authoritative base setter.
    private func checkServer(_ host: ServerHost) async {
        Task { await doPing(host) }  // parallel TCP ping; updates the Ping metric
        await run(.check, on: host) { secret in
            let (rstate, stats) = try await provisioner.checkReadiness(
                on: host, secret: secret, containerName: host.lastContainerName)
            if let stats { vpsStats[host.id] = stats }
            // #456: stamp the probe so the process caption can say how old this
            // verdict is, and so the on-entry refresh skips a freshly-checked host.
            // Both clocks: `checkReadiness` RETURNED, so this is a real reading.
            lastProbe[host.id]   = Date()
            lastProbeOK[host.id] = Date()   // #456 (audit)
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

    // boc #456: requirement 8 — never blow away a working deployment silently.
    // scripts/srv.sh force-removes EVERY `olcrtc-server-*` container (and every
    // superseded deploy dir) before installing, and Install is the primary CTA
    // whenever no container is on record — which includes "never probed". So a
    // host we don't know is scanned first, and anything found becomes a choice.

    // boc #457: the scan is now VISIBLE and its failure is FATAL to the install.
    // #457 was: the whole body ran silently (tapping Install blocked for seconds
    // with no feedback at all) and swallowed the error —
    //   `guard let found = try? await provisioner.scanContainers(…) else { installFor = host }`
    // — so a scan that could not run fell straight through to the destructive
    // branch. Nothing may be asserted from an absence of information: a failed
    // scan offers NEITHER fork, and says why on the card.
    private func beginInstall(_ host: ServerHost) async {
        guard !actionsDisabled else { return }
        guard !currentBase(host).hasContainer, let secret = secret(for: host) else {
            installFor = host; return
        }
        let previous = currentBase(host)
        // The card already knows how to render a running op — reuse it rather
        // than inventing a second busy vocabulary. `.check` is the honest verb:
        // this IS a read of the server, and its Retry re-runs the full check.
        display[host.id] = HostDisplay.start(.check, from: previous)
            .advanced(note: L10n.vpsScanBeforeInstall.localized())
        do {
            let found = try await provisioner.scanContainers(on: host, secret: secret)
            display[host.id] = .base(previous)
            if found.isEmpty { installFor = host }
            else             { installChoice = InstallChoiceRequest(host: host, found: found) }
        } catch {
            LogStore.shared.log(.provisioning,
                "⚠ pre-install scan failed: \(error.localizedDescription)")
            // The raw Citadel / stderr text never becomes the headline — route it
            // through the same mapper the health layer uses (#456).
            let why = HealthFailureMapper.reason(forSSH: error.localizedDescription).message
            display[host.id] = HostDisplay.start(.check, from: previous)
                .failed(message: L10n.vpsScanFailed_fmt.formatted(why))
        }
    }
    // eoc #457

    /// #456: adopt what is already running — link the container, then recover its
    /// connection (room + key) from the deployed server.yaml. Nothing is
    /// destroyed and nothing is re-asked that the server already knows.
    private func adoptExisting(_ req: InstallChoiceRequest) {
        guard let container = req.found.first else { return }
        restoreContainer(container, on: req.host)
        Task {
            await recoverConnection(req.host, containerName: container.name,
                                    configFile: "server.yaml", asExtra: false)
        }
    }
    // eoc #456

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
        // boc #456: the install must PROVE itself — "installed" stops meaning
        // "the script printed a URI". Also remember the rooms it used.
        rememberRoom(primary)
        for extra in extras { rememberRoom(extra) }
        await verifyLinked(host.id)
        // eoc #456
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
        // #456: a started container is a running PROCESS — prove it carries
        // traffic before anything on this card turns green.
        await verifyRecord(primaryRecordID(host.id))
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
        // boc #456: a reconfigure rewrites room/transport server-side — the row's
        // old verdict describes a deployment that no longer exists, so re-measure.
        rememberRoom(options)
        await verifyRecord(recordID)
        // eoc #456
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

    // boc #457: `protocolsSection`, `carrierRowView` and `carrierRowLead` moved
    // to App/Views/ProtocolRowView.swift (the row) and App/Views/ServerCardView.swift
    // (the section around it); `rowView` above resolves one row's inputs. What
    // changed on the way out:
    //   • #455's aurora WASH, its `signalCyan` hairline and the cyan checkmark
    //     are gone — `Theme.Palette.auroraSoft` is deleted, and "live" was a
    //     colour with no word behind it. The aurora is now a 3pt leading spine
    //     shown only on a live row a probe has VERIFIED: a verdict, not a style.
    //   • the raw `podman ps` status ("Up 3 hours", "Exited (137) 5 minutes ago")
    //     is out of the row subtitle; a stopped protocol says so in one sentence.
    // eoc #457

    // #456 was: carrierStatusColor(_:) — the podman-"Up"→green rule that painted
    // the user's dead telemost row green. Deleted; the dot is health-driven now.

    /// #456: probe THIS row end-to-end and stamp the result. Forced — the user
    /// asked, so the coordinator's 2-minute debounce doesn't apply.
    private func verifyRow(_ host: ServerHost, row: SSHRunner.CarrierInfo) {
        guard let rec = connectionRecord(host, row: row) else {
            alertText = L10n.protocolRecordMissing.localized()
            return
        }
        Task { await health.verify(rec, using: tunnel, force: true) }
    }

    private func carrierMenuItems(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> [OlcMenuItem] {
        let rowState = rowHealth(host, row: row)   // #456
        let suggested = rowState.suggestedAction   // #457
        var items: [OlcMenuItem] = []
        // boc #457: a verdict that names its own fix must OFFER that fix, and
        // offer it first. `HealthReason.action` has always returned one
        // (keyMismatch → Recover connection, roomInvalid → Change room) and it
        // was never wired to anything — the row menu opened with actions that
        // assume the protocol already works. Whichever item the verdict points
        // at is hoisted to the top and skipped in its usual position below, so
        // the menu never lists the same action twice.
        if suggested == .recoverConnection { items.append(recoverItem(host, row: row)) }
        if suggested == .checkRoom         { items.append(reconfigureItem(host, row: row)) }
        // eoc #457
        // #456: Verify comes next — the honest answer to "can I use this?" is one
        // tap away, instead of buried under actions that assume it already works.
        items.append(.action(L10n.healthActionVerify.localized(), systemImage: "checkmark.shield") {
            verifyRow(host, row: row)
        })
        items.append(.action(L10n.protocolConnectAction.localized(), systemImage: "personalhotspot") {
            connectVia(host, row: row)
        })
        // #457 was: `row.status.shortLabel.hasPrefix("Up")` — string-matching a
        // user-visible label. `ContainerStatus.parse` already decided this.
        if Self.isUp(row.status) {
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
        if suggested != .checkRoom { items.append(reconfigureItem(host, row: row)) }   // #457
        // #456 was: `if connectionRecord(host, row: row) == nil` — the user's actual
        // incident was the opposite case: they reinstalled the server, so its key
        // changed, their stored key stopped matching, and the handshake failed with
        // "read welcome / handshake client". A row whose probe reported a key
        // mismatch now offers Recover right here, stale record and all.
        // #457: …and when the verdict asked for it, it is already at the top.
        if suggested != .recoverConnection, connectionRecord(host, row: row) == nil {
            items.append(recoverItem(host, row: row))
        }
        // #456: explain a failure in human terms, in place — never raw core log
        // lines. "Couldn't check" gets the same item; it is a different sentence.
        switch rowState {
        case .broken, .inconclusive:
            items.append(.action(L10n.healthShowReasonAction.localized(), systemImage: "questionmark.circle") {
                alertText = "\(rowState.title)\n\n\(rowState.subtitle)"
            })
        default:
            break
        }
        if !row.isPrimary {
            items.append(.divider)
            items.append(.action(L10n.removeProtocolAction.localized(), systemImage: "trash", role: .destructive) {
                removeCarrierConfirm = CarrierRemoveRequest(host: host, row: row)
            })
        }
        return items
    }

    /// #457: "Re-read the settings from the server" as ONE item, so it can be
    /// hoisted to the top of the menu when the verdict asks for it without being
    /// written out twice.
    private func recoverItem(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> OlcMenuItem {
        .action(L10n.actionRecoverConnection.localized(), systemImage: "arrow.counterclockwise.circle") {
            recoverRowRequest = CarrierRecoverRequest(
                host: host, container: row.container, file: row.file, isPrimary: row.isPrimary)
        }
    }

    /// #457: same, for "Change room / transport".
    private func reconfigureItem(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> OlcMenuItem {
        .action(L10n.actionChangeRoomTransport.localized(), systemImage: "slider.horizontal.3") {
            // #456: seeded through the shared builder, so the wbstream token and
            // the jitsi instance the record already holds are carried in.
            reconfigureRequest = rowReconfigureRequest(host, row: row)
        }
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
            // boc #456: prove the protocol we just added actually carries
            // traffic, and remember the room it used. Fire-and-forget: this
            // function holds `carrierBusyHostID` until it returns (its `defer`),
            // and a ~10 s probe must not keep the row's menus locked — the chip
            // renders `.checking` on its own while the coordinator works.
            rememberRoom(options)
            let addedID = record.id
            Task { await verifyRecord(addedID) }
            // eoc #456
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
            // #456: same rule as the primary Start — a running process is not
            // yet a working protocol, so measure it before anything turns green.
            // Fire-and-forget for the same reason as addCarrier (busy flag).
            let startedID = connectionRecord(host, row: row)?.id
            Task { await verifyRecord(startedID) }
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
    /// #456: when the rows are NOT loaded yet the seeds used to be nil — the
    /// sheet opened blank and confirming it rewrote the server with defaults.
    /// Fall back to the host's linked record, which carries the same values.
    private func primaryReconfigureRequest(_ host: ServerHost) -> ReconfigureRequest? {
        guard let cname = host.lastContainerName else { return nil }
        let row = carrierRows[host.id]?.first(where: { $0.isPrimary })
        let rec = linkedConnection(host)
        var carrier   = row?.provider
        var transport = row?.transport
        var room      = row?.room
        if carrier == nil, let rec, case .olcrtc(let p) = rec.details {
            carrier = p.carrier; transport = p.transport; room = p.roomID
        }
        return ReconfigureRequest(host: host, containerName: cname,
                                  recordID: host.lastConnectionID,
                                  initialCarrier: carrier,
                                  initialTransport: transport,
                                  initialRoom: room,
                                  initialWbToken: Self.wbToken(of: rec),
                                  initialJitsiBase: Self.jitsiBase(of: rec))
    }

    /// #456: reconfigure targeted at ONE protocol row, seeded with everything
    /// the app already knows about it.
    private func rowReconfigureRequest(_ host: ServerHost, row: SSHRunner.CarrierInfo) -> ReconfigureRequest {
        let rec = connectionRecord(host, row: row)
        return ReconfigureRequest(host: host, containerName: row.container,
                                  recordID: rec?.id,
                                  initialCarrier: row.provider,
                                  initialTransport: row.transport,
                                  initialRoom: row.room,
                                  initialWbToken: Self.wbToken(of: rec),
                                  initialJitsiBase: Self.jitsiBase(of: rec))
    }

    /// #456: the wbstream token the record already holds (Keychain-hydrated by
    /// ConnectionStore). Seeding it is what stops a reconfigure from deleting
    /// the server's `auth.token` line just because the field started blank.
    private static func wbToken(of rec: ConnectionRecord?) -> String? {
        guard let rec, case .olcrtc(let p) = rec.details, !p.wbToken.isEmpty else { return nil }
        return p.wbToken
    }

    /// #456: the jitsi instance behind a full room URL ("https://host/room" →
    /// "https://host"), so reconfiguring a self-hosted Jitsi doesn't silently
    /// fall back to the shared public default.
    private static func jitsiBase(of rec: ConnectionRecord?) -> String? {
        guard let rec, case .olcrtc(let p) = rec.details, p.carrier == "jitsi",
              let url = URL(string: p.roomID), let scheme = url.scheme,
              let h = url.host, !h.isEmpty else { return nil }
        if let port = url.port { return "\(scheme)://\(h):\(port)" }
        return "\(scheme)://\(h)"
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
                                    // boc #457: the bare 8pt unlabelled dot is gone — a shape
                                    // whose only channel was hue, next to text that already
                                    // says the same thing.
                                    // #350 was: Color.green / Color.orange — route through Theme.Palette.
                                    // #456 (audit) was: `hasPrefix("Up") ? Theme.Palette.green`
                                    // — the LAST podman-"Up"→green rule left in the app.
                                    // #457 was: Circle().fill(…).frame(width: 8, height: 8)
                                    Image(systemName: Self.scanGlyph(container.status))
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                    // eoc #457
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
        // #456 was: display[host.id] = .base(.stopped) — the scan had ALREADY
        // told us whether the container is Up; seeding "stopped" for a running
        // one was a present-tense claim we held evidence against.
        // #457 was: `container.status.shortLabel.hasPrefix("Up")`
        let base: HostBase = Self.isUp(container.status) ? .running : .stopped
        display[host.id] = .base(base)
        // #456: the scan IS a fresh SSH observation — both clocks.
        lastProbe[host.id]   = Date()
        lastProbeOK[host.id] = Date()   // #456 (audit)
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
    // boc #456: the sheet used to seed these blank, so confirming a wbstream
    // reconfigure DELETED the server's auth.token and a self-hosted jitsi
    // silently fell back to the shared public default. Defaulted + last, so
    // every pre-#456 construction still compiles.
    var initialWbToken: String? = nil
    var initialJitsiBase: String? = nil
    // eoc #456
    var id: String { containerName }
}

/// #456: an install about to run on a host that already carries olcrtc
/// containers. `scripts/srv.sh` force-removes EVERY `olcrtc-server-*` container
/// (and its rooms and keys) before installing, so the user chooses between
/// adopting what is there and a deliberate, warned reinstall.
struct InstallChoiceRequest: Identifiable {
    let id = UUID()
    let host: ServerHost
    let found: [SSHRunner.FoundContainer]
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
// #457 was: the previews passed `logsRouter: LogsRouter()`.
#Preview("Servers — Dark") {
    ServersView(serverStore: ServerHostStore(), connections: ConnectionStore(),
                botStore: BotStore(), tunnel: TunnelManager())
        .preferredColorScheme(.dark)
}
#Preview("Servers — Light") {
    ServersView(serverStore: ServerHostStore(), connections: ConnectionStore(),
                botStore: BotStore(), tunnel: TunnelManager())
        .preferredColorScheme(.light)
}
#endif
