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
//   B. "Checks" — the three things the user can RUN: IP check, speed test,
//      carrier endpoints. Always present, because they are the only entry points
//      to `IPChecker.checkAll`, `SpeedTest.run` and the #328 exclusions.
//
// #460: block A's third fact is no longer called "latency", is no longer tinted
// red, and now states where its number comes from — because the screen was
// printing TWO numbers under that one word, taken by two different methods, and
// painting the larger, less comparable one in the alarm colour. The full
// reasoning is on `responseRow`; the short version is that this card times a
// whole request INCLUDING opening the connection, while the per-connection
// checks time a round-trip on a connection that is already open.
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
    let carrierParams: OlcrtcConnection?
    let onSpeedTest: () -> Void
    let onCarrierEndpoints: (OlcrtcConnection) -> Void

    var body: some View {
        OlcCard(padding: 0) {
            VStack(spacing: 0) {
                sessionBlock
                DiagnosticsTools(ipCheck: ipCheck, speed: speed, mode: mode,
                                 maskIPs: maskIPs, carrierParams: carrierParams,
                                 onSpeedTest: onSpeedTest,
                                 onCarrierEndpoints: onCarrierEndpoints)
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
// machinery moves verbatim: the 8 s probe loop (#460: its reading is a
// RESPONSE TIME, not a latency — see `responseRow`), `latencyAt` / `probing`, and
// `exitAt` (tracked here because `ExitGeo` carries no timestamp and the refresh
// is also fired from ConnectionsView on the connect transition).

private struct DiagnosticsFacts: View {
    let record: ConnectionRecord?
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    let mode: RouteMode
    let maskIPs: Bool

    /// The live response time, refreshed by the ping loop below. nil = no
    /// measurement. #460: NOT a latency — one whole request including connection
    /// setup; see `responseRow` for why that distinction is load-bearing.
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
            responseRow    // #460 was: latencyRow
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
        .onChange(of: ipCheck.exitGeo) { _, new in
            exitAt = new == nil ? nil : Date()
        }
    }

    // MARK: The latency loop

    private func runLatencyLoop() async {
        // #457: a new live record has been measured zero times — clear the value
        // AND its stamp, so the previous node's number is never shown as this
        // one's after a #453 failover swap.
        latencyMs = nil
        latencyAt = nil
        while !Task.isCancelled {
            probing = true
            let ms = await speed.quickPing(via: mode)
            if Task.isCancelled { return }
            latencyMs = ms
            latencyAt = Date()
            probing = false
            try? await Task.sleep(for: .seconds(8))
        }
    }

    // MARK: Rows

    /// #459: the ONE place this screen states the live node's carrier/transport.
    /// The hero dropped its mono `olcrtc · … · …` line and the rows never say it
    /// for a node that is not in the list, so this is not a repeat of anything.
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

    // boc #460
    /// #460 (findings 2 and 15): THE TWO CONTRADICTORY LATENCIES.
    ///
    /// On one screen, at one moment, this row read `LATENCY 1109 ms` in RED
    /// while a connection row for the same server read `133 ms`. Both were
    /// labelled "latency". They are not the same measurement and never could be:
    ///
    ///   • THIS row — `SpeedTest.quickPing(via:)` every 8 s: ONE HEAD request to
    ///     the speed-test provider's ping endpoint on a BRAND-NEW `URLSession`,
    ///     so every sample pays a fresh SOCKS connect and a fresh TLS handshake
    ///     through the live carrier tunnel. One sample, no warm-up, no averaging.
    ///     Most of the number is connection setup.
    ///   • THE ROW CHIPS — `NodeHealth.rttMs`, from the Go core's `Runtime.Ping`
    ///     (`mobile/ping.go`): a SEPARATE isolated probe tunnel, a warm-up GET,
    ///     then three GETs over one kept-alive connection, of which it returns
    ///     the BEST. Connection setup is excluded by construction.
    ///
    /// So this figure is several times the chips' figure BY DESIGN — and it was
    /// the one painted red, because it was tinted with ping thresholds
    /// (<150 green / <400 amber / else red) that were calibrated for a
    /// round-trip, not for a cold fetch. The app's most alarming number was its
    /// least comparable one.
    ///
    /// The fix keeps the measurement — it is the only continuously updating,
    /// user-meaningful live reading, and its success is what marks tunnel
    /// activity for the keep-alive loop — but stops it pretending to be latency:
    ///   1. it is named for what it times (a response, setup included);
    ///   2. the note says so, and says why the per-connection checks always read
    ///      lower, so the two numbers are reconciled where they are compared.
    ///      The note names the OTHER MEASUREMENT, not a place on the screen: the
    ///      live node is the hero's subject and ConnectionsView deliberately
    ///      keeps it out of the list, so "the connections below" would have
    ///      pointed away from the chip a reader is comparing against;
    ///   3. NO threshold tint. An uncalibrated number does not get to raise an
    ///      alarm; measured = primary, unmeasured = tertiary, never red.
    ///
    /// #460 was: `latencyRow` — `DiagnosticsRow(label: healthLatencyLabel)` with
    /// `latencyTone` (green/orange/red by ms) on the value.
    @ViewBuilder
    private var responseRow: some View {
        DiagnosticsRow(label: L10n.diagResponseLabel.localized(),
                       note: L10n.diagResponseNote.localized()) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(responseValue)
                    .font(Theme.Typography.metricValue)
                    .foregroundStyle(responseTone)
                    .lineLimit(1)
                DiagnosticsAge(at: latencyAt)
            }
        }
    }

    // MARK: Values

    /// #457 was: nil ⇒ "measuring…" (forever, over a dead data path) and later
    /// nil ⇒ "not measured" with no date. The word for work-in-progress is now
    /// licensed by `probing` alone, and the verdict carries its stamp below.
    private var responseValue: String {
        if let ms = latencyMs { return L10n.healthLatencyMs_fmt.formatted(Int(ms.rounded())) }
        if probing && latencyAt == nil { return L10n.healthChecking.localized() }
        return L10n.healthLatencyNotMeasured.localized()
    }

    /// #460: two tones, and neither is an alarm — see `responseRow`. A measured
    /// figure reads as data; the absence of one reads as tertiary, which is what
    /// "we have no value here" looks like everywhere else in this card.
    /// #460 was: `latencyTone` — green under 150 ms, orange under 400, red above.
    private var responseTone: Color {
        latencyMs == nil ? Theme.Palette.textTertiary : Theme.Palette.textPrimary
    }
    // eoc #460

    /// "City, CC" from whatever geo fields are present ("location unknown" when
    /// neither is). The flag glyph is rendered separately, next to this.
    private func placeString(_ geo: IPChecker.ExitGeo) -> String {
        let place = [geo.city, geo.country].compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty ? L10n.healthLocationUnknown.localized() : place
    }
}

