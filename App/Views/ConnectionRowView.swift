import SwiftUI

// MARK: - ConnectionRowView (#457)
//
// #457: the SEMANTIC INVERSION fix, and the retirement of "primary".
//
// The old row (`ConnectionsView.serverRow`) carried status in COLOUR alone: a
// 24 pt aurora circle with a white bolt for the live node, an amber ring plus a
// "Main" capsule for the selected one, an empty grey ring otherwise, and a 7 pt
// coloured dot inside `OlcHealthChip`. Five states, one shape, no glyph and —
// in the chip — no word at all. Under Accessibility → Colour Filters →
// Grayscale the whole vocabulary collapsed. WCAG 2.2 SC 1.4.1 and Apple's
// "Differentiate Without Color Alone" both fail on that.
//
// Every state here renders THREE channels: a distinct SF Symbol, the word, and
// the age — all three straight out of the honesty layer's `HealthDisplay`, so a
// row can never make a claim `HealthCoordinator` has not dated.
//
// #457 was: tapping a row called `store.setPrimary` + `Haptics.tap()` and did
// NOT connect — the most natural gesture in the app produced a gold star and a
// buzz and no connection, while "Connect" appeared in the overflow menu only on
// rows that were NOT already primary, i.e. missing on the row you most wanted.
// A tap now CONNECTS (`TunnelManager.connect(record:)` disconnects-then-dials,
// so it is safe from any state); the caller keeps `store.primary` in step as a
// side effect, purely so auto-connect-on-launch still has a record to read.
//
// A failing row also carries its FIX. `HealthDisplay.suggestedAction` was
// already computed and simply never rendered, so "This server's key no longer
// matches" was a dead end unless the user thought to open an overflow menu.
// Re-checking runs here; everything else names the screen it lives on rather
// than drawing a button that cannot work (see `ConnectActionSite`).

struct ConnectionRowView: View {

    let record: ConnectionRecord
    /// The honesty layer's dated verdict for this record.
    let display: HealthDisplay
    /// True only for the node the tunnel is actually running through
    /// (`TunnelManager.connectedRecord`) — never `store.primary`.
    let isLive: Bool
    /// #337: screenshot-safe IP masking for the subscription meta line.
    let maskIPs: Bool
    let menuItems: [OlcMenuItem]
    /// Tap = connect through this node.
    let onConnect: () -> Void
    /// The inline "Check" / "Retry" affordance on a failing row.
    let onVerify: () -> Void

