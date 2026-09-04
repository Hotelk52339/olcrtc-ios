import SwiftUI

// MARK: - DiagnosticsCard (#454 / #258, merged #459)
//
// FILE NOTE (#459): this file is still called HealthCard.swift because renaming
// it needs an `xcodegen generate` pass, which cannot run on this machine. Its
// contents are the Diagnostics card; rename the file to DiagnosticsCard.swift on
// the next regeneration (`sources: - path: App` is a directory glob, so no
// project.yml edit is involved).
//
// #459: ONE card, because there were two and they said the same things.
//
// #459 was: `HealthCard` ("Connection health": protocol / exit / latency /
// throughput, only while a session was up) sat directly above `Diagnostics` (IP
// check / speed test / carrier endpoints) — and the two overlapped on the two
// facts the user actually reads. Latency was measured twice: a live 8 s probe in
// the health card and a `SpeedResult.pingMs` figure in the speed row, which
// carried no timestamp at all and could be inherited from a previous session or
// a DIRECT-mode run. Two cards, two ping numbers, one screen. The owner's
// verdict — "maybe KEEP Diagnostics and REMOVE Health, everything should be
// logical" — is exactly right, so Diagnostics is the name that survives and the
// health card's four facts move in as its first block.
//
// The card is two blocks:
//   A. "This session" — what is true about the tunnel that is up RIGHT NOW.
//      Mounted only while connected. Protocol (the ONE place this screen states
//      the carrier/transport), exit, live response time.
//   B. "Checks" — the two things the user can RUN: IP check and speed test.
//      Always present, because they are the only entry points to
//      `IPChecker.checkAll` and `SpeedTest.run`. #461 was: a third row for the
//      #328 carrier exclusions, now an item in the connected record's menu.
//
// #461: block A's third fact is called "Latency" again, because there is only
// one latency in the app now. #460 had renamed it "Response time" and added a
// paragraph explaining why it read ~8x the per-connection chips: this card timed
// a whole request INCLUDING opening the connection, the chips timed a round-trip
// on a connection already open. `LatencyProbe` (SpeedTest.swift) collapses the
// two methods into one, and `publishLiveLatency` makes the live node's chip
// print this card's own sample. The explanation is deleted with the discrepancy
// it explained. Full reasoning on `responseRow`.
//
// #460: every fact in block A now also says WHERE IT COMES FROM, not just when
// it was taken. Dating a claim answers "is this still true?"; sourcing it
// answers "who says so?" — the owner asked the second question out loud about
// the exit country, and it applies to every number here. Block B's third row
// gained the same treatment for a different reason (finding 23): it named a
// mechanism nobody outside the project recognises, so it now names the
// SITUATION it applies to instead.
//
// NOTHING IS DRAWN THAT CANNOT BE DATED (#457, kept verbatim). Every value
// carries the age of the measurement behind it, in the same `HealthAge`
// vocabulary the row verdicts use, so a number from four minutes ago can never
// read as "now".
//
// #457's "measuring… forever" fix is kept too: `SpeedTest.quickPing` returns nil
// on ANY error, so the state machine is explicit — `probing` (a measurement is
// in flight now) vs `latencyAt` (when one last completed). "Checking…" is
// reachable only while `probing` is true AND nothing has completed yet.
//
// Throughput stays deliberately hard to claim: `SpeedResult` carries no
// timestamp, so a `lastResult` inherited from an earlier session — or from a
// DIRECT-mode test — is not evidence about the tunnel that is up now. The speed
// row dates only a run this view watched finish.
//
// #459 was also: `HealthCard.refreshButton` (an `arrow.clockwise` glyph). The
// list now pulls to refresh, screen-wide; a per-card refresh glyph beside a
// screen-wide gesture is two controls for one job.
//
// It stays SEPARATE view structs (not inlined into ConnectionsView.body) so that
// file's already-large body stays under the SwiftUI type-checker budget, and so
// each `body` here is under ~25 lines.