// MARK: - DiagnosticsTools — block B, "Checks" (#258, moved here #459)
//
// The three manual probes. #459 was: they lived in `ConnectDiagnosticsCard`
// inside ConnectionsView.swift, under a card of their own, with a `PING ms`
// metric that measured the same thing block A measures — less often, and with no
// timestamp at all (`SpeedResult` carries none). The ping metric is deleted; DL
// and UL stay, and now say when they were taken.

private struct DiagnosticsTools: View {
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    let mode: RouteMode
    let maskIPs: Bool
    let carrierParams: OlcrtcConnection?
    let onSpeedTest: () -> Void
    let onCarrierEndpoints: (OlcrtcConnection) -> Void

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
            speedRow
            Divider().overlay(Theme.Palette.separator)
            carrierRow
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
                    OlcMetric(label: L10n.speedLabelDL.localized(),
                              value: value(speed.lastResult?.downloadMbps, L10n.speedRateValue_fmt.localized()),
                              unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
                    OlcMetric(label: L10n.speedLabelUL.localized(),
                              value: value(speed.lastResult?.uploadMbps, L10n.speedRateValue_fmt.localized()),
                              unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
                }
                // #459: the throughput figures keep the card's dating rule — a
                // run this view watched finish, on this route, or no stamp.
                if throughputAt != nil, speed.lastResult?.mode == mode {
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

    // boc #460
    /// #460 (finding 23): this row was written for someone who already knew what
    /// it was — "Carrier endpoints" over "Endpoints to route DIRECT in your proxy
    /// app", sitting on the app's main screen with nothing to say WHEN a person
    /// would ever want it. It now leads with the only question that selects its
    /// audience (are you running a second proxy app?) and states the failure it
    /// prevents, so everyone else can skip it in one line.
    ///
    /// #460 was: title `carrierEndpointsTitle`, hints `carrierEndpointsReadyHint`
    /// / `carrierEndpointsConnectHint`, action `carrierEndpointsCheckAction`
    /// ("Check" — which read as "check the endpoints' health", which it is not).
    private var carrierRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.carrierEndpointsRowTitle.localized())
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(carrierParams != nil
                     ? L10n.carrierEndpointsRowHint.localized()
                     : L10n.carrierEndpointsRowConnectHint.localized())
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            OlcButton(L10n.carrierEndpointsShowAction.localized(), role: .secondary) {
                if let params = carrierParams { onCarrierEndpoints(params) }
            }
            .disabled(carrierParams == nil)
        }
        .padding(.vertical, Theme.Metrics.s3)
    }
    // eoc #460

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
