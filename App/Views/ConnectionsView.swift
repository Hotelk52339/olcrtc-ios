import SwiftUI

// MARK: - ConnectionsView — the Connect tab (#457, restructured #459)
//
// JOB: state the truth about the tunnel right now, and offer the ONE action that
// changes it. Nothing is drawn that cannot be dated.
//
// Top to bottom:
//   1. ConnectHero          — the state as the largest text on the screen, the
//                             connection it applies to, one line of dated
//                             evidence, the scope, one labelled button, and that
//                             connection's action menu.
//   2. Diagnostics          — "This session" (protocol / exit / latency, only
//                             while connected) + "Checks" (IP check / speed test
//                             / carrier endpoints). See HealthCard.swift.
//   3. Switch to            — one row per OTHER connection: name, kind, and one
//                             `OlcHealthChip`. TAP = connect.
//
// #459: THE ONE STRUCTURAL DECISION — the hero's subject is NOT in the list.
// `heroSubjectID` (the live node while a session is up, else `store.primary`) is
// skipped when the rows are drawn, so a connection's name appears exactly once
// on this screen. That answers both halves of the owner's complaint: the
// duplication between the hero and the rows is gone BY CONSTRUCTION, and "which
// one is selected?" is answered by POSITION and CONTAINER — the selected node is
// the big card at the top, the one with the button in it. That is the only
// selection marker; no accent bar, no badge, no new vocabulary. (The existing
// `auroraVerdictRing` is a VERDICT mark, not a selection mark.)
//
// The filtering happens at RENDER time, not in `recompute()`: keeping `groups`
// whole means `groupHeader`'s failing count and `groupFooter`'s subscription
// metadata still describe the real group, and a group whose only member is the
// hero's subject renders as an empty `Section` rather than silently dropping its
// quota footer.
//
// #459: DIAGNOSTICS MOVED ABOVE THE LIST. It describes the hero's subject, and
// the list is a switcher, so the switcher goes last. (#457's note about demoting
// it below the list, and about a future pushed "Check & why" screen, is retired:
// Diagnostics is now the ONE card, having absorbed the old `HealthCard`.)
//
// #459: PULL TO REFRESH replaces the per-group "Verify all" button. See
// `refreshEverything()`.
//
// #457 (structure) was: hero → diagnostics → servers, with `.navigationTitle("OlcRTC")`
// above it all. A 34 pt brand name carrying no information sat over a 15 pt
// status pill, and three always-rendered buttons that show nothing until pressed
// held the second-best position on the app's most-used screen. The brand name is
// gone (inline title), the answer is the largest thing here, and diagnostics sit
// under the content they are about.
//
// #457 (surgery discipline): this file had already hit the SwiftUI type-checker's
// expression budget twice. Every change is by EXTRACTION — the hero lives in
// ConnectHero.swift, the row in ConnectionRowView.swift, the diagnostics card in
// HealthCard.swift, and the List's modifiers are split across two small wrapper
// functions. Nothing here has a `body` over ~20 lines or a chain over ~8.
//
// #456: the row verdicts are `HealthCoordinator`'s persisted, timestamped
// evidence. Green means an HTTP 2xx came back through that node's OWN SOCKS
// listener, minutes ago — not "we ran something once".

struct ConnectionsView: View {
    @ObservedObject var store   : ConnectionStore
    @ObservedObject var tunnel  : TunnelManager
    @ObservedObject var ipCheck : IPChecker
    @ObservedObject var speed   : SpeedTest
    /// #361: routes a subscription pasted into the AddConnection import box (an
    /// https URL or raw sub.md body) up to MainTabView's confirm-then-import flow.
    var onPasteImport: ((OlcrtcSubscription.ImportInput) -> Void)? = nil

    // #337: observe the screenshot-safe toggle so IP displays re-mask live.
    // #457: also the source of `tunnelMode` for the hero's permanent scope line.
    @ObservedObject private var settings = SettingsStore.shared
    // #456: the ONE health vocabulary — a singleton because it is written by
    // non-view code (TunnelManager) and read by two tabs.
    @ObservedObject private var health = HealthCoordinator.shared

