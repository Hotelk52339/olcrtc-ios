import SwiftUI

// MARK: - ProtocolRowView (#457)
//
// #457: the per-protocol row, cut out of `ServersView.carrierRowView` +
// `carrierRowLead`. ServersView has hit the Swift type-checker's expression
// budget twice (see `ServersView.carrierModals`), so everything this screen
// gains from here on lands in a small, value-driven struct like this one: every
// input is a plain value or a closure, and every parameter is explicitly typed,
// so the row costs the type-checker nothing to resolve.
//
// This is the densest element in the app — one row has to answer "what is this
// protocol, does it work, and how do I know". #460: "one row", not "one
// line" — the labels column is ~105pt wide once the evidence chip and the
// fixed 44pt menu have taken theirs, so each answer gets a line of its own
// rather than a share of one. The two inversions it fixes:
//
//  • SEMANTIC — nothing here is carried by colour alone. The evidence chip
//    renders glyph + word + age; the row adds a glyph AND the word "Live" for
//    the protocol the tunnel is running through (#460 was: "Connected", which
//    was long enough to be hyphenated into "Connec-ted"), and a plain sentence
//    when the server-side process is not running.
//    #457 was: a cyan `checkmark.circle.fill` whose only text was an
//    `accessibilityLabel`, i.e. "live" was a colour to everyone who could see it.
//
//  • DECORATION — #455's aurora WASH, its cyan hairline and the cyan checkmark
//    are gone (`Theme.Palette.auroraSoft` is deleted). The aurora survives as
//    exactly ONE thing: a 3pt leading spine, and only where it is a VERDICT —
//    the row is live AND a probe verified it inside the freshness window.

struct ProtocolRowView: View {
    /// #461: the SERVICE this protocol hides the traffic inside — the row's
    /// identity ("Yandex Telemost"), composed by `ServersView.rowView` from the
    /// same `CarrierTransportMatrix` labels the Connect tab reads through
    /// `ConnectionNaming.service(_:)`.
    /// #461 was: "Carrier display name ("Telemost")".
    let title: String
    /// #461: HOW it is carried, already a display LABEL ("VP8"), not the raw
    /// transport id. It leads `subtitleText`, one line under the service.
    /// #461 was: "Transport display name ("vp8channel")" — the doc named the id
    /// while the call site has always passed `transportLabel(_:)`.
    let transport: String
    /// The srv.sh-installed protocol — the one whose container anchors the deploy dir.
    let isPrimary: Bool
    /// The live tunnel currently runs through this protocol.
    let isLive: Bool
    /// The server-side process for this protocol is up (a real reading, not a guess).
    let isRunningOnServer: Bool
    /// Measured evidence — the ONLY source of green (App/Models/NodeHealth.swift).
    let health: HealthDisplay
    /// True while an SSH op holds the lane.
    let menuDisabled: Bool
    /// The complete action set for this protocol — ONE menu, no rival controls.
    let menuItems: [OlcMenuItem]
    /// Re-run the end-to-end probe for THIS protocol.
    let onVerify: () -> Void

    /// #460: the one thing the row's shape adapts to. Private with a default,
    /// so the memberwise init ServersView calls is unchanged.
    @Environment(\.dynamicTypeSize) private var typeSize

    // boc #460: finding 16 — the live row hyphenated its own status word
    // ("Connec-ted"). The row is three channels wide — labels, evidence chip
    // and the overflow menu — and the menu costs a FIXED 44pt at every text size, so
    // on a 393pt phone the labels column is left with roughly 105pt. A carrier
    // name and a status word never fitted in that together, and SwiftUI resolves
    // an impossible line by breaking the last word in it.
    //
    // Three changes, each removing one cause:
    //   1. the badge has its OWN line (see `labels`), so it never competes with
    //      the carrier name for width;
    //   2. it is `lineLimit(1)` + `fixedSize`, which makes a break impossible at
    //      any width it is ever offered — the chip beside it is the flexible one
    //      and is documented to wrap instead (App/UI/HealthChip.swift);
    //   3. the word itself is shorter (`protocolLiveBadge`), because the old one
    //      was the longest string in the row in both languages.
    // The `primary` tag left the title line for the same reason and now joins
    // the technical subtitle, which may wrap freely: it breaks at " · " between
    // words, never inside one.
    var body: some View {
        layout
            .padding(.vertical, 10)
            .padding(.trailing, 8)
            .background(Theme.Palette.fill.opacity(0.5), in: rowShape)
    }

    /// #460: at the accessibility text sizes the evidence chip alone is wider
    /// than the whole labels column, so the row stops sharing one line — the
    /// same rule `ServerMetricsGrid` (App/Views/ServerCardView.swift) follows
    /// for the machine numbers. Two whole layouts rather than one with `if`s
    /// inside it, so each stays a tiny expression.
    @ViewBuilder
    private var layout: some View {
        if typeSize.isAccessibilitySize { stacked } else { inline }
    }

    private var inline: some View {
        HStack(spacing: 10) {
            spine
            labels
            Spacer(minLength: 8)
            OlcHealthChip(display: health, onTap: onVerify)
            overflow
        }
    }

