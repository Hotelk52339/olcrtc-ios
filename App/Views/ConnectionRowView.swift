import SwiftUI

// MARK: - ConnectionRowView (#457, cut down #459)
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
// #457 was: tapping a row called `store.setPrimary` + `Haptics.tap()` and did
// NOT connect — the most natural gesture in the app produced a gold star and a
// buzz and no connection, while "Connect" appeared in the overflow menu only on
// rows that were NOT already primary, i.e. missing on the row you most wanted.
// A tap now CONNECTS (`TunnelManager.connect(record:)` disconnects-then-dials,
// so it is safe from any state); the caller keeps `store.primary` in step as a
// side effect, purely so auto-connect-on-launch still has a record to read.
//
// #459: THE ROW IS TWO LINES. This list is a SWITCHER — the connection the hero
// is about is not in it at all — so a row's whole job is "which node is this,
// and does it work?". It says that in a name, a localized carrier·transport
// line, and ONE `OlcHealthChip`.
//
// #459 was: four lines under the name — `record.subtitle` ("olcrtc · jitsi ·
// datachannel", whose first word is on every row and carries no bits), a
// hand-rolled `verdictLine` (glyph + `display.title`), an `evidenceLine`
// (`display.subtitle`) and, on the live row, a "Live" badge plus an aurora
// spine. The glyph/word/age trio was the SAME three channels `OlcHealthChip`
// already renders — the chip the Manage VPS protocol rows use — so the row was
// re-implementing a shared component beside itself. That duplication IS the
// "lots of unnecessary and repeated details and words" in the brief.
//
// All three channels survive inside the chip: glyph (`OlcHealthGlyph.symbol`),
// word (`chipLabel`, falling back to `display.title`), age. It is already
// grayscale-safe, already wraps to two lines rather than truncating, and its
// 44 pt tap target RE-VERIFIES — which is why the row menu no longer carries a
// "Verify" item either.
//
// `isLive` / `liveBadge` / `auroraSpine` are gone because the live node is
// never in this list: a "Live" badge that can never render is dead code.
//
// A failing row still carries its FIX, and grows to do it. `HealthDisplay
// .suggestedAction` was already computed and simply never rendered, so the key
// mismatch headline was a dead end unless the user thought to open an overflow
// menu. Re-checking runs here; everything else names the screen it lives on
// rather than drawing a button that cannot work (see `ConnectActionSite`).
// Complexity appears only where there is a problem.

struct ConnectionRowView: View {

    let record: ConnectionRecord
    /// The honesty layer's dated verdict for this record.
    let display: HealthDisplay
    /// #337: screenshot-safe IP masking for the subscription meta line.
    let maskIPs: Bool
    let menuItems: [OlcMenuItem]
    /// Tap = connect through this node.
    let onConnect: () -> Void
    /// Tap on the chip, and the inline "Check" / "Retry" on a failing row.
    let onVerify: () -> Void

    var body: some View {
        OlcCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Theme.Metrics.s2) {
                    // #457: a real Button (not an `onTapGesture`) so VoiceOver
                    // gets the button trait and one activatable element, while
                    // the chip and the overflow menu stay their OWN elements
                    // beside it — the old row used `.accessibilityElement(
                    // children: .combine)` on the whole card, which swallowed
                    // both.
                    // #459: no `Spacer` beside it — `infoColumn` already carries
                    // `maxWidth: .infinity`, and two greedy siblings would split
                    // the slack and squeeze the chip into a needless wrap.
                    Button(action: onConnect) { infoColumn }
                        .buttonStyle(.plain)
                        .accessibilityHint(L10n.connectRowTapHint.localized())
                    // #459: the row's WHOLE status vocabulary, and its verify
                    // affordance — the same component the Manage VPS protocol
                    // rows draw, so "48 ms · 2m" means one thing in both places.
                    OlcHealthChip(display: display, onTap: onVerify)
                    OlcOverflowMenu(items: menuItems)
                }
                // #457: OUTSIDE the connect Button. A button nested inside another
                // button does not reliably receive taps and reads as one control
                // to VoiceOver — and this is the control that repairs the node.
                problemBlock
            }
        }
    }

    // MARK: The subject — name, kind, and nothing else

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.displayName)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            // #459 was: `record.subtitle` — "olcrtc · jitsi · datachannel". The
            // protocol word is on every row and the raw ids are the engineering
            // form the connection log wants, not the one a person reads.
            Text(detailLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
            metaLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// #459: the row's HUMAN second line — localized carrier + transport, no
    /// protocol word: "Jitsi · DataChannel". `ConnectionDetails.subtitle` is left
    /// alone because it is the ENGINEERING form ("olcrtc · jitsi · datachannel")
    /// that `ConnectionStore` writes to the connection log, and logs want raw ids.
    ///
    /// The design spec put this on the model as `ConnectionRecord.displayDetail`.
    /// App/Models/ConnectionRecord.swift is outside this change's partition and
    /// the property was not added there, so the derivation lives here; move it
    /// onto the model — and delete this — the next time that file is touched.
    private var detailLine: String {
        switch record.details {
        case .olcrtc(let p):
            return "\(CarrierTransportMatrix.carrierLabel(p.carrier)) · \(CarrierTransportMatrix.transportLabel(p.transport))"
        }
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

    // MARK: The problem, and the fix, offered where the problem is shown

    /// Only states that mean "something is wrong" get the reason spelled out and
    /// a full inline affordance. `.never` / `.stale` also suggest `.verify`, but
    /// on a fresh install EVERY row is `.never` — a block on all of them would be
    /// noise, so those keep the chip (tap = verify) and the pull gesture.
    private var fixAction: HealthAction? {
        switch display {
        case .broken, .inconclusive: return display.suggestedAction
        case .handshakeOnly:         return .verify
        default:                     return nil
        }
    }

    /// #459: the reason and its fix, together, only on a row that has a problem.
    /// The chip beside the name already carries the verdict WORD; what the chip
    /// cannot fit is the sentence — for `.broken` that is `HealthReason.headline`
    /// — which is never truncated (HIG Typography).
    @ViewBuilder
    private var problemBlock: some View {
        if let action = fixAction {
            VStack(alignment: .leading, spacing: 4) {
                Text(display.title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(display.tone.color)
                    .fixedSize(horizontal: false, vertical: true)
                inlineFix(action)
            }
            .padding(.top, Theme.Metrics.s2)
        }
    }

    @ViewBuilder
    private func inlineFix(_ action: HealthAction) -> some View {
        if let note = ConnectActionSite.elsewhereNote(for: action) {
            Label(note, systemImage: "arrow.forward.circle")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            OlcButton(action.title, systemImage: "checkmark.shield",
                      role: .secondary, compact: true, action: onVerify)
        }
    }
}

// boc #459
// #459 was: `enum ConnectHealthGlyph` — a byte-identical copy of
// `OlcHealthGlyph` (App/UI/HealthChip.swift), which existed only to feed this
// row's hand-rolled verdict line. The row draws `OlcHealthChip` now, and the
// chip owns the mapping, so the duplicate is deleted rather than kept in sync.
// eoc #459