struct DiagnosticsCard: View {
    /// The live record (`TunnelManager.connectedRecord`) — the subject of block A.
    let record: ConnectionRecord?
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    /// Route for the live probes — `.tunnel` while connected in proxy mode.
    let mode: RouteMode
    /// #337: screenshot-safe IP masking (mirrors the IP-check rows).
    let maskIPs: Bool
    /// Block A exists only while a session is up; block B always does.
    let isConnected: Bool
    // #461 was: also `carrierParams: OlcrtcConnection?` and
    // `onCarrierEndpoints: (OlcrtcConnection) -> Void`, for the tools block's
    // third row. That row is an action on a CONNECTION and moved into the
    // connected record's overflow menu (`ConnectionsView.carrierEndpointsItem`);
    // dropping the inputs is what makes it a move rather than a duplication.
    let onSpeedTest: () -> Void

    var body: some View {
        OlcCard(padding: 0) {
            VStack(spacing: 0) {
                sessionBlock
                DiagnosticsTools(ipCheck: ipCheck, speed: speed, mode: mode,
                                 maskIPs: maskIPs, onSpeedTest: onSpeedTest)
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
        }
    }

    /// #459: absent — not empty, not greyed — when nothing is connected. There is
    /// no session to describe, so the card is just the tools and ~140 pt shorter.
    @ViewBuilder
    private var sessionBlock: some View {
        if isConnected {
            DiagnosticsFacts(record: record, ipCheck: ipCheck, speed: speed,
                             mode: mode, maskIPs: maskIPs)
            Divider().overlay(Theme.Palette.separator)
        }
    }
}

// MARK: - DiagnosticsFacts — block A, "This session" (#454, moved here #459)
//
// The former HealthCard, minus its own title and its refresh glyph. Its dating
// machinery moves verbatim: the 8 s probe loop (#461: its reading IS the app's
// one latency again — see `responseRow`), `latencyAt` / `probing`, and
// `exitAt` (tracked here because `ExitGeo` carries no timestamp and the refresh
// is also fired from ConnectionsView on the connect transition).

private struct DiagnosticsFacts: View {
    let record: ConnectionRecord?
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    let mode: RouteMode
    let maskIPs: Bool

