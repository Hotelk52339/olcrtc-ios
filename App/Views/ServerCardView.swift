import SwiftUI

// MARK: - ServerCardView (#457)
//
// #457: one VPS card, cut out of `ServersView` (`hostCard` / `hostCardTop` /
// `hostCardBottom` / `statusRegion` / `processCaption` / `metricsStrip` /
// `actionBar` / `primaryButton` / `protocolsSection` / `healthSweepFooter`).
// ServersView has hit the Swift type-checker's expression budget twice, so the
// card is a small value-driven struct: every input is a plain value or a
// closure, explicitly typed, and every sub-view here stays under ~20 lines.
//
// Reading order on the card is the order of the questions the owner asks:
//   1 which server is this        → header
//   2 what is true right now      → verdict (headline + progress + failures + process line)
//   3 what runs on it, does it work → PROTOCOLS (the content, above the numbers)
//   4 how is the machine doing    → metrics, demoted
//   5 what do I do next           → ONE full-width action
//
// #457 was: four unlabelled 44pt icon buttons (antenna / arrow.down.doc /
// slider.horizontal.3 / RobotIcon) squeezing the primary action into a fifth of
// the row. Every one of them duplicated an item that is already in the overflow
// menu, so deleting them costs nothing and buys the primary action its width.

/// #457: the primary action a card is allowed to offer. The rule the old
/// `primaryButton` broke: never offer an action no evidence justifies. A server
/// nothing has ever read (`HostBase.unknown`) gets **Check server**, never
/// Install — `scripts/srv.sh` force-removes every `olcrtc-server-*` container,
/// so one tap on a re-added VPS used to destroy a working deployment.
enum ServerPrimaryAction: Equatable {
    case busy, retry, check, start, stop, install

    var isBusy: Bool { self == .busy }

    var title: String {
        switch self {
        case .busy:    return L10n.vpsWorking.localized()
        case .retry:   return L10n.actionRetry.localized()
        case .check:   return L10n.vpsCheckServer.localized()
        case .start:   return L10n.actionStart.localized()
        case .stop:    return L10n.actionStop.localized()
        case .install: return L10n.actionInstall.localized()
        }
    }

    var systemImage: String? {
        switch self {
        case .busy:    return nil
        case .retry:   return "arrow.clockwise"
        case .check:   return "antenna.radiowaves.left.and.right"
        case .start:   return "play.fill"
        case .stop:    return "stop.fill"
        case .install: return "arrow.down.app"
        }
    }

    var role: OlcButton.Role {
        switch self {
        case .busy: return .secondary
        case .stop: return .danger
        default:    return .primary
        }
    }
}

/// #457: the numbers strip, pre-formatted by ServersView — its `shortUsage` /
/// `shortRAM` / `shortUptime` statics stay there because `VPSStatFormattingTests`
/// pins them by name.
struct ServerCardMetrics {
    let ping: String
    let pingTone: Color
    let disk: String
    let ram: String
    let uptime: String
}

struct ServerCardView: View {
    /// Server label.
    let name: String
    /// "user@host:port", already IP-masked by the caller.
    let addressLine: String
    /// The ONE headline (App/Models/HostDisplay.swift) — busy → op-failed →
    /// unreachable → never-checked → stopped → nothing-installed → measured health.
    let headline: HostHeadline
    /// Progress-bar fraction while an op runs; nil leaves the slot empty.
    let progress: Double?
    /// The demoted server-process line, with its own age.
    let processCaption: String
    /// Protocols on this server that a probe found BROKEN or data-less.
    let failingCount: Int
    /// How many protocols that count is out of.
    let protocolCount: Int
    /// Protocols with no usable evidence at all — drives the "Verify all" note.
    let uncheckedCount: Int
    let metrics: ServerCardMetrics
    let rows: [SSHRunner.CarrierInfo]
    /// A protocol-level op (add / remove / sibling start-stop) is in flight.
    let rowsBusy: Bool
    let canAddProtocol: Bool
    let actionsDisabled: Bool
    let primary: ServerPrimaryAction
    /// The single COMPLETE action set for this server.
    let menuItems: [OlcMenuItem]
    let onPrimary: () -> Void
    let onAddProtocol: () -> Void
    let onVerifyAll: () -> Void
    /// Row factory — ServersView owns the resolution from a container to a record.
    let row: (SSHRunner.CarrierInfo) -> ProtocolRowView

    private var isBusy: Bool {
        if case .busy = headline { return true }
        return false
    }

