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
//
// #458: …and the row now KEEPS that promise in every state that makes one. The
// `.never` verdict's hint read "Tap Verify to push a real request through this
// connection" while `fixAction` deliberately returned nil for `.never` — so the
// sentence named a button the screen refused to draw, which is this release's
// own dishonesty rule inverted. Two changes here (the third is the wording, in
// App/Models/NodeHealth.swift):
//   • the verdict block is a Verify BUTTON in its own right, 44pt tall, and a
//     sibling of the connect button instead of part of its label — tapping the
//     words "Not checked yet" used to dial the node rather than check it;
//   • every state whose suggested action can be honoured on this screen draws
//     that action by name, `.never` and `.stale` included.

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
    /// Re-probe this node. #458 was: "the inline affordance on a FAILING row" —
    /// it is the verdict block's own action now, on every row.
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
                // #458: the verdict moved in here too — it is a control now, not
                // a caption (see `healthBlock`).
                healthBlock
                elsewhereNote
            }
        }
        // #457: the aurora is a VERDICT, not a style — the spine appears only on
        // the node carrying traffic AND only while its proof is still fresh.
        // Connected-but-unverified draws nothing, which is the whole point.
        .overlay(alignment: .leading) { auroraSpine }
    }

    // MARK: The subject + its evidence

    /// #458 was: this column also held `verdictLine` + `evidenceLine`, i.e. the
    /// health verdict was part of the CONNECT button's label. Tapping the words
    /// "Not checked yet" dialled the node instead of checking it. The verdict is
    /// its own control now (`healthBlock`); this button carries only the subject.
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

    // MARK: The verdict — and the fix, offered where the failure is shown

    /// #458: the verdict is a CONTROL, not a caption.
    ///
    /// The regression it repairs: `.never`'s own hint told the owner to "Tap
    /// Verify", `HealthDisplay.suggestedAction` returned `.verify` for it — and
    /// `fixAction` below deliberately answered nil, so the row printed the name
    /// of a button it refused to draw. Prose promising a control that is not on
    /// screen is the same class of dishonesty as a green dot with no evidence
    /// behind it, only inverted.
    ///
    /// Now the whole verdict block — glyph, word, dated evidence and the named
    /// action pill — is ONE button running the same probe as the row menu's
    /// "Verify", and it is a sibling of the connect button rather than nested
    /// inside it (a button inside a button does not reliably receive taps).
    private var healthBlock: some View {
        Button(action: onVerify) { healthLabel }
            .buttonStyle(.plain)
            // A probe already in flight has nothing to re-trigger.
            .disabled(display.isChecking)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(healthAccessibilityLabel)
            .accessibilityHint(L10n.connectRowVerifyHint.localized())
            .accessibilityAddTraits(.isButton)
    }

    private var healthLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            verdictLine
            evidenceLine
            actionPill
        }
        // #458: Apple's 44pt minimum, met by the TOUCH region — the drawn text
        // keeps its own size, so nothing is scaled down to reach it (HIG:
        // Layout → tap targets). Full row width for the same reason.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.top, 4)
    }

    /// #458: VoiceOver reads the verdict as one sentence — the pairing
    /// `OlcHealthChip` already uses. Localised at the point of use.
    private var healthAccessibilityLabel: String {
        "\(display.title). \(display.subtitle)"
    }

    /// #458 was: only `.broken` / `.inconclusive` / `.handshakeOnly` returned an
    /// action here, on the reasoning that a button on every unchecked row would
    /// be noise — which left `.never` and `.stale` naming an invisible button.
    /// Every state that suggests an action now offers it; `.checking` is the one
    /// silent state, because a probe is already running.
    ///
    /// `HealthDisplay.suggestedAction` itself is UNCHANGED — `ServersView`'s
    /// `carrierMenuItems` branches on it and `HealthModelTests` pins it.
    private var fixAction: HealthAction? {
        switch display {
        case .checking:      return nil
        // `.handshakeOnly` records no reason (the transport DID come up), so
        // `suggestedAction` is nil for it — but re-probing is exactly its fix.
        case .handshakeOnly: return .verify
        default:             return display.suggestedAction
        }
    }

    /// The part of `fixAction` this screen can actually honour: verify / retry.
    private var localAction: HealthAction? {
        guard let action = fixAction,
              ConnectActionSite.elsewhereNote(for: action) == nil else { return nil }
        return action
    }

    /// #458: the named affordance, drawn INSIDE `healthBlock`'s button rather
    /// than as its own — one control, one target, no nested buttons.
    @ViewBuilder
    private var actionPill: some View {
        if let action = localAction {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield")
                Text(action.title)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.Palette.fill, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.Palette.fillBorder, lineWidth: 1) }
            .padding(.top, 2)
        }
    }

    /// #457 (unchanged): when the fix lives on another screen the row NAMES that
    /// screen instead of drawing a button that cannot run here.
    @ViewBuilder
    private var elsewhereNote: some View {
        if let action = fixAction, let note = ConnectActionSite.elsewhereNote(for: action) {
            Label(note, systemImage: "arrow.forward.circle")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
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
