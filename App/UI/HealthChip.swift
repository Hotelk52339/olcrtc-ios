import SwiftUI

// MARK: - OlcHealthChip (#456)
//
// #456: the ONE evidence chip. Renders a `HealthDisplay` (App/Models/NodeHealth.swift)
// as a compact pill: status dot + short label. Green ONLY for `.verified` —
// every other state is neutral, amber or red, never "looks fine".
//
// It lives here (not in DesignSystem.swift) because it is the only component
// that knows the health vocabulary; the tokens it draws with — `OlcStatusTone`,
// `Theme.Palette` — already exist and are used unchanged. Both the Connections
// rows and the Manage VPS protocol rows render THIS view, so "48 ms · 2m" means
// exactly the same thing on both tabs.

struct OlcHealthChip: View {
    let display: HealthDisplay
    /// When non-nil the chip becomes a button (re-verify on tap).
    var onTap: (() -> Void)? = nil

    var body: some View {
        // #456: tappable and static chips draw the IDENTICAL pill — only the
        // touch target and the a11y traits differ.
        if onTap != nil {
            Button { onTap?() } label: { chip }
                .buttonStyle(.plain)
                // #456: grow the TOUCH region to Apple's 44pt minimum without
                // enlarging the drawn pill (mirrors ConnectionsView.healthButton).
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(.isButton)
        } else {
            chip
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }

    /// The drawn pill. `.checking` swaps the dot for a spinner and carries an
    /// empty label (the spinner IS the message), so the Text is dropped rather
    /// than rendered blank — that keeps the capsule from collapsing to a sliver.
    private var chip: some View {
        HStack(spacing: 5) {
            if display.isChecking {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(display.tone.color)
                    .frame(width: 7, height: 7)
            }
            if !display.chipLabel.isEmpty {
                Text(display.chipLabel)
                    // #456: green text is granted ONLY by `.verified` — the same
                    // rule the dot follows, so colour never outruns the evidence.
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(display.isVerified ? Theme.Palette.green
                                                        : Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.Palette.fill, in: Capsule())
    }

    /// #456: VoiceOver gets the full sentence ("Verified. 48 ms, checked 2m ago"),
    /// not the compressed pill text. Localised at the point of use.
    private var accessibilityText: String {
        "\(display.title). \(display.subtitle)"
    }
}