    var body: some View {
        OlcCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                verdict
                protocolsSection
                metricsStrip
                footer
            }
            .animation(.easeOut(duration: 0.2), value: headline)
        }
    }

    // MARK: 1 — identity

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(addressLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 8)
            OlcOverflowMenu(items: menuItems)
                .disabled(actionsDisabled)
        }
    }

    // MARK: 2 — what is true right now

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRegion
            failureBanner
            Text(processCaption)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    /// #341/#335: fixed footprint — the pill always occupies the same slot and
    /// the bar below only fades its opacity, so starting an op never reflows the
    /// card or animates the pill from one anchor to another.
    private var statusRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            OlcStatusPill(tone: headline.tone, title: headline.title, subtitle: headline.subtitle) {
                if isBusy { ProgressView().controlSize(.small) }
            }
            OlcProgressBar(fraction: progress ?? 0)
                .opacity(progress == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }

    /// #457: the headline reports the BEST evidence on purpose ("at least one
    /// protocol works" is the useful sentence), which on its own lets a server
    /// with one working and one dead protocol read as simply fine — a known
    /// failure hidden behind an average. It is never allowed to be silent:
    /// glyph + sentence + count, right under the claim it qualifies.
    @ViewBuilder
    private var failureBanner: some View {
        if failingCount > 0 {
            Label(L10n.vpsProtocolsFailing_fmt.formatted(failingCount, protocolCount),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.orange)
        }
    }

    // MARK: 3 — the protocols (the content)

    @ViewBuilder
    private var protocolsSection: some View {
        if !rows.isEmpty || canAddProtocol {
            VStack(alignment: .leading, spacing: 6) {
                protocolsHeader
                ForEach(rows) { info in row(info) }
            }
            .opacity(isBusy ? 0.45 : 1)
        }
    }

    private var protocolsHeader: some View {
        HStack(spacing: 8) {
            Text(L10n.protocolsSectionHeader.localized().uppercased())
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textTertiary)
            if rowsBusy { ProgressView().controlSize(.mini) }
            Spacer(minLength: 0)
            if canAddProtocol { addProtocolButton }
        }
    }

    private var addProtocolButton: some View {
        Button(action: onAddProtocol) {
            Label(L10n.addProtocolAction.localized(), systemImage: "plus.circle")
                .font(.caption)
        }
        .disabled(actionsDisabled)
    }

    // MARK: 4 — the machine (supporting numbers, below the protocols)

    // #458: the four readings used to sit in ONE row with each label and value
    // side by side, so a cell cost the SUM of their widths and the row could not
    // fit on a phone in Russian. `ServerMetricsGrid` puts the label ABOVE the
    // value (a cell costs the wider of the two) in two columns, and folds to one
    // column at accessibility text sizes. Nothing shrinks — scaling text down
    // makes the reading unreadable, which defeats the point of showing it.
    private var metricsStrip: some View {
        ServerMetricsGrid(metrics: metrics)
            .opacity(isBusy ? 0.45 : 1)
    }

    // MARK: 5 — the one next step

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            OlcButton(primary.title, systemImage: primary.systemImage,
                      role: primary.role, isBusy: primary.isBusy,
                      fillWidth: true, action: onPrimary)
                .disabled(actionsDisabled && !primary.isBusy)
            sweepNote
        }
    }

    /// #456/#457: an automatic sweep is capped and only touches nodes with no
    /// usable evidence, so everything it skipped must SAY it was skipped rather
    /// than look fine.
    @ViewBuilder
    private var sweepNote: some View {
        if uncheckedCount > 0 {
            HStack(spacing: 8) {
                Text(L10n.healthSweepSkipped_fmt.formatted(uncheckedCount))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Button(L10n.healthVerifyAllAction.localized(), action: onVerifyAll)
                    .font(.caption2)
                    .disabled(actionsDisabled)
            }
        }
    }
}

// MARK: - ServerMetricsGrid (#458)
//
// #458: the machine numbers, laid out so they cannot crowd one another.
//
// Two rules do the work:
//   • label ABOVE value (OlcMetric), so a cell needs max(label, value) of width
//     instead of their sum — the single-line pairs were what overflowed;
//   • a fixed TWO-COLUMN grid, one column at accessibility text sizes, so four
//     stats never share one line at any Dynamic Type setting or in any language.
// Columns are equal-width (`maxWidth: .infinity` per cell), so the labels line up
// down the card instead of drifting with the value beside them.
//
// There is no `minimumScaleFactor` anywhere in here, and there must not be: a
// measured value that has to shrink to fit is a value the owner cannot read, and
// an unreadable truth is the failure this whole release was about.

private struct ServerMetricsGrid: View {
    let metrics: ServerCardMetrics

    /// The one thing the grid adapts to. At accessibility sizes two columns of
    /// monospaced numbers stop fitting on any phone, so the stats stack.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Two whole layouts rather than one with `if`s inside the Grid: each
        // stays a tiny expression, which is what this file's rule about the
        // type-checker's budget asks for.
        if typeSize.isAccessibilitySize { stacked } else { paired }
    }

    private var paired: some View {
        Grid(alignment: .topLeading,
             horizontalSpacing: Theme.Metrics.s3,
             verticalSpacing: Theme.Metrics.s3) {
            GridRow {
                cell(L10n.vpsStatPing.localized(), metrics.ping, tone: metrics.pingTone)
                cell(L10n.vpsStatDisk.localized(), metrics.disk)
            }
            GridRow {
                cell(L10n.vpsStatRAM.localized(), metrics.ram)
                cell(L10n.vpsStatUp.localized(), metrics.uptime)
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.s3) {
            cell(L10n.vpsStatPing.localized(), metrics.ping, tone: metrics.pingTone)
            cell(L10n.vpsStatDisk.localized(), metrics.disk)
            cell(L10n.vpsStatRAM.localized(), metrics.ram)
            cell(L10n.vpsStatUp.localized(), metrics.uptime)
        }
    }

    /// One stat. `OlcMetric` is the existing label-above-value component (it
    /// already speaks as one VoiceOver element, "Disk 36/40G"); the frame is what
    /// makes the two columns equal.
    private func cell(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        OlcMetric(label: label, value: Self.reading(value), tone: tone)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// #458: the honesty placeholder the data side already uses — every one of
    /// `ServersView.shortUsage` / `shortRAM` / `shortUptime` / `pingValue`
    /// returns "—" when there is no reading. This is the backstop for anything
    /// that reaches the card empty anyway: a stat with nothing behind it says so,
    /// and never renders as a blank slot that reads like a zero.
    private static func reading(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}
