import SwiftUI

// MARK: - HealthCard (#454)
//
// One consolidated "connection health" panel on the Connections hero, shown
// only while the tunnel is up. Four things in one place: which protocol is
// live, where the exit is (flag + city/country + masked IP), a LIVE latency
// readout, and the last speed-test throughput.
//
// It REUSES the existing services — IPChecker.exitGeo for the location and
// SpeedTest.quickPing / lastResult for latency + throughput — rather than a
// parallel measurement stack. It is a SEPARATE view struct (not inlined into
// ConnectionsView.body) so that already-large body stays under the SwiftUI
// type-checker budget.

struct HealthCard: View {
    /// The live record (TunnelManager.connectedRecord). nil is tolerated but the
    /// card is only mounted while connected, so it is effectively always present.
    let record: ConnectionRecord?
    @ObservedObject var ipCheck: IPChecker
    @ObservedObject var speed: SpeedTest
    /// Route for the live probes — `.tunnel` while connected.
    let mode: RouteMode
    /// #337: screenshot-safe IP masking (mirrors the IP-check rows).
    let maskIPs: Bool

    /// Live latency, refreshed by the ping loop below. nil → "measuring…".
    @State private var latencyMs: Double?

    var body: some View {
        OlcCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.healthTitle.localized())
                    .font(Theme.Typography.sectionHeader)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.textTertiary)

                protocolRow
                Divider().overlay(Theme.Palette.separator)
                exitRow
                Divider().overlay(Theme.Palette.separator)
                metricsRow
            }
        }
        // Live latency: measure now, then every ~8 s. Keyed on the live record so
        // a failover (record swap, #453) restarts the loop against the new
        // protocol; the conditional mount cancels it on disconnect.
        .task(id: record?.id) {
            while !Task.isCancelled {
                let ms = await speed.quickPing(via: mode)
                if Task.isCancelled { return }
                latencyMs = ms
                try? await Task.sleep(for: .seconds(8))
            }
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
            if let geo = ipCheck.exitGeo, geo != IPChecker.ExitGeo() {
                VStack(alignment: .trailing, spacing: 1) {
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
                }
            } else {
                Text(L10n.healthLocationUnknown.localized())
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            OlcMetric(label: L10n.healthLatencyLabel.localized(),
                      value: latencyValue)
            OlcMetric(label: L10n.healthThroughputLabel.localized(),
                      value: throughputValue,
                      unit: L10n.speedUnitMbps.localized(), unitInLabel: true)
            Spacer(minLength: 8)
            Button {
                Task {
                    await ipCheck.refreshExitGeo(via: mode)
                    latencyMs = await speed.quickPing(via: mode)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .accessibilityLabel(L10n.healthRefresh.localized())
        }
    }

    // MARK: Helpers

    private var latencyValue: String {
        guard let ms = latencyMs else { return L10n.healthMeasuring.localized() }
        return L10n.healthLatencyMs_fmt.formatted(Int(ms.rounded()))
    }

    /// "City, CC" from whatever geo fields are present ("location unknown" when
    /// neither is). The flag glyph is rendered separately, next to this.
    private func placeString(_ geo: IPChecker.ExitGeo) -> String {
        let place = [geo.city, geo.country].compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty ? L10n.healthLocationUnknown.localized() : place
    }

    /// "DL / UL" from the last speed test (a bare "—" before any test runs). The
    /// throughput here is user-driven (the existing speed-test button below fills
    /// it) — the card never auto-runs a test.
    private var throughputValue: String {
        guard let r = speed.lastResult else { return "—" }
        let dl = r.downloadMbps.map { String(format: "%.1f", $0) } ?? "—"
        let ul = r.uploadMbps.map { String(format: "%.1f", $0) } ?? "—"
        return "\(dl) / \(ul)"
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
