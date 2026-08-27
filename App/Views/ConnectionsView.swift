import SwiftUI

// MARK: - ConnectionsView — the Connect tab (#457)
//
// JOB: state the truth about the tunnel right now, and offer the ONE action that
// changes it. Nothing is drawn that cannot be dated.
//
// Top to bottom:
//   1. ConnectHero          — the state as the largest text on the screen, the
//                             connection it applies to, one line of dated
//                             evidence, the scope, and one labelled button.
//   2. HealthCard           — the dated evidence strip, only while a session is up.
//   3. Connections          — one row per connection: glyph + word + age, plus the
//                             fix when something is wrong. TAP = connect.
//   4. Diagnostics          — IP check / speed test / carrier endpoints, demoted
//                             below the list (see the DIAGNOSTICS note below).
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
// ConnectHero.swift, the row in ConnectionRowView.swift, the strip in
// HealthCard.swift, and the diagnostics card is a sibling struct below with its
// own small body. Nothing here has a `body` over ~40 lines.
//
// DIAGNOSTICS: the plan retires this card into a pushed "Check & why" screen. That
// screen does not exist yet, and IP check / speed test / carrier endpoints have no
// other entry point, so the card is DEMOTED (moved under the list) rather than
// deleted. Delete it in the same change that lands CheckView.
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
        NavigationStack {
            List {
                Section { heroBlock }
                if tunnel.state.isConnected {
                    Section {
                        HealthCard(record: tunnel.connectedRecord,
                                   ipCheck: ipCheck, speed: speed,
                                   mode: currentMode, maskIPs: settings.maskIPs)
                            .olcCardRow()
                    }
                }
                connectionsSection
                diagnosticsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.bg)
            .refreshable { await refreshSubscriptions() }
            .onChange(of: store.connections, initial: true) { _, _ in recompute() }
            .onChange(of: store.subscriptionMeta) { _, _ in recompute() }
            .onChange(of: tunnel.state) { old, new in stateChanged(from: old, to: new) }
            // #457 was: `.navigationTitle("OlcRTC")` — 34 pt of the most valuable
            // space spent on a word carrying no information.
            .navigationTitle(L10n.tabConnections.localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .add } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L10n.newConnectionTitle.localized())
                }
            }
            .sheet(item: $activeSheet) { sheetContent($0) }
        }
        // #456: an in-flight native probe can't be interrupted, but leaving the tab
        // stops the coordinator from starting further ones.
        .onDisappear { health.cancelAll() }
    }

    // MARK: 1. Hero

    private var heroBlock: some View {
        ConnectHero(state: tunnel.state,
                    subject: heroSubject,
                    health: heroSubject.map { health.display(for: $0.id) } ?? HealthDisplay.never,
                    mode: tunnel.state.isConnected ? tunnel.activeMode : settings.tunnelMode,
                    socksPort: tunnel.boundPort ?? settings.socksPort,
                    secretsLocked: store.secretsLocked,
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

    // MARK: 2. The connection list

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
            if store.hasSubscriptions {
                Section { pullToRefreshHint }
            }
            ForEach(groups, id: \.group) { group in
                Section {
                    ForEach(group.items) { conn in row(conn) }
                } header: {
                    groupHeader(group.group, items: group.items)
                } footer: {
                    groupFooter(group.group)
                }
            }
        }
    }

    private func row(_ conn: ConnectionRecord) -> some View {
        ConnectionRowView(record: conn,
                          display: health.display(for: conn.id),
                          isLive: tunnel.connectedRecord?.id == conn.id,
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

    /// #458: the row's verdict block is a real button now, so a tap on it gets
    /// the same immediate acknowledgement a tap on the row does. `tap()` (not
    /// `impact()`) — checking is a light action, connecting is a committed one.
    private func verify(_ conn: ConnectionRecord) {
        Haptics.tap()
        Task { await health.verify(conn, using: tunnel, force: true) }
    }

    private func remove(_ conn: ConnectionRecord) {
        if let i = store.connections.firstIndex(where: { $0.id == conn.id }) {
            store.remove(at: IndexSet([i]))
        }
    }

    // MARK: Section chrome

    /// #457 was: every group drew its name, including the default one — whose
    /// label is "Connections", identical to the tab it sits in, costing a full row
    /// to say nothing. The default group's header now carries only what it can
    /// prove: how many of its nodes are known to be failing, and the check control.
    @ViewBuilder
    private func groupHeader(_ group: String, items: [ConnectionRecord]) -> some View {
        HStack(spacing: 8) {
            if group != ConnectionRecord.defaultGroupName {
                Text(ConnectionRecord.displayGroupName(group))
            }
            failingBadge(items)
            Spacer()
            groupHealthControl(items)
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

    /// #456: "Check all" for one group. The coordinator probes strictly
    /// sequentially and never probes the room the live tunnel holds; it returns at
    /// once, and the spinner tracks its own in-flight set.
    @ViewBuilder
    private func groupHealthControl(_ items: [ConnectionRecord]) -> some View {
        if items.contains(where: { health.isChecking($0.id) }) {
            ProgressView().controlSize(.mini)
        } else {
            Button(L10n.healthVerifyAllAction.localized(), systemImage: "checkmark.shield") {
                health.verifyAll(items, using: tunnel)
            }
            .font(.caption2)
            .buttonStyle(.borderless)
            .textCase(nil)
        }
    }

    @ViewBuilder
    private func groupFooter(_ group: String) -> some View {
        if let info = subInfoByGroup[group] {
            SubscriptionMetaFooter(source: info.source, meta: info.meta)
        }
    }

    /// #411: pulling the list down force-refreshes every subscription source.
    private var pullToRefreshHint: some View {
        Label(L10n.pullToRefreshSubscriptions.localized(), systemImage: "arrow.down.circle")
            .font(.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
    }

    // MARK: 3. Diagnostics (demoted below the list — see the file header)

    private var diagnosticsSection: some View {
        Section {
            ConnectDiagnosticsCard(ipCheck: ipCheck, speed: speed,
                                   mode: currentMode, maskIPs: settings.maskIPs,
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
    private func rowMenuItems(_ conn: ConnectionRecord) -> [OlcMenuItem] {
        var items: [OlcMenuItem] = []
        items.append(.action(L10n.healthActionVerify.localized(), systemImage: "checkmark.shield") {
            verify(conn)
        })
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

// MARK: - ConnectDiagnosticsCard (#258, extracted #457)
//
// #457: the three manual probes, in one card, DEMOTED below the connection list.
// They are the only entry points to `IPChecker.checkAll`, `SpeedTest.run` and the
// #328 carrier-endpoint exclusions; the plan re-parents all three into a pushed
// "Check & why" screen, and this card is deleted in the change that lands it.

private struct ConnectDiagnosticsCard: View {
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    let mode: RouteMode
    let maskIPs: Bool
    let carrierParams: OlcrtcConnection?
    let onSpeedTest: () -> Void
    let onCarrierEndpoints: (OlcrtcConnection) -> Void

    /// #264: when the IP check last finished.
    @State private var ipCheckTime: Date?

    var body: some View {
        OlcCard(padding: 0) {
            VStack(spacing: 0) {
                ipRow
                Divider().overlay(Theme.Palette.separator)
                speedRow
                Divider().overlay(Theme.Palette.separator)
                carrierRow
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
        }
    }

    private var ipRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.ipCheckTitle.localized())
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                ConnectIPStatus(ipCheck: ipCheck, maskIPs: maskIPs)
                if let t = ipCheckTime, !ipCheck.isChecking {
                    Label(t.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            OlcButton(L10n.ipCheckRun.localized(), role: .secondary, isBusy: ipCheck.isChecking) {
                Task { await ipCheck.checkAll(via: mode); ipCheckTime = Date() }
            }
        }
        .padding(.vertical, 12)
    }

    private var speedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                OlcMetric(label: L10n.speedLabelPing.localized(),
                          value: value(speed.lastResult?.pingMs, L10n.speedPingValue_fmt.localized()),
                          unit: L10n.speedUnitMs.localized(), unitInLabel: true)
                OlcMetric(label: L10n.speedLabelDL.localized(),
                          value: value(speed.lastResult?.downloadMbps, L10n.speedRateValue_fmt.localized()),
                          unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
                OlcMetric(label: L10n.speedLabelUL.localized(),
                          value: value(speed.lastResult?.uploadMbps, L10n.speedRateValue_fmt.localized()),
                          unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
            }
            Spacer(minLength: 8)
            OlcButton(L10n.speedTestRun.localized(), role: .secondary,
                      isBusy: speed.isTesting, action: onSpeedTest)
        }
        .padding(.vertical, 12)
    }

    private var carrierRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.carrierEndpointsTitle.localized())
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(carrierParams != nil
                     ? L10n.carrierEndpointsReadyHint.localized()
                     : L10n.carrierEndpointsConnectHint.localized())
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 8)
            OlcButton(L10n.carrierEndpointsCheckAction.localized(), role: .secondary) {
                if let params = carrierParams { onCarrierEndpoints(params) }
            }
            .disabled(carrierParams == nil)
        }
        .padding(.vertical, 12)
    }

    private func value(_ v: Double?, _ format: String) -> String {
        if speed.isTesting { return "…" }
        guard let v else { return "—" }
        return String(format: format, v)
    }
}

// MARK: - ConnectIPStatus (extracted #457)
//
// The IP-check result block: collapsed agreement line, the DNS-leak warning, or
// the per-source list. Its own struct so the diagnostics card's body stays small.

private struct ConnectIPStatus: View {
    @ObservedObject var ipCheck: IPChecker
    let maskIPs: Bool

    var body: some View {
        if ipCheck.isChecking {
            Text(L10n.ipChecking.localized())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Palette.textSecondary)
        } else if !hasResults {
            Text(L10n.ipNotChecked.localized())
                .font(.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        } else if collapsed, let ip = summaryIP {
            // #337: mask for display only — the value behind it stays real.
            Text(L10n.ipSourcesAgree_fmt.formatted(IPMask.display(ip, masked: maskIPs),
                                                   ipCheck.results.filter { $0.ip != nil }.count))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Palette.green)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if allDone, Set(ipCheck.results.compactMap { $0.ip }).count > 1 {
                    leakWarning
                }
                ForEach(ipCheck.results) { r in sourceRow(r) }
            }
        }
    }

    private var leakWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.red)
            Text(L10n.ipDnsLeak.localized())
                .font(.caption)
                .foregroundStyle(Theme.Palette.red)
        }
    }

    @ViewBuilder
    private func sourceRow(_ r: IPResult) -> some View {
        HStack {
            Text(r.label)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            if let ip = r.ip {
                Text(IPMask.display(ip, masked: maskIPs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textPrimary)
            } else if let err = r.error {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("—").foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var collapsed: Bool {
        let ips = ipCheck.results.compactMap { $0.ip }
        guard ips.count >= 2 else { return false }
        return Set(ips).count == 1
    }
    private var summaryIP: String? { ipCheck.results.compactMap { $0.ip }.first }
    private var hasResults: Bool { ipCheck.results.contains { $0.ip != nil || $0.error != nil } }
    private var allDone: Bool {
        !ipCheck.results.isEmpty && ipCheck.results.allSatisfy { $0.ip != nil || $0.error != nil }
    }
}

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