    var body: some View {
        OlcCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    // #457: a real Button (not an `onTapGesture`) so VoiceOver
                    // gets the button trait and one activatable element, while
                    // the overflow menu stays its OWN element beside it — the old
                    // row used `.accessibilityElement(children: .combine)` on the
                    // whole card, which swallowed the menu.
                    Button(action: onConnect) { infoColumn }
                        .buttonStyle(.plain)
                        .accessibilityHint(L10n.connectRowTapHint.localized())
                    trailingColumn
                }
                // #457: OUTSIDE the connect Button. A button nested inside another
                // button does not reliably receive taps and reads as one control
                // to VoiceOver — and this is the control that repairs the node.
                inlineFix
            }
        }
        // #457: the aurora is a VERDICT, not a style — the spine appears only on
        // the node carrying traffic AND only while its proof is still fresh.
        // Connected-but-unverified draws nothing, which is the whole point.
        .overlay(alignment: .leading) { auroraSpine }
    }

    // MARK: The subject + its evidence

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.displayName)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Text(record.subtitle)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
            metaLine
            verdictLine
            evidenceLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Glyph + WORD. The glyph is the shape channel, the word is the text
    /// channel, colour is only the third — so this survives Grayscale.
    private var verdictLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            verdictGlyph
            Text(display.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(verdictTextColor)
                // #457: a reason is never truncated (HIG Typography).
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    /// #457: the SHAPE channel. `.checking` is the one state that earns a moving
    /// indicator, and a system `ProgressView` stops the instant the state resolves
    /// and honours Reduce Motion for free.
    @ViewBuilder
    private var verdictGlyph: some View {
        if display.isChecking {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: ConnectHealthGlyph.symbol(for: display))
                .font(.caption)
                .foregroundStyle(display.tone.color)
        }
    }

    /// The AGE. `HealthDisplay.subtitle` is already the dated sentence — for a
    /// failure it is "<why> · checked 5m ago", for a pass "Verified 2m ago · 48 ms".
    private var evidenceLine: some View {
        Text(display.subtitle)
            .font(.caption2)
            .foregroundStyle(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var verdictTextColor: Color {
        // Only `.verified` is green and only `.broken` is red — everything else
        // reads as neither good nor bad, which is what "we do not know" looks like.
        display.tone == .unknown ? Theme.Palette.textSecondary : display.tone.color
    }

    /// #363: per-node subscription metadata (`##ip` / `##comment`), both
    /// server-supplied free text — rendered defensively, with no styling derived
    /// from the value.
    @ViewBuilder
    private var metaLine: some View {
        if record.subIP != nil || record.subComment != nil {
            HStack(spacing: 6) {
                if let ip = record.subIP, !ip.isEmpty {
                    Text(IPMask.display(ip, masked: maskIPs))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                if let comment = record.subComment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    // MARK: The fix, offered where the failure is shown

    /// Only states that mean "something is wrong" get a full inline affordance.
    /// `.never` / `.stale` also suggest `.verify`, but on a fresh install EVERY
    /// row is `.never` — a button on all of them would be noise, so those keep
    /// the section's "Check all" and the row menu.
    private var fixAction: HealthAction? {
        switch display {
        case .broken, .inconclusive: return display.suggestedAction
        case .handshakeOnly:         return .verify
        default:                     return nil
        }
    }

    @ViewBuilder
    private var inlineFix: some View {
        if let action = fixAction {
            if let note = ConnectActionSite.elsewhereNote(for: action) {
                Label(note, systemImage: "arrow.forward.circle")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                OlcButton(action.title, systemImage: "checkmark.shield",
                          role: .secondary, compact: true, action: onVerify)
                    .padding(.top, 5)
            }
        }
    }

    // MARK: Trailing — live word + the row's action set

    private var trailingColumn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            OlcOverflowMenu(items: menuItems)
            if isLive { liveBadge }
        }
    }

    /// #457: "live" is a WORD plus a glyph, not a colour. It sits on the neutral
    /// fill; the aurora is reserved for the verified spine.
    private var liveBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.caption2)
            Text(L10n.connectRowLive.localized())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(Theme.Palette.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.Palette.fill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.connectRowLive.localized())
    }

    @ViewBuilder
    private var auroraSpine: some View {
        if isLive && display.isVerified {
            Capsule()
                .fill(Theme.Palette.auroraGradient)
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 3)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - ConnectHealthGlyph (#457)
//
// #457: the SHAPE channel of the status vocabulary. `HealthDisplay.tone` returns
// the SAME `.unknown` grey for `.never`, `.fading`, `.inconclusive` and `.stale`
// — four semantically different facts ("never checked", "worked recently",
// "couldn't check", "too old to trust") painted identically. A distinct glyph
// per state is what makes them tell apart without colour at all.
//
// It lives here rather than on `HealthDisplay` so this partition adds no symbol
// to `App/Models/NodeHealth.swift`; fold it in there if that file ever grows a
// `symbol` property.

enum ConnectHealthGlyph {
    static func symbol(for display: HealthDisplay) -> String {
        switch display {
        case .never:         return "questionmark.circle"
        case .checking:      return "arrow.triangle.2.circlepath"
        case .verified:      return "checkmark.circle.fill"
        case .fading:        return "checkmark.circle"          // hollow: past tense
        case .handshakeOnly: return "exclamationmark.triangle.fill"
        case .broken:        return "xmark.octagon.fill"        // octagon ≠ every circle
        case .inconclusive:  return "antenna.radiowaves.left.and.right.slash"
        case .stale:         return "clock.arrow.circlepath"
        }
    }
}
