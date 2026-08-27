import SwiftUI

// MARK: - HealthCard (#454, reworked #457)
//
// The dated evidence strip under the Connect hero, mounted only while a session
// is up. Four facts in one place: which protocol is live, where the exit is,
// the live latency, and the last throughput.
//
// #457: NOTHING IS DRAWN THAT CANNOT BE DATED. Every value here now carries the
// age of the measurement behind it, in the same `HealthAge` vocabulary the row
// verdicts use, so a number from four minutes ago can never read as "now".
//
// #457 also closes the "measuring… forever" hole. `SpeedTest.quickPing` returns
// nil on ANY error, so the card's `attempted` flag was the only thing keeping a
// permanently failing probe from claiming work-in-progress indefinitely — and it
// only distinguished "not yet" from "failed", never saying WHEN the failure was.
// The state machine is now explicit: `probing` (a measurement is in flight now)
// vs `latencyAt` (when one last completed). "Checking…" is reachable only while
// `probing` is true AND nothing has completed yet; after that it is "not
// measured", stamped.
//
// Throughput is deliberately harder to claim: `SpeedResult` carries no
// timestamp, so a `lastResult` inherited from an earlier session — or from a
// DIRECT-mode test — is not evidence about the tunnel that is up now. The card
// reports throughput only for a test it watched finish, on this route.
//
// It stays a SEPARATE view struct (not inlined into ConnectionsView.body) so
// that file's already-large body stays under the SwiftUI type-checker budget.

struct HealthCard: View {
    /// The live record (TunnelManager.connectedRecord). nil is tolerated but the
    /// card is only mounted while connected, so it is effectively always present.
    let record: ConnectionRecord?
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    /// Route for the live probes — `.tunnel` while connected in proxy mode.
    let mode: RouteMode
    /// #337: screenshot-safe IP masking (mirrors the IP-check rows).
    let maskIPs: Bool

    /// Live latency, refreshed by the ping loop below. nil = no measurement.
    @State private var latencyMs: Double?
    /// #457: when the last latency measurement COMPLETED (success or failure).
    /// nil ⇒ none has completed for this record yet.
    @State private var latencyAt: Date?
    /// #457: a measurement is in flight right now. The ONLY thing that licenses
    /// the word "Checking…".
    @State private var probing = false
    /// #457: when `ipCheck.exitGeo` last changed — the exit line's age. Tracked
    /// here because `ExitGeo` carries no timestamp and the refresh is also fired
    /// from outside this card (ConnectionsView, on the connect transition).
    @State private var exitAt: Date?
    /// #457: when a speed test finished while this card was on screen. Nothing
    /// else may be dated, so nothing else is reported.
    @State private var throughputAt: Date?