    // #330: ONE enum-driven sheet. Multiple `.sheet` modifiers on one view is
    // unsupported in SwiftUI and, when the host re-renders under a live tunnel,
    // the editor sheet hangs on present and on dismiss.
    @State private var activeSheet: ConnectionSheet?

    /// #403: per-group subscription metadata, cached — `body` re-evaluates ~10×/s
    /// during a speed test and must not recompute it.
    @State private var subInfoByGroup: [String: (source: String, meta: ConnectionStore.SubscriptionMeta)] = [:]
    /// #413: the grouped connection list, cached for the same reason.
    @State private var groups: [(group: String, items: [ConnectionRecord])] = []

    // boc #457 was: @State alertText — a one-OK alert titled `healthWhyTitle`,
    // reached from a "What's wrong?" overflow item. The reason and its fix are
    // now ON the failing row, which is where the user is already looking.
    // eoc #457

    /// #330: the single sheet this view can present.
    private enum ConnectionSheet: Identifiable {
        case add
        case edit(ConnectionRecord)
        case qr(ConnectionRecord)
        case carrierEndpoints(OlcrtcConnection)   // #406
        case share(ConnectionRecord)              // #456

        var id: String {
            switch self {
            case .add:              return "add"
            case .edit(let c):      return "edit-\(c.id.uuidString)"
            case .qr(let c):        return "qr-\(c.id.uuidString)"
            case .carrierEndpoints: return "carrier"
            case .share(let c):     return "share-\(c.id.uuidString)"
            }
        }
    }

    /// #455: only the in-app PROXY exposes a local SOCKS port to probe through. In
    /// VPN mode the whole device already routes through the tunnel, so a plain
    /// `.direct` request IS tunnelled.
    private var currentMode: RouteMode {
        (tunnel.state.isConnected && tunnel.activeMode == .proxy) ? .tunnel : .direct
    }

    // MARK: Body

    var body: some View {
        // #459: the List's modifiers are split across two wrappers. This file has
        // blown the SwiftUI type-checker's budget twice; one chain of eleven
        // modifiers on a `List` whose content is four dynamic sections is exactly
        // how it happened.
        NavigationStack {
            listWiring(listChrome(connectionList))
        }
        // #459: the manual equivalent of the pull, on entry — governed by the
        // "Check on opening" switch. The contract, stated once: THE TOGGLE
        // DECIDES WHETHER THE APP CHECKS BY ITSELF; A PULL ALWAYS CHECKS.
        .onAppear { entrySweep() }
        // #456: an in-flight native probe can't be interrupted, but leaving the tab
        // stops the coordinator from starting further ones.
        .onDisappear { health.cancelAll() }
    }

    /// #459 was: `HealthCard` sat between the hero and the list, and Diagnostics
    /// sat under the list. Both reported latency; only one of them could date it.
    private var connectionList: some View {
        List {
            Section { heroBlock }
            diagnosticsSection
            connectionsSection
        }
    }

