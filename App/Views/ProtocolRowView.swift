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
// This is the densest element in the app — one line has to answer "what is this
// protocol, does it work, and how do I know". The two inversions it fixes:
//
//  • SEMANTIC — nothing here is carried by colour alone. The evidence chip
//    renders glyph + word + age; the row adds the WORD "Connected" for the
//    protocol the tunnel is running through, and a plain sentence when the
//    server-side process is not running.
//    #457 was: a cyan `checkmark.circle.fill` whose only text was an
//    `accessibilityLabel`, i.e. "live" was a colour to everyone who could see it.
//
//  • DECORATION — #455's aurora WASH, its cyan hairline and the cyan checkmark
//    are gone (`Theme.Palette.auroraSoft` is deleted). The aurora survives as
//    exactly ONE thing: a 3pt leading spine, and only where it is a VERDICT —
//    the row is live AND a probe verified it inside the freshness window.

struct ProtocolRowView: View {
    /// Carrier display name ("Telemost").
    let title: String
    /// Transport display name ("vp8channel").
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

    var body: some View {
        HStack(spacing: 10) {
            spine
            labels
            Spacer(minLength: 8)
            OlcHealthChip(display: health, onTap: onVerify)
            OlcOverflowMenu(items: menuItems)
                .disabled(menuDisabled)
        }
        // #459: 7 → 10. The card now breathes at 20pt between blocks, and a row
        // packed tighter than its neighbours read as a list crammed into a
        // corner of a half-empty screen. Nothing is added — the same three
        // channels just stop touching each other.
        // #459 was: .padding(.vertical, 7)
        .padding(.vertical, 10)
        .padding(.trailing, 8)
        .background(Theme.Palette.fill.opacity(0.5), in: rowShape)
    }

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

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLine
            Text(subtitleText)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(isLive ? .semibold : .regular))
                .foregroundStyle(Theme.Palette.textPrimary)
            if isLive { liveBadge }
            if isPrimary { primaryBadge }
        }
    }

    /// #457: glyph AND word. "Connected" is a fact about this row, so it is
    /// written down, not painted on.
    private var liveBadge: some View {
        Label(L10n.protocolConnectedBadge.localized(), systemImage: "bolt.horizontal.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    private var primaryBadge: some View {
        Text(L10n.protocolPrimaryBadge.localized())
            .font(.caption2)
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    /// #457 was: `"\(transport) · \(row.status.shortLabel)"` — raw `podman ps`
    /// text ("Up 3 hours", "Exited (137) 5 minutes ago") sitting in a top-level
    /// row. Process liveness answers a question the user did not ask; a stopped
    /// process is now one plain sentence and a running one adds nothing.
    private var subtitleText: String {
        isRunningOnServer
            ? transport
            : "\(transport) · \(L10n.protocolStoppedNote.localized())"
    }
}

// #340: both appearance variants.
#if DEBUG
#Preview("Protocol row — Dark") {
    VStack(spacing: 8) {
        ProtocolRowView(title: "Telemost", transport: "vp8channel",
                        isPrimary: true, isLive: true, isRunningOnServer: true,
                        health: .verified(ms: 48, age: 120),
                        menuDisabled: false, menuItems: [], onVerify: {})
        ProtocolRowView(title: "Jitsi", transport: "datachannel",
                        isPrimary: false, isLive: false, isRunningOnServer: false,
                        health: .never,
                        menuDisabled: false, menuItems: [], onVerify: {})
        ProtocolRowView(title: "WBStream", transport: "seichannel",
                        isPrimary: false, isLive: false, isRunningOnServer: true,
                        health: .broken(.keyMismatch, age: 300),
                        menuDisabled: false, menuItems: [], onVerify: {})
    }
    .padding()
    .background(Theme.Palette.bg)
    .preferredColorScheme(.dark)
}
#endif
