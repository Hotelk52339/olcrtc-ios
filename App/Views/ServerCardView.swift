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
//   2 what is true right now      → verdict (headline + progress + failures)
//   3 what runs on it, does it work → PROTOCOLS (the content, above the numbers)
//   4 how is the machine doing    → metrics, demoted, with the age of the reading
//   5 what do I do next           → two frequent verbs + ONE full-width action
//   6 what else can I do to it    → "Manage server ›", a push (#459)
//
// boc #459: the card grows into the empty half of the Servers screen instead of
// something new being invented to fill it — 20pt between blocks, roomier
// protocol rows, and the four affordances the owner reached for most often
// (Check server, Container logs, the primary verb, and the way to everything
// else) visible on the card rather than buried in a 13-item ⋯ menu.
// What LEFT the card in the same pass:
//   • the process caption ("Server process is running · read 2m ago") — it
//     restated the status pill and each protocol row already says whether its
//     own container is up. Only its AGE was load-bearing, so the age survives
//     as the read stamp on the metrics block, and nothing else does.
//   • the sweep note ("N more not checked — tap Verify all") — a footnote
//     advertising a button that pull-to-refresh replaces. Every skipped
//     protocol still says "not checked" in its own chip, which is the same
//     fact stated per item instead of in aggregate.
// eoc #459
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