    var body: some View {
        OlcCard {
            // #457 was: two `Divider()`s between the rows. Rhythm does the same
            // job with less ink — 8 pt inside a pair, 18 pt between rows.
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.healthTitle.localized())
                    .font(Theme.Typography.sectionHeader)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.textTertiary)
                protocolRow
                exitRow
                metricsRow
            }
        }
        // Live latency: measure now, then every ~8 s. Keyed on the live record so
        // a failover (record swap, #453) restarts the loop against the new
        // protocol; the conditional mount cancels it on disconnect. The 8 s tick
        // is also what re-renders every age on this card.
        .task(id: record?.id) { await runLatencyLoop() }
        // #457: `ExitGeo` is Equatable, so this catches BOTH refresh paths — the
        // button below and ConnectionsView's connect-transition fetch.
        .onChange(of: ipCheck.exitGeo) { _, new in
            if new == nil { exitAt = nil } else { exitAt = Date() }
        }
        // #457: `SpeedResult` is not Equatable and carries no date; the falling
        // edge of `isTesting` is the moment a run we can attribute completed.
        .onChange(of: speed.isTesting) { was, now in if was && !now { throughputAt = Date() } }
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

    @ViewBuilder
    private var protocolRow: some View {
        healthRow(L10n.healthProtocolLabel.localized()) {
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

    @ViewBuilder
    private var exitRow: some View {
        healthRow(L10n.healthExitLabel.localized()) {
            VStack(alignment: .trailing, spacing: 2) {
                exitValue
                // #457: the exit's age. A country printed with no date is a claim
                // about now made from evidence about then.
                ageCaption(exitAt)
            }
        }
    }

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

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            datedMetric(label: L10n.healthLatencyLabel.localized(),
                        value: latencyValue, at: latencyAt, tone: latencyTone)
            datedMetric(label: L10n.healthThroughputLabel.localized(),
                        value: throughputValue, at: throughputAt, tone: nil)
            Spacer(minLength: 8)
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                probing = true
                await ipCheck.refreshExitGeo(via: mode)
                latencyMs = await speed.quickPing(via: mode)
                latencyAt = Date()
                probing = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .accessibilityLabel(L10n.healthRefresh.localized())
    }

    // MARK: Values

    /// #457 was: nil ⇒ "measuring…" (forever, over a dead data path) and later
    /// nil ⇒ "not measured" with no date. The word for work-in-progress is now
    /// licensed by `probing` alone, and the verdict carries its stamp below.
    private var latencyValue: String {
        if let ms = latencyMs { return L10n.healthLatencyMs_fmt.formatted(Int(ms.rounded())) }
        if probing && latencyAt == nil { return L10n.healthChecking.localized() }
        return L10n.healthLatencyNotMeasured.localized()
    }

    /// #455: tint the live latency by quality. #457: with no measurement, tertiary
    /// says plainly that this is not a value.
    private var latencyTone: Color? {
        guard let ms = latencyMs else {
            return latencyAt == nil ? nil : Theme.Palette.textTertiary
        }
        switch Int(ms.rounded()) {
        case ..<150: return Theme.Palette.green
        case ..<400: return Theme.Palette.orange
        default:     return Theme.Palette.red
        }
    }

    /// #457 was: `speed.lastResult` rendered unconditionally — a figure from a
    /// previous session, or from a DIRECT-mode test, presented as this tunnel's
    /// throughput. `SpeedResult` has no timestamp, so the card reports only a run
    /// it watched finish, on this route.
    private var throughputValue: String {
        if speed.isTesting { return "…" }
        guard throughputAt != nil, let r = speed.lastResult, r.mode == mode else { return "—" }
        let dl = r.downloadMbps.map { String(format: "%.1f", $0) } ?? "—"
        let ul = r.uploadMbps.map { String(format: "%.1f", $0) } ?? "—"
        return "\(dl) / \(ul)"
    }

    // MARK: Pieces

    /// A metric with the age of the measurement under it — the card's whole rule
    /// in one component. `at == nil` prints "never measured", not a blank.
    private func datedMetric(label: String, value: String,
                             at: Date?, tone: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            OlcMetric(label: label, value: value, tone: tone)
            ageCaption(at)
        }
    }

    private func ageCaption(_ at: Date?) -> some View {
        Text(ageText(at))
            .font(.caption2)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineLimit(1)
    }

    /// #457: the age of ONE measurement, in the same `HealthAge` vocabulary the
    /// row verdicts use. No stamp means the fact was never measured — say so;
    /// never print a value with a blank where its date belongs.
    private func ageText(_ at: Date?) -> String {
        guard let at else { return L10n.healthNeverMeasured.localized() }
        return L10n.healthCheckedAgo_fmt.formatted(HealthAge.label(Date().timeIntervalSince(at)))
    }

    /// "City, CC" from whatever geo fields are present ("location unknown" when
    /// neither is). The flag glyph is rendered separately, next to this.
    private func placeString(_ geo: IPChecker.ExitGeo) -> String {
        let place = [geo.city, geo.country].compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty ? L10n.healthLocationUnknown.localized() : place
    }

    @ViewBuilder
    private func healthRow<Trailing: View>(_ label: String,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 12)
            trailing()
        }
    }
}