    private func listChrome(_ content: some View) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.bg)
            // #459 was: `refreshSubscriptions()` only, with a per-group "Verify
            // all" button in every section header.
            .refreshable { await refreshEverything() }
    }

    private func listWiring(_ content: some View) -> some View {
        content
            .onChange(of: store.connections, initial: true) { _, _ in recompute() }
            .onChange(of: store.subscriptionMeta) { _, _ in recompute() }
            .onChange(of: tunnel.state) { old, new in stateChanged(from: old, to: new) }
            // #457 was: `.navigationTitle("OlcRTC")` — 34 pt of the most valuable
            // space spent on a word carrying no information.
            .navigationTitle(L10n.tabConnections.localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { addButton } }
            .sheet(item: $activeSheet) { sheetContent($0) }
    }

    private var addButton: some View {
        Button { activeSheet = .add } label: { Image(systemName: "plus") }
            .accessibilityLabel(L10n.newConnectionTitle.localized())
    }

    // MARK: 1. Hero

    private var heroBlock: some View {
        ConnectHero(state: tunnel.state,
                    subject: heroSubject,
                    health: heroSubject.map { health.display(for: $0.id) } ?? HealthDisplay.never,
                    exitFlag: exitFlag,
                    exitPlace: exitPlace,
                    mode: tunnel.state.isConnected ? tunnel.activeMode : settings.tunnelMode,
                    socksPort: tunnel.boundPort ?? settings.socksPort,
                    secretsLocked: store.secretsLocked,
                    // #459: the subject has no row any more, so it carries the
                    // row's own action set — the SAME builder, not a copy.
                    menuItems: heroSubject.map { rowMenuItems($0) } ?? [],
                    onConnect: { heroConnect() },
                    onDisconnect: { heroDisconnect() })
            .olcCardRow()
    }

    /// #456: the record the hero describes — the LIVE node while a session is up
    /// (never `store.primary`, which a row tap used to move without reconnecting),
    /// else the last-used one, which is also the node a Connect tap will dial.
    private var heroSubject: ConnectionRecord? {
        tunnel.state.isConnected ? tunnel.connectedRecord : store.primary
    }

    /// #459: the hero's subject is drawn in the hero, never again in the list.
    private var heroSubjectID: UUID? { heroSubject?.id }

    /// #459: the exit as the hero prints it — "Amsterdam, NL". nil whenever the
    /// lookup gave nothing usable, in which case the hero falls back to the
    /// honesty layer's own dated sentence.
    private var exitPlace: String? {
        guard let geo = ipCheck.exitGeo, geo != IPChecker.ExitGeo() else { return nil }
        let place = [geo.city, geo.country].compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty ? nil : place
    }

    private var exitFlag: String? {
        guard let cc = ipCheck.exitGeo?.country else { return nil }
        return CountryFlag.emoji(iso2: cc)
    }

    private func heroConnect() {
        guard let p = store.primary else { return }
        Haptics.impact()                // the one press-level haptic in the app
        tunnel.connect(record: p)       // #393: the secrets guard lives in connect()
    }

    private func heroDisconnect() {
        Haptics.impact()
        tunnel.disconnect()
    }

    /// #455: physical feedback on the OUTCOME — success only after `verifyTunnel`
    /// returned 200, an error buzz when the attempt gives up. #454: the exit geo is
    /// fetched on the connect transition and cleared on the way down.
    private func stateChanged(from old: ConnectionState, to new: ConnectionState) {
        if new.isConnected, !old.isConnected {
            Haptics.success()
        } else if case .failed = new, old != new {
            Haptics.error()
        }
        if new.isConnected {
            Task { await ipCheck.refreshExitGeo(via: currentMode) }
        } else {
            ipCheck.clearExitGeo()
        }
    }

    // MARK: 3. The connection list — the switcher

    @ViewBuilder
    private var connectionsSection: some View {
        if store.connections.isEmpty {
            Section {
                OlcEmptyState(systemImage: "network",
                              title: L10n.emptyNoConnections.localized(),
                              hint: L10n.emptyNoConnectionsHint.localized(),
                              ctaTitle: L10n.newConnectionTitle.localized()) {
                    activeSheet = .add
                }
                .olcCardRow()
            }
        } else {
            // #459 was: a `pullToRefreshHint` row — a caption instructing the
            // user to perform a standard system gesture. The gesture now does
            // considerably more, and still needs no caption.
            ForEach(groups, id: \.group) { group in
                Section {
                    connectionRows(group.items)
                } header: {
                    groupHeader(group.group, items: group.items)
                } footer: {
                    groupFooter(group.group)
                }
            }
        }
    }

    /// #459: the hero's subject is skipped. `excluded` is read once per SECTION,
    /// never per row (CLAUDE.md: don't derive in `body` on a view that
    /// re-evaluates ~10×/s during a speed test), and the filtering is a per-row
    /// `if` rather than a `filter` so no new array is built either.
    private func connectionRows(_ items: [ConnectionRecord]) -> some View {
        let excluded = heroSubjectID
        return ForEach(items) { conn in
            rowUnlessHeroSubject(conn, excluded: excluded)
        }
    }

    @ViewBuilder
    private func rowUnlessHeroSubject(_ conn: ConnectionRecord, excluded: UUID?) -> some View {
        if conn.id != excluded { row(conn) }
    }

    /// #459: a group whose ONLY member is the hero's subject keeps its Section —
    /// so `groupFooter`'s subscription quota still renders — but drops its header,
    /// because a "Switch to" heading over nothing is a promise the list can't keep.
    private func hasVisibleRows(_ items: [ConnectionRecord]) -> Bool {
        let excluded = heroSubjectID
        return items.contains { $0.id != excluded }
    }

    private func row(_ conn: ConnectionRecord) -> some View {
        // #459 was: also `isLive:` — the live node is the hero's subject and is
        // therefore never in this list, so the "Live" badge could never render.
        ConnectionRowView(record: conn,
                          display: health.display(for: conn.id),
                          maskIPs: settings.maskIPs,
                          menuItems: rowMenuItems(conn),
                          onConnect: { connect(conn) },
                          onVerify: { verify(conn) })
            .olcCardRow()
            .swipeActions(edge: .trailing) { rowSwipeActions(conn) }
    }

    @ViewBuilder
    private func rowSwipeActions(_ conn: ConnectionRecord) -> some View {
        Button(role: .destructive) { remove(conn) } label: {
            // #457 was: `actionRemoveFromList` ("Remove host from list") — a
            // connection is not a host, and `trash` is reserved for irreversible
            // server-side destruction.
            Label(L10n.connectRowRemove.localized(), systemImage: "minus.circle")
        }
        Button { activeSheet = .edit(conn) } label: {
            Label(L10n.edit.localized(), systemImage: "pencil")
        }
        // #457 was: `.tint(Theme.Palette.orange)` — amber now means in-flight only.
        .tint(Theme.Palette.accent)
    }

    /// #457: a tap on a row CONNECTS through it. `connect(record:)` already
    /// disconnects-then-dials, so this is safe from any state. `store.primary` is
    /// kept in step as a SIDE EFFECT — it is no longer a user-facing concept, but
    /// auto-connect-on-launch and the hero's idle subject still read it.
    /// #457 was: `Haptics.tap()` + `store.setPrimary(conn.id)` and no connection.
    private func connect(_ conn: ConnectionRecord) {
        store.setPrimary(conn.id)
        Haptics.impact()
        tunnel.connect(record: conn)
    }

    private func verify(_ conn: ConnectionRecord) {
        Task { await health.verify(conn, using: tunnel, force: true) }
    }

    private func remove(_ conn: ConnectionRecord) {
        if let i = store.connections.firstIndex(where: { $0.id == conn.id }) {
            store.remove(at: IndexSet([i]))
        }
    }

    // MARK: Section chrome

    /// #459: the default group's header says what the list below it IS — a
    /// switcher for everything that is not the hero's subject. #457 had left it
    /// blank because its own name ("Connections") repeated the tab it sits in;
    /// "Switch to" is the same length and carries the whole structural decision.
    ///
    /// #459 was: `groupHealthControl` — a per-group "Verify all" button plus its
    /// spinner, sitting in a section header. Pull-to-refresh replaces it, checks
    /// EVERYTHING rather than one group, and reports progress per row instead of
    /// through one header spinner.
    @ViewBuilder
    private func groupHeader(_ group: String, items: [ConnectionRecord]) -> some View {
        if hasVisibleRows(items) {
            HStack(spacing: 8) {
                Text(group == ConnectionRecord.defaultGroupName
                     ? L10n.connectListOtherHeader.localized()
                     : ConnectionRecord.displayGroupName(group))
                failingBadge(items)
                Spacer()
            }
        }
    }

    /// #456: `HealthCoordinator.summary` reports the BEST evidence, which on its
    /// own lets one working node hide a dead sibling. The count is the pairing that
    /// keeps a known failure from being silent.
    @ViewBuilder
    private func failingBadge(_ items: [ConnectionRecord]) -> some View {
        if let label = failingLabel(items) {
            Text(label)
                .foregroundStyle(Theme.Palette.red)
                .textCase(nil)
        }
    }

    private func failingLabel(_ items: [ConnectionRecord]) -> String? {
        let counts = health.failingCount(for: items.map(\.id))
        guard counts.failing > 0 else { return nil }
        return L10n.connectGroupFailing_fmt.formatted(counts.failing, counts.total)
    }

    // boc #459
    // #459 was: `groupHealthControl(_:)` — an `if items.contains(where: health
    // .isChecking) { ProgressView() } else { Button(healthVerifyAllAction) { … } }`
    // in every section header. The owner asked for "something like the Verify all
    // button — but not a button, a SWIPE DOWN". `refreshEverything()` below is it.
    // eoc #459

    @ViewBuilder
    private func groupFooter(_ group: String) -> some View {
        if let info = subInfoByGroup[group] {
            SubscriptionMetaFooter(source: info.source, meta: info.meta)
        }
    }

    // MARK: 2. Diagnostics — the ONE card (defined in HealthCard.swift)

    /// #459: promoted ABOVE the list (it describes the hero's subject) and merged
    /// with the old `HealthCard`. `Diagnostics` is the name that survives.
    private var diagnosticsSection: some View {
        Section {
            DiagnosticsCard(record: tunnel.connectedRecord,
                            ipCheck: ipCheck, speed: speed,
                            mode: currentMode, maskIPs: settings.maskIPs,
                            isConnected: tunnel.state.isConnected,
                            carrierParams: activeOlcrtcParams,
                            onSpeedTest: { runSpeedTest() },
                            onCarrierEndpoints: { activeSheet = .carrierEndpoints($0) })
                .olcCardRow()
        } header: {
            Text(L10n.diagnosticsTitle.localized())
        }
    }

    /// #389: the LIVE node's params (not `store.primary`, which a row tap desyncs)
    /// — the carrier-endpoint tool must name the host the tunnel actually holds.
    private var activeOlcrtcParams: OlcrtcConnection? {
        guard case .olcrtc(let p)? = tunnel.connectedRecord?.details else { return nil }
        return p
    }

    /// #285: pass the LIVE carrier/transport into the speed test so the header logs
    /// the connection type and the datachannel hint can fire.
    private func runSpeedTest() {
        var carrier: String?
        var transport: String?
        if currentMode == .tunnel, case .olcrtc(let p)? = tunnel.connectedRecord?.details {
            carrier = p.carrier
            transport = p.transport
        }
        Task { await speed.run(via: currentMode, carrier: carrier, transport: transport) }
    }

    // MARK: Row actions

    /// #457 was: this menu also held "Connect" (offered only on rows that were NOT
    /// primary — i.e. missing on exactly the row you most wanted) and "What's
    /// wrong?" (an alert). Tapping the row connects; the reason and its fix are on
    /// the row itself.
    ///
    /// #459 was: this menu also opened with "Verify". The row's `OlcHealthChip`
    /// IS the verify affordance now — a 44 pt target that re-probes on tap — and
    /// the hero, which shows this same menu for its own subject, is covered by
    /// the pull gesture.
    private func rowMenuItems(_ conn: ConnectionRecord) -> [OlcMenuItem] {
        var items: [OlcMenuItem] = []
        // #456: connection-ONLY share — the `olcrtc://` URI and nothing else, so it
        // grants NO VPS/SSH access.
        items.append(.action(L10n.shareConnectionTitle.localized(), systemImage: "square.and.arrow.up") {
            activeSheet = .share(conn)
        })
        items.append(.divider)
        items.append(.action(L10n.copyURIAction.localized(), systemImage: "doc.on.doc") {
            UIPasteboard.general.string = Self.uriOf(conn)
            LogStore.shared.log(.connection, L10n.copiedURI_fmt.formatted(conn.displayName))
        })
        items.append(.action(L10n.actionQR.localized(), systemImage: "qrcode") {
            activeSheet = .qr(conn)
        })
        items.append(.divider)
        items.append(.action(L10n.edit.localized(), systemImage: "pencil") { activeSheet = .edit(conn) })
        // #457 was: `actionRemoveFromList` + systemImage "trash" — the string says
        // "host" on a connection row, and `trash` is reserved for irreversible
        // server-side destruction; this only tidies the local list.
        items.append(.action(L10n.connectRowRemove.localized(),
                             systemImage: "minus.circle", role: .destructive) {
            remove(conn)
        })
        return items
    }

    /// Reassembles the original `olcrtc://` URI for sharing / copy / QR.
    private static func uriOf(_ conn: ConnectionRecord) -> String {
        switch conn.details {
        case .olcrtc(let p): return OlcrtcURI.encode(p)
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ConnectionSheet) -> some View {
        switch sheet {
        case .add:
            AddConnectionView(existingGroups: store.allGroupNames,
                              onImport: { input in
                                  activeSheet = nil   // #361: hand off to the confirm flow
                                  onPasteImport?(input)
                              }) {
                store.add($0)
            }
        case .edit(let conn):
            AddConnectionView(existing: conn, existingGroups: store.allGroupNames) {
                store.update($0)
            }
        case .qr(let conn):
            qrSheet(conn)
        case .carrierEndpoints(let params):
            CarrierEndpointsView(params: params)
        case .share(let conn):
            ShareConnectionView(conn: conn)
        }
    }

    private func qrSheet(_ conn: ConnectionRecord) -> some View {
        NavigationStack {
            QRCodeView(uri: Self.uriOf(conn))
                .padding(32)
                .navigationTitle(conn.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.actionDone.localized()) { activeSheet = nil }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: Caches

    /// #403/#413: rebuild the cached grouped list + per-group subscription meta.
    /// Runs only when the inputs change, never inside `body`.
    private func recompute() {
        let grouped = store.grouped()
        groups = grouped
        var map: [String: (source: String, meta: ConnectionStore.SubscriptionMeta)] = [:]
        for group in grouped {
            if let info = store.subscriptionInfo(for: group.items) {
                map[group.group] = info
            }
        }
        subInfoByGroup = map
    }

    /// #411: manual pull-to-refresh — force-refresh every subscription source.
    private func refreshSubscriptions() async {
        guard store.hasSubscriptions else { return }
        _ = await store.refreshAllSources()
    }

    // MARK: Refresh — the gesture that replaced the button (#459)

    /// #459: how long the pull spinner may be held for the health sweep. The
    /// sweep is sequential and each probe owns a 20 s budget
    /// (`HealthPolicy.probeTimeoutMs`), so without a cap one dead carrier would
    /// pin the spinner for minutes. Past the cap the sweep keeps running and the
    /// rows keep saying "Checking…", which is the honest report either way.
    private static let pullSweepMaxSeconds: TimeInterval = 20

    /// #459 was: `refreshSubscriptions()` alone, with a per-group "Verify all"
    /// button beside it. A pull now refreshes the STATE OF EVERYTHING, which is
    /// what the owner asked the gesture to mean:
    ///   • every connection's end-to-end health probe (`verifyDue`, the same pass
    ///     the on-entry sweep runs — uncapped, no staleness filter, and left to
    ///     the coordinator so `sweepTask` bookkeeping and `cancelAll()` still
    ///     apply to it);
    ///   • the tunnel's exit geo, while a session is up (the hero's evidence line
    ///     and Diagnostics → Exit both read it);
    ///   • every subscription source.
    ///
    /// It ignores `SettingsStore.refreshOnEntry`: that switch governs only what
    /// the app does BY ITSELF.
    private func refreshEverything() async {
        health.verifyDue(store.connections, using: tunnel)
        if tunnel.state.isConnected {
            await ipCheck.refreshExitGeo(via: currentMode)
        }
        await refreshSubscriptions()
        await awaitSweep()
    }

    /// #459: hold the spinner while the coordinator is actually probing, so the
    /// gesture reports real work instead of snapping back on a fire-and-forget.
    /// Gives up on the cap, and the moment the refresh task itself is cancelled.
    private func awaitSweep() async {
        // The sweep is a `Task` the coordinator has only just scheduled; give it
        // the actor before deciding it never started.
        try? await Task.sleep(for: .milliseconds(120))
        let deadline = Date().addingTimeInterval(Self.pullSweepMaxSeconds)
        while !Task.isCancelled, Date() < deadline, sweepInFlight {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private var sweepInFlight: Bool {
        store.connections.contains { health.isChecking($0.id) }
    }

    /// #459: the automatic twin of the pull, on tab entry — the same uncapped
    /// `verifyDue` pass, but debounced by `HealthPolicy.minRecheckSeconds` and
    /// gated on the user's "Check on opening" switch. Connections had no on-entry
    /// sweep at all before this, so that switch governed only the Servers tab and
    /// the foreground transition.
    private func entrySweep() {
        guard settings.refreshOnEntry else { return }
        health.verifyDue(store.connections, using: tunnel)
    }
}

// MARK: - SubscriptionMetaFooter (#363, extracted #457)
//
// Per-group subscription metadata. Every value is server-provided free text, so
// it renders as plain captions with no styling derived from the input.

private struct SubscriptionMetaFooter: View {
    let source: String
    let meta: ConnectionStore.SubscriptionMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(L10n.subMetaSource.localized(), Self.displaySource(source))
            if let count = meta.serverCount {
                line(L10n.subMetaServers.localized(), String(count))
            }
            line(L10n.subMetaRefresh.localized(), Self.refreshDisplay(meta.refreshInterval))
            if let used = meta.used, !used.isEmpty {
                line(L10n.subMetaUsed.localized(), used)
            }
            if let available = meta.available, !available.isEmpty {
                line(L10n.subMetaAvailable.localized(), available)
            }
        }
        .padding(.top, 4)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.Palette.textTertiary)
            Text(value)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.caption2)
    }

    /// #363: a readable host for the source link. Falls back to the raw string.
    private static func displaySource(_ source: String) -> String {
        URL(string: source)?.host ?? source
    }

    /// #363: the stored `#refresh` interval, as the largest whole unit.
    private static func refreshDisplay(_ interval: TimeInterval?) -> String {
        guard let i = interval, i > 0 else { return L10n.subMetaRefreshNever.localized() }
        let s = Int(i)
        let text: String
        switch s {
        case let n where n % 86400 == 0: text = "\(n / 86400)d"
        case let n where n % 3600  == 0: text = "\(n / 3600)h"
        case let n where n % 60    == 0: text = "\(n / 60)m"
        default:                         text = "\(s)s"
        }
        return L10n.subMetaRefreshInterval_fmt.formatted(text)
    }
}

// boc #459
// #459 was: ConnectDiagnosticsCard and ConnectIPStatus lived here. Both moved
// into HealthCard.swift, where the old health strip merged into them as the
// Diagnostics card's "This session" block. A move, not a cut — and this file
// sheds the ~180 lines the type-checker was carrying for them.
// eoc #459

// #340: both appearance variants.
#if DEBUG
#Preview("Connect — Dark") {
    ConnectionsView(store: ConnectionStore(), tunnel: TunnelManager(),
                    ipCheck: IPChecker(), speed: SpeedTest())
        .preferredColorScheme(.dark)
}
#Preview("Connect — Light") {
    ConnectionsView(store: ConnectionStore(), tunnel: TunnelManager(),
                    ipCheck: IPChecker(), speed: SpeedTest())
        .preferredColorScheme(.light)
}
#endif