    /// The live latency, refreshed by the loop below. nil = no measurement.
    /// #461 was documented here as "NOT a latency — one whole request including
    /// connection setup". It excludes connection setup now (`LatencyProbe`), so
    /// it is the same quantity the node chips carry; see `responseRow`.
    @State private var latencyMs: Double?
    /// #457: when the last latency measurement COMPLETED (success or failure).
    /// nil ⇒ none has completed for this record yet.
    @State private var latencyAt: Date?
    /// #457: a measurement is in flight right now. The ONLY thing that licenses
    /// the word "Checking…".
    @State private var probing = false
    /// #457: when `ipCheck.exitGeo` last changed — the exit line's age.
    @State private var exitAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiagnosticsSubheader(title: L10n.diagSessionHeader.localized())
            protocolRow
            exitRow
            responseRow    // #460 was: latencyRow; #461: called "Latency" again
        }
        // Live response time: measure now, then every ~8 s. Keyed on the live record so
        // a failover (record swap, #453) restarts the loop against the new
        // protocol; the conditional mount cancels it on disconnect. The 8 s tick
        // is also what re-renders every age in this block.
        .task(id: record?.id) { await runLatencyLoop() }
        // #457: `ExitGeo` is Equatable, so this catches BOTH refresh paths — the
        // pull gesture and ConnectionsView's connect-transition fetch. Deliberately
        // NOT `initial: true`: a value already in the store was measured at some
        // unknown earlier moment, and stamping it on mount would date it "now".
        // #470 was: `.onChange(of: ipCheck.exitGeo)` stamping Date() here — a
        // refresh that returned the same geo never fired it, so a fresh reading
        // kept its old age. The checker dates each measurement (`exitGeoAt`).
        .onChange(of: ipCheck.exitGeoAt) { _, new in
            exitAt = new
        }
    }

    // MARK: The latency loop

    private func runLatencyLoop() async {
        // #457: a new live record has been measured zero times — clear the value
        // AND its stamp, so the previous node's number is never shown as this
        // one's after a #453 failover swap.
        latencyMs = nil
        latencyAt = nil
        // #461: captured once. The task is keyed on `record?.id`, so a failover
        // swap restarts the loop and this can never publish under the wrong node.
        let liveID = record?.id
        while !Task.isCancelled {
            // boc #461
            // #461: stand aside while a USER speed test is running. `SpeedTest
            // .run` reserves 180 s of keep-alive suppression up front precisely
            // because extra connections mid-test add congestion; this loop was
            // the one prober that ignored that. Probing a saturated tunnel
            // measures the transfer, not the route — and now that this figure
            // and the per-node chips are the same measurement, that bad sample
            // would be published as the node's health. The previous reading
            // keeps its stamp and `DiagnosticsAge` goes on ageing it, so the
            // pause is visible and honest rather than silent.
            // `MainActor.run` rather than a bare `await speed.isTesting`: this
            // closure's isolation is whatever `.task` gives it, and an explicit
            // hop reads the same either way. `SpeedTest` is `@MainActor`, hence
            // implicitly Sendable, so nothing is captured unsafely.
            if await MainActor.run(body: { speed.isTesting }) {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            // eoc #461
            probing = true
            // boc #470: fail-closed, the way `verifyTunnel` is (#445). URLSession
            // silently BYPASSES a loopback proxy that REFUSES the connection and
            // completes the HEAD direct, so a sample taken after the Go listener
            // died still succeeded — and was published below as `.working`
            // (green "Verified just now · N ms") while `LatencyProbe` refreshed
            // the keep-alive activity marker on what was direct traffic. The raw
            // SOCKS greeting cannot be bypassed: no answer is a failed sample,
            // never a direct one. `.direct` mode has no listener to ask.
            var listens = true
            if mode == .tunnel {
                listens = await TunnelManager.socksListenerAnswers(port: TunnelManager.activeSocksPort)
            }
            let ms: Double?
            if listens { ms = await speed.quickPing(via: mode) } else { ms = nil }
            // #470 was: let ms = await speed.quickPing(via: mode)
            // eoc #470
            if Task.isCancelled { return }
            latencyMs = ms
            latencyAt = Date()
            probing = false
            await publishLiveLatency(ms, for: liveID)
            try? await Task.sleep(for: .seconds(8))
        }
    }

    // boc #461
    /// #461: THE LIVE NODE'S CHIP PRINTS THIS CARD'S OWN SAMPLE — the half of
    /// the owner's complaint 2 that an explanation could never fix.
    ///
    /// `HealthCoordinator.noteLiveVerified` is called from two places in
    /// `TunnelManager` (the verify-tunnel success and every keep-alive tick)
    /// with `rttMs: nil`, so the live node's chip carried an rtt from some
    /// EARLIER probe — a different tunnel, a different moment — or none at all.
    /// Publishing this loop's reading means the Diagnostics row and every
    /// `OlcHealthChip` for the connected node render THE SAME INTEGER, taken by
    /// THE SAME sample, at most 8 s apart in age. Side benefit: `.verified`
    /// stops expiring mid-session, so the hero's aurora verdict ring no longer
    /// goes out while the tunnel is plainly working.
    ///
    /// `.tunnel` ONLY. In VPN mode the whole device is routed, `mode` is
    /// `.direct`, and the reading is not attributable to this node's own SOCKS
    /// listener — `HealthCoordinator` refuses to probe under a live system VPN
    /// for the same reason. A failed sample publishes nothing: one missed HEAD
    /// is not evidence that a node is broken, and the keep-alive / wedge
    /// machinery owns that judgement.
    ///
    /// DESIGN NOTE: the spec asked for a non-persisting sibling
    /// (`HealthCoordinator.noteLiveLatency`) so an 8 s cadence would not write
    /// UserDefaults ~450x an hour. App/Services/HealthCoordinator.swift is
    /// outside this change's partition, so this calls the existing writer, whose
    /// stored shape (`.working`, `source: "live"`) is identical. The cost is
    /// bounded in practice — the loop only runs while a session is UP and this
    /// card is ON SCREEN — but swap the call the moment that sibling exists.
    private func publishLiveLatency(_ ms: Double?, for recordID: UUID?) async {
        guard let ms, let recordID, mode == .tunnel else { return }
        let rtt = Int(ms.rounded())
        await MainActor.run {
            HealthCoordinator.shared.noteLiveVerified(recordID: recordID, rttMs: rtt)
        }
    }
    // eoc #461

    // MARK: Rows

    /// #461 (audit): NO LONGER THE ONE PLACE. #459's claim here — "the ONE place
    /// this screen states the live node's carrier/transport, so this is not a
    /// repeat of anything" — held only while the hero printed neither. #461 made
    /// the carrier the hero's headline and the transport the line under it
    /// (`ConnectHero.identityBlock`), so this row now says "Yandex Telemost ·
    /// DataChannel" about the same connection the top of the same screen already
    /// names. Deleting the row is the fix; it is left standing here because that
    /// is a structural change, and this comment is the record that it is owed.
    @ViewBuilder
    private var protocolRow: some View {
        DiagnosticsRow(label: L10n.healthProtocolLabel.localized()) {
            if case .olcrtc(let p)? = record?.details {
                Text("\(CarrierTransportMatrix.carrierLabel(p.carrier)) · \(CarrierTransportMatrix.transportLabel(p.transport))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            } else {
                Text("—").foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    // boc #460
    /// #460 (findings 3 / 22): the provenance moves OUT of the value column and
    /// becomes the row's note. #459 answered the owner's "the country and the IP,
    /// where do they even come from?" with a right-aligned fragment ("Asked
    /// ipinfo.io through the tunnel") wrapped into the narrow trailing stack; the
    /// sentence now runs the width of the card and says what was actually
    /// measured — the tunnel's own exit IP — and that the city and country are
    /// derived from that one lookup rather than known independently.
    ///
    /// `IPChecker.fetchExitGeo` GETs https://ipinfo.io/json through a
    /// `SOCKSSession.make(mode:)` session, so the sentence is true and specific.
    /// #460 was: the hint lived inside the trailing VStack, `.multilineTextAlignment(.trailing)`.
    @ViewBuilder
    private var exitRow: some View {
        DiagnosticsRow(label: L10n.healthExitLabel.localized(),
                       note: L10n.diagExitNote.localized()) {
            VStack(alignment: .trailing, spacing: 2) {
                exitValue
                // #457: the exit's age. A country printed with no date is a claim
                // about now made from evidence about then.
                DiagnosticsAge(at: exitAt)
            }
        }
    }
    // eoc #460

    @ViewBuilder
    private var exitValue: some View {
        if let geo = ipCheck.exitGeo, geo != IPChecker.ExitGeo() {
            HStack(spacing: 4) {
                if let cc = geo.country, let flag = CountryFlag.emoji(iso2: cc) {
                    Text(flag)
                }
                Text(placeString(geo))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            if let ip = geo.ip {
                Text(IPMask.display(ip, masked: maskIPs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        } else {
            Text(L10n.healthLocationUnknown.localized())
                .font(.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    // boc #461
    /// #461: THE TWO CONTRADICTORY LATENCIES, closed at the source.
    ///
    /// #460 was: on one screen, at one moment, this row read `LATENCY 1109 ms`
    /// in RED while a connection row for the same server read `133 ms`. Both
    /// were labelled "latency" and neither was wrong — they were different
    /// measurements. #460's answer was to rename this one "Response time", drop
    /// the threshold tint, and add `diagResponseNote`: a ~250-character
    /// paragraph reconciling the two numbers. The owner's answer to that: "the
    /// diagnostics ping is 947 ms again, while somewhere else it is different."
    /// An explanation is not a fix, and a paragraph explaining why two numbers
    /// disagree is the app admitting it prints two numbers.
    ///
    /// #461 makes them ONE. `SpeedTest.quickPing` now delegates to
    /// `LatencyProbe.measure(via:)`, which reproduces the Go core's own method
    /// — a warm-up request that pays the SOCKS connect and the TLS handshake,
    /// then samples over the SAME kept-alive session, best returned — so this
    /// figure and the chips' figure are comparable BY CONSTRUCTION. For the
    /// live node they are not merely comparable: `publishLiveLatency` above
    /// makes them the same integer.
    ///
    /// So the row is called what it measures again ("Latency"), and the
    /// paragraph is gone: there is nothing left to reconcile.
    ///
    /// NO THRESHOLD TINT, still. The honesty layer's chip beside this number
    /// already carries the verdict colour, and two colour systems on one number
    /// is exactly how #460 went wrong. Two tones — measured = `textPrimary`,
    /// unmeasured = `textTertiary` — and never red.
    ///
    /// `latencyMs` / `latencyAt` / `probing` keep their names: they were always
    /// accurate, and #460 renamed the LABEL away from them. This puts it back.
    @ViewBuilder
    private var responseRow: some View {
        DiagnosticsRow(label: L10n.diagResponseLabel.localized()) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(responseValue)
                    .font(Theme.Typography.metricValue)
                    .foregroundStyle(responseTone)
                    .lineLimit(1)
                DiagnosticsAge(at: latencyAt)
            }
        }
    }
    // eoc #461

    // MARK: Values

    /// #457 was: nil ⇒ "measuring…" (forever, over a dead data path) and later
    /// nil ⇒ "not measured" with no date. The word for work-in-progress is now
    /// licensed by `probing` alone, and the verdict carries its stamp below.
    private var responseValue: String {
        if let ms = latencyMs { return L10n.healthLatencyMs_fmt.formatted(Int(ms.rounded())) }
        if probing && latencyAt == nil { return L10n.healthChecking.localized() }
        // #470: a probe that RAN and got nothing back is a data-path fact, not an
        // absence of measurement — "not measured · checked just now" hid a wedged
        // tunnel (in=0 out=0) under a no-measurement word while the hero above
        // still read Connected. `latencyAt` is stamped on failure too.
        if latencyAt != nil { return L10n.healthLatencyNoResponse.localized() }
        return L10n.healthLatencyNotMeasured.localized()
    }

    /// #460/#461: two tones, and neither is an alarm — see `responseRow`. A measured
    /// figure reads as data; the absence of one reads as tertiary, which is what
    /// "we have no value here" looks like everywhere else in this card.
    /// #460 was: `latencyTone` — green under 150 ms, orange under 400, red above.
    private var responseTone: Color {
        latencyMs == nil ? Theme.Palette.textTertiary : Theme.Palette.textPrimary
    }

    /// "City, CC" from whatever geo fields are present ("location unknown" when
    /// neither is). The flag glyph is rendered separately, next to this.
    private func placeString(_ geo: IPChecker.ExitGeo) -> String {
        let place = [geo.city, geo.country].compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty ? L10n.healthLocationUnknown.localized() : place
    }
}

// MARK: - DiagnosticsTools — block B, "Checks" (#258, moved here #459)
//
// The manual probes — two of them since #461 moved the carrier-endpoints tool
// into the connected record's overflow menu. #459 was: they lived in `ConnectDiagnosticsCard`
// inside ConnectionsView.swift, under a card of their own, with a `PING ms`
// metric that measured the same thing block A measures — less often, and with no
// timestamp at all (`SpeedResult` carries none). The ping metric is deleted; DL
// and UL stay, and now say when they were taken.

private struct DiagnosticsTools: View {
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    let mode: RouteMode
    let maskIPs: Bool
    let onSpeedTest: () -> Void   // #461 was: also carrierParams / onCarrierEndpoints

    /// #264: when the IP check last finished.
    @State private var ipCheckTime: Date?
    /// #457/#459: when a speed test finished while this view was on screen.
    /// `SpeedResult` has no timestamp, so nothing else may be dated.
    @State private var throughputAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiagnosticsSubheader(title: L10n.diagToolsHeader.localized())
            ipRow
            Divider().overlay(Theme.Palette.separator)
            speedRow   // #461 was: + a Divider and `carrierRow` below it
        }
        // #457: `SpeedResult` is not Equatable and carries no date; the falling
        // edge of `isTesting` is the moment a run we can attribute completed.
        .onChange(of: speed.isTesting) { was, now in if was && !now { throughputAt = Date() } }
    }

    private var ipRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.ipCheckTitle.localized())
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                // #459: the second half of the owner's "where do these numbers
                // come from?" — name the method, and how many services answer.
                Text(L10n.diagIPSourceHint_fmt.formatted(Self.ipSourceCount))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ConnectIPStatus(ipCheck: ipCheck, maskIPs: maskIPs, mode: mode)   // #470: + mode
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
        .padding(.vertical, Theme.Metrics.s3)
    }

    // boc #459
    // #459 was: a third `OlcMetric` here — `PING ms`, from `speed.lastResult
    // .pingMs`. Block A measures the same route every 8 s and stamps the result;
    // this one was taken once per speed test and could not be dated at all.
    private var speedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 16) {
                    // #470 was: speed.lastResult?.downloadMbps / uploadMbps (any route)
                    OlcMetric(label: L10n.speedLabelDL.localized(),
                              value: value(routeResult?.downloadMbps, L10n.speedRateValue_fmt.localized()),
                              unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
                    OlcMetric(label: L10n.speedLabelUL.localized(),
                              value: value(routeResult?.uploadMbps, L10n.speedRateValue_fmt.localized()),
                              unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
                }
                // #459: the throughput figures keep the card's dating rule — a
                // run this view watched finish, on this route, or no stamp.
                if throughputAt != nil, routeResult != nil {   // #470 was: speed.lastResult?.mode == mode
                    DiagnosticsAge(at: throughputAt)
                }
            }
            Spacer(minLength: 8)
            OlcButton(L10n.speedTestRun.localized(), role: .secondary,
                      isBusy: speed.isTesting, action: onSpeedTest)
        }
        .padding(.vertical, Theme.Metrics.s3)
    }
    // eoc #459

    // boc #461
    // #461 was: `carrierRow` — the "Using another proxy app?" tool. A title, a
    // two-line audience-selecting hint (`carrierEndpointsRowHint` /
    // `carrierEndpointsRowConnectHint`) and a "Show" button, ~90 pt, mounted
    // permanently on the app's main screen and disabled whenever nothing was
    // connected. Every one of the four clients read for this change pushes its
    // technical tools below the fold or behind a disclosure; this one goes one
    // better and becomes an item in the connected record's overflow menu, which
    // is on screen at all times (`ConnectionsView.carrierEndpointsItem`).
    // `carrierEndpointsRowTitle` survives as that item's title; the two hints
    // and `carrierEndpointsShowAction` lose their last use.
    // eoc #461

    // boc #470
    /// The last result ONLY when it was measured on the route this card is
    /// about. #470 was: the DL/UL figures printed `speed.lastResult` whatever
    /// its `mode`, and only the AGE line was gated on it — so a direct-mode run
    /// showed as bare numbers inside the tunnel's Diagnostics, undated and
    /// unattributed, the exact claim the file header forbids. A result from the
    /// other route reads "—", like no result. (A same-route result from an
    /// earlier session still shows undated: `SpeedResult` carries no timestamp.)
    private var routeResult: SpeedResult? {
        speed.lastResult.flatMap { $0.mode == mode ? $0 : nil }
    }
    // eoc #470

    private func value(_ v: Double?, _ format: String) -> String {
        if speed.isTesting { return "…" }
        guard let v else { return "—" }
        return String(format: format, v)
    }

    /// #459: how many services the IP check will actually query — the same
    /// resolution `IPChecker.sources` performs (its own copy is private), so the
    /// sentence never promises a count the check will not honour.
    private static var ipSourceCount: Int {
        let enabled = SettingsStore.shared.enabledIPSources
        let chosen = AppConstants.ipCheckServices.filter { enabled.contains($0.label) }
        if chosen.isEmpty {
            return AppConstants.ipCheckServices.filter {
                AppConstants.defaultEnabledIPCheckLabels.contains($0.label)
            }.count
        }
        return chosen.count
    }
}

// MARK: - Shared pieces

/// #459: one block sub-header ("This session" / "Checks"), in the design
/// system's section-header treatment so the two blocks read as siblings.
private struct DiagnosticsSubheader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Metrics.s3)
    }
}