/// #459: one visible quick action. Two of these sit above the primary button —
/// the verbs the owner reaches for constantly (Check server, Container logs),
/// which used to cost a ⋯ tap plus a scan of thirteen items. Value-driven and
/// explicitly typed, like every other input on this card, so the row costs the
/// type-checker nothing.
struct ServerQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let action: () -> Void
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
    /// #459: how old the machine numbers beside it are ("read 2 min ago"), or
    /// the honest "nothing has been read yet". The ONLY survivor of the deleted
    /// process caption: an age the user can see is the age of the reading.
    /// #459 was: `processCaption` — "Server process is running · read 2m ago".
    let readCaption: String
    /// Protocols on this server that a probe found BROKEN or data-less.
    let failingCount: Int
    /// How many protocols that count is out of.
    let protocolCount: Int
    let metrics: ServerCardMetrics
    let rows: [SSHRunner.CarrierInfo]
    /// A protocol-level op (add / remove / sibling start-stop) is in flight.
    let rowsBusy: Bool
    let canAddProtocol: Bool
    let actionsDisabled: Bool
    let primary: ServerPrimaryAction
    /// #459: the frequent verbs, promoted out of the menu. Empty ⇒ the row is
    /// not drawn at all (nothing is installed yet, so Logs / Check would read an
    /// empty server and the card's whole offer is its primary CTA).
    let quickActions: [ServerQuickAction]
    /// The safe, occasional action set for this server (5 items). Everything
    /// rare or destructive lives behind `onManage` (#459).
    let menuItems: [OlcMenuItem]
    let onPrimary: () -> Void
    let onAddProtocol: () -> Void
    /// #459: push the full server-management screen.
    let onManage: () -> Void
    /// Row factory — ServersView owns the resolution from a container to a record.
    let row: (SSHRunner.CarrierInfo) -> ProtocolRowView

    private var isBusy: Bool {
        if case .busy = headline { return true }
        return false
    }

    var body: some View {
        OlcCard {
            // #459: 12 → 20 between blocks (Theme.Metrics.s5, "block ↔ block
            // inside a card"). Six children, five gaps: the card reads as five
            // answers instead of one dense slab, and the ~40pt it costs comes
            // straight out of the empty half of the screen.
            // #459 was: VStack(alignment: .leading, spacing: 12) { header;
            // verdict; protocolsSection; metricsStrip; footer }
            VStack(alignment: .leading, spacing: Theme.Metrics.s5) {
                header
                verdict
                protocolsSection
                metricsBlock
                actions
                manageRow
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

    /// #459 was: a third line here, `Text(processCaption)` — "Server process is
    /// running · read 2m ago". The pill directly above it already answers "what
    /// is true right now", and each protocol row answers it per container, so
    /// the sentence was the same claim written a third time. Its age moved to
    /// the numbers it actually dates (see `metricsBlock`).
    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRegion
            failureBanner
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
            // #459 was: spacing 6 — see ProtocolRowView's own padding note.
            VStack(alignment: .leading, spacing: Theme.Metrics.s2 + 2) {
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
    /// #459: the numbers, with the age of the reading pinned to their top-right
    /// corner. Nothing else moved — `ServerMetricsGrid` (#458) is what makes the
    /// values structurally un-truncatable and must not be regressed.
    /// #459 was: `metricsStrip` — the grid alone; its age was a sentence three
    /// blocks up, attached to a claim about the process rather than to these.
    private var metricsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.s2) {
            // No `lineLimit` and no `minimumScaleFactor`, for the same reason
            // the grid below has neither: the Russian never-read stamp is a
            // whole sentence, and a stamp that truncates is a stamp that lies
            // about how old the numbers are (#459).
            Text(readCaption)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ServerMetricsGrid(metrics: metrics)
        }
        .opacity(isBusy ? 0.45 : 1)
    }

    // MARK: 5 — what do I do next (two frequent verbs + the one primary action)

    private var actions: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.s3) {
            quickRow
            OlcButton(primary.title, systemImage: primary.systemImage,
                      role: primary.role, isBusy: primary.isBusy,
                      fillWidth: true, action: onPrimary)
                .disabled(actionsDisabled && !primary.isBusy)
        }
    }

    /// #459: the two verbs that were reached for constantly through the ⋯ menu.
    /// They can never duplicate the primary button: `primary == .check` happens
    /// only on `HostBase.unknown`, and a host nothing has read carries no
    /// container, so ServersView hands us an empty array exactly then.
    @ViewBuilder
    private var quickRow: some View {
        if !quickActions.isEmpty {
            HStack(spacing: Theme.Metrics.s2) {
                ForEach(quickActions) { item in
                    OlcButton(item.title, systemImage: item.systemImage,
                              role: .secondary, fillWidth: true, compact: true,
                              action: item.action)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(actionsDisabled)
        }
    }

    // MARK: 6 — everything else (#459)

    /// #459: the way to the rare and the destructive. Eleven ⋯ items became one
    /// row: a push whose `Form` can give every destructive verb a sentence
    /// saying what it destroys — which a `Menu` cannot render at all. That is
    /// why "Wipe all olcrtc data from server" used to sit in a scrolling list
    /// with nothing but its own name to warn you.
    private var manageRow: some View {
        VStack(spacing: Theme.Metrics.s3) {
            Divider().overlay(Theme.Palette.separator)
            manageButton
        }
    }

    private var manageButton: some View {
        Button(action: onManage) {
            HStack {
                Text(L10n.vpsManageServer.localized())
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .contentShape(Rectangle())
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .disabled(actionsDisabled)
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
//
// #459 (re-audit, do not regress): the screenshot that reported "DISK 3.5/8.…"
// predates this grid. Truncation is structurally impossible here only while ALL
// FOUR rules hold together, so they are written down:
//   1. label ABOVE value (`OlcMetric`) — a cell costs max(label, value);
//   2. two equal-width columns (`maxWidth: .infinity` per cell), one at
//      accessibility sizes;
//   3. NO `minimumScaleFactor` and NO `lineLimit` on a LABEL — a label that
//      cannot wrap is a label that truncates. Only the VALUE keeps
//      `OlcMetric`'s own `lineLimit(1)`, because a wrapped number is a lie;
//   4. the data side guarantees the value fits: `shortUsage` → "3.5/8.0G",
//      `shortRAM` → "0.4/1.9G", `shortUptime` → "13:57"/"3d",
//      `pingValue` → "255ms"/"✕"/"—" — ≤ 9 monospaced characters, i.e. ~62pt
//      inside a ≥150pt column on the narrowest supported phone.

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