    private var stacked: some View {
        HStack(alignment: .top, spacing: 10) {
            spine
            VStack(alignment: .leading, spacing: Theme.Metrics.s2) {
                labels
                OlcHealthChip(display: health, onTap: onVerify)
            }
            Spacer(minLength: 0)
            overflow
        }
    }

    private var overflow: some View {
        OlcOverflowMenu(items: menuItems)
            .disabled(menuDisabled)
    }
    // eoc #460

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    /// #457: the only aurora left on this screen, and it is a verdict mark.
    /// Live + verified → aurora. Live but unproven → a neutral spine (the row is
    /// still the one carrying traffic, we just have no proof yet). Anything else
    /// → nothing at all, because an unproven row must draw nothing.
    private var spine: some View {
        Capsule(style: .continuous)
            .fill(spineStyle)
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .padding(.leading, 5)
            .accessibilityHidden(true)
    }

    private var spineStyle: AnyShapeStyle {
        if isLive && health.isVerified { return AnyShapeStyle(Theme.Palette.auroraGradient) }
        if isLive { return AnyShapeStyle(Theme.Palette.textTertiary) }
        return AnyShapeStyle(Color.clear)
    }

    // #460 was: `titleLine` — an HStack packing the carrier name, the live
    // badge and the `primary` tag onto one ~105pt line. Three lines that each fit
    // is the whole fix; nothing is dropped, the tag moves into `subtitleText`.
    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(isLive ? .semibold : .regular))
                .foregroundStyle(Theme.Palette.textPrimary)
                // boc #461: TWO lines, not one.
                // #460 was: `.lineLimit(1)`, on the stated premise that "carrier
                // names are 5-8 characters, so this is a backstop rather than
                // something anyone will see". That premise expired the moment
                // the carrier became its full service name ("Yandex Telemost",
                // «Яндекс Телемост») — at one line it is the very word the owner
                // asked to see, ellipsised, in a labels column that is ~105pt
                // once the evidence chip and the fixed 44pt menu have taken
                // theirs.
                // What #460 actually guaranteed was never "one line", it was
                // "never break a WORD" (finding 16, "Connec-ted"). Two lines
                // keep that guarantee intact: the break falls on the space
                // between the two words, and each of them is far narrower than
                // the column at every non-accessibility text size — and at
                // accessibility sizes `stacked` gives the labels the whole row.
                .lineLimit(2)
                // eoc #461
            if isLive { liveBadge }
            Text(subtitleText)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    /// #457: glyph AND word. Which protocol carries the tunnel is a fact about
    /// this row, so it is written down, not painted on.
    /// #460 was: `protocolConnectedBadge` — nine characters in English and ten
    /// in Russian, on the title line, with nothing forbidding a break, so the
    /// longest word in the row was also the one SwiftUI hyphenated. The word is
    /// now the short one that says the same thing, on its own line, one line
    /// only, at its natural width: `lineLimit(1)` forbids the second line and
    /// `fixedSize` refuses any width narrower than the word, which together make
    /// "Connec-ted" structurally impossible rather than merely unlikely.
    private var liveBadge: some View {
        Label(L10n.protocolLiveBadge.localized(), systemImage: "bolt.horizontal.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// #457 was: `"\(transport) · \(row.status.shortLabel)"` — raw `podman ps`
    /// text ("Up 3 hours", "Exited (137) 5 minutes ago") sitting in a top-level
    /// row. Process liveness answers a question the user did not ask; a stopped
    /// process is now one plain sentence and a running one adds nothing.
    /// #460: the `primary` tag joins it, off the title line. This is the ONE
    /// line in the row that is allowed to wrap, and it is safe to: every break
    /// falls on a " · " boundary between words, never inside one.
    private var subtitleText: String {
        var parts = [transport]
        if isPrimary { parts.append(L10n.protocolPrimaryBadge.localized()) }
        if !isRunningOnServer { parts.append(L10n.protocolStoppedNote.localized()) }
        return parts.joined(separator: " · ")
    }
}

// #340: both appearance variants.
#if DEBUG
#Preview("Protocol row — Dark") {
    VStack(spacing: 8) {
        // #461: the real strings the call site passes — service labels (the
        // longest of them is the one this row has to survive) over transport
        // LABELS, not raw ids. A preview that lies about its inputs cannot show
        // the width pressure the row is built for.
        ProtocolRowView(title: "Yandex Telemost", transport: "VP8",
                        isPrimary: true, isLive: true, isRunningOnServer: true,
                        health: .verified(ms: 48, age: 120),
                        menuDisabled: false, menuItems: [], onVerify: {})
        ProtocolRowView(title: "Jitsi", transport: "DataChannel",
                        isPrimary: false, isLive: false, isRunningOnServer: false,
                        health: .never,
                        menuDisabled: false, menuItems: [], onVerify: {})
        ProtocolRowView(title: "WB Stream", transport: "SEI",
                        isPrimary: false, isLive: false, isRunningOnServer: true,
                        health: .broken(.keyMismatch, age: 300),
                        menuDisabled: false, menuItems: [], onVerify: {})
    }
    .padding()
    .background(Theme.Palette.bg)
    .preferredColorScheme(.dark)
}
#endif