/// Label left, value right — the fact rows of block A. The explicit init (rather
/// than an `@ViewBuilder` stored property) matches `OlcCard` / `OlcSectionHeader`
/// in the design system.
///
/// #460: an optional `note` — one full-width caption under the label/value line,
/// inside the same vertical padding. It exists because the two rows that most
/// needed to say WHERE THEIR NUMBER COMES FROM (exit, response time) could only
/// squeeze that into the right-hand value column, where a sentence renders as a
/// ragged three-word-wide stack. A provenance line is prose: it gets the row.
private struct DiagnosticsRow<Trailing: View>: View {
    private let label: String
    private let note: String?
    private let trailing: () -> Trailing

    // #460 was: init(label:trailing:)
    init(label: String, note: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.note = note
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: 12)
                trailing()
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, Theme.Metrics.s3)
    }
}

/// #457/#459: the age of ONE measurement, in the same `HealthAge` vocabulary the
/// row verdicts use. No stamp means the fact was never measured — say so; never
/// print a value with a blank where its date belongs.
///
/// #459: `HealthAge.phrase` (not the old `HealthAge.label`) — the phrase carries
/// its own "ago"/«назад», which is what stops `healthCheckedAgo_fmt` reading
/// "checked just now ago".
private struct DiagnosticsAge: View {
    let at: Date?

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineLimit(1)
    }

    private var text: String {
        guard let at else { return L10n.healthNeverMeasured.localized() }
        return L10n.healthCheckedAgo_fmt.formatted(HealthAge.phrase(Date().timeIntervalSince(at)))
    }
}

// MARK: - ConnectIPStatus (extracted #457, moved here #459)
//
// The IP-check result block: collapsed agreement line, the DNS-leak warning, or
// the per-source list. Its own struct so the tools block's body stays small.

private struct ConnectIPStatus: View {
    @ObservedObject var ipCheck: IPChecker
    let maskIPs: Bool
    /// #470: the route the card is about NOW — a result from the other route is
    /// attributed, and never green.
    let mode: RouteMode

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
            // #470: say WHICH ROUTE answered, and be green only while that is the
            // route this card is about. `IPResult.mode` was stored and never
            // rendered, and nothing clears results across connect / disconnect,
            // so a real-IP check made before connecting sat green under a
            // Connected hero (and a tunnel IP stayed green after disconnecting),
            // reading as the current answer.
            let agree = L10n.ipSourcesAgree_fmt.formatted(IPMask.display(ip, masked: maskIPs),
                                                          ipCheck.results.filter { $0.ip != nil }.count)
            Text("\(agree) · \(resultRoute.label)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(resultIsCurrentRoute ? Theme.Palette.green : Theme.Palette.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if allDone, Set(ipCheck.results.compactMap { $0.ip }).count > 1 {
                    leakWarning
                }
                ForEach(ipCheck.results) { r in sourceRow(r) }
                routeCaption   // #470
            }
        }
    }

    // boc #470
    /// The route the listed answers came from (every row of one check shares it).
    private var resultRoute: RouteMode { ipCheck.results.first?.mode ?? mode }
    private var resultIsCurrentRoute: Bool { resultRoute == mode }

    private var routeCaption: some View {
        Text(resultRoute.label)
            .font(.caption2)
            .foregroundStyle(Theme.Palette.textTertiary)
    }
    // eoc #470

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
