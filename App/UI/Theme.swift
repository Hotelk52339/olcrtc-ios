import SwiftUI
import UIKit  // #340: UIColor trait closures back the dynamic light/dark tokens

// #258: Design-system tokens — the single source of truth for color, spacing,
// shape, and type. App/UI/DesignSystem.swift and (later) every screen read from
// here instead of hardcoding `.controlSize(...)`, ad-hoc hex, or per-call tints.
//
// Values come from design_handoff_ui_redesign (pure-black ground, soft
// borderless cards). Where the handoff's hex matches an iOS system color we use
// the *semantic* color — noted per token — so Dynamic Type, contrast, and the
// dark palette keep working.
// #340 was: "The app is dark-only; this palette is authored for the dark
// appearance" — light values come from design_handoff_logs_theme §4; the
// appearance now follows SettingsStore.appearanceMode via preferredColorScheme
// in App.swift. Semantic system colors adapt for free; the handful of
// hardcoded grounds are dynamic via UIColor traits.
// #299 was: a runtime Refined/Console "design direction" (#267/#281) that only
// changed radii/borders/fonts, never colours. Dropped in favour of a real
// third *colour* scheme — Gray — alongside System/Light/Dark. The metric/type
// tokens are now single (Refined) values; the grounds resolve to neutral
// mid-gray when AppearanceMode is .gray.

enum Theme {

    /// #299: true when the user picked the Gray colour scheme. The hardcoded
    /// grounds below read this so pure-black surfaces become neutral mid-gray.
    fileprivate static var isGray: Bool { SettingsStore.shared.appearanceMode == .gray }

    /// #340: dark/light pair → one Color that resolves per the active trait.
    fileprivate static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: - Colors
    enum Palette {
        // Grounds & surfaces. #340: light values per the handoff §4 token table.
        // #299: Gray uses neutral mid-gray grounds (systemGray6/5) instead of
        // pure black so the whole app reads as a soft dark-gray, not OLED black.
        // #340 was: bg = .black (dark-only)
        static var bg        : Color {
            Theme.isGray
                ? Theme.dynamic(dark: UIColor(hex: 0x1C1C1E), light: UIColor(hex: 0x1C1C1E))   // #299: systemGray6
                : Theme.dynamic(dark: .black, light: .systemGroupedBackground)   // light = #F2F2F7
        }
        static var card      : Color {
            Theme.isGray
                ? Theme.dynamic(dark: UIColor(hex: 0x2C2C2E), light: UIColor(hex: 0x2C2C2E))   // #299: systemGray5
                : Color(.secondarySystemGroupedBackground)
        }
        static let fill      = Color(.tertiarySystemFill)                // rgba(118,118,128,0.22) — secondary-button / chip fill
        // #340 was: segActive = 0x48484A (dark-only); light = white (+ OlcSegmented's soft shadow)
        // #299: Gray reuses the dark segmented fill on its mid-gray ground.
        static var segActive : Color {
            Theme.isGray
                ? Theme.dynamic(dark: UIColor(hex: 0x48484A), light: UIColor(hex: 0x48484A))
                : Theme.dynamic(dark: UIColor(hex: 0x48484A), light: .white)
        }
        /// #340: Console card hairline — was hardcoded `Color.white.opacity(0.16)`
        /// in OlcCard (#281 bumped dark from the handoff's 8% for visibility);
        /// light uses the handoff's black 8%.
        static var cardBorder: Color {
            Theme.dynamic(dark: UIColor.white.withAlphaComponent(0.16),
                          light: UIColor.black.withAlphaComponent(0.08))
        }
        static let separator = Color(.separator)                         // rgba(84,84,88,0.5)

        // Text
        static let textPrimary   = Color.primary           // #FFFFFF
        static let textSecondary = Color.secondary         // rgba(235,235,245,0.62)
        static let textTertiary  = Color(.tertiaryLabel)   // rgba(235,235,245,0.32)

        // Accent + the ONE status vocabulary (unknown = gray, progress = amber,
        // ok = green, warn = orange, error = red), used identically everywhere.
        static let accent = Color.accentColor   // #0A84FF — existing AccentColor asset
        static let green  = Color.green          // #30D158
        // #350 (audit U4) was: amber = Color.yellow (#FFD60A) — ~1.3:1 on light/gray
        // grounds, so the .progress dot and OlcProgressBar fill were near-invisible
        // in Light. Now dynamic: bright yellow on dark, a darker amber on light.
        static let amber  = Theme.dynamic(dark: UIColor(hex: 0xFFD60A), light: UIColor(hex: 0xB8860B))
        static let orange = Color.orange         // #FF9F0A
        static let red    = Color.red            // #FF453A

        // Tinted (weak) fills
        static let redWeak  = Color.red.opacity(0.16)      // danger-button background
        // #350 (audit U4) was: star = Color.yellow (#FFD60A) — same low-contrast
        // problem on the "Main" badge in Light. Dynamic, matching `amber`.
        static let star     = Theme.dynamic(dark: UIColor(hex: 0xFFD60A), light: UIColor(hex: 0xB8860B))
        // (audit) was: Color.yellow.opacity(0.16) — static bright-yellow wash
        // clashed with the dark-amber `star` text on light cards. Dynamic like
        // `star`: bright yellow wash in dark, muted amber wash in light.
        static let starWeak = Theme.dynamic(dark: UIColor(hex: 0xFFD60A).withAlphaComponent(0.16),
                                            light: UIColor(hex: 0xB8860B).withAlphaComponent(0.14))

        // MARK: Aurora signature (#455 premium redesign)
        //
        // The app's own identity: a cyan→violet "aurora" that stands in for the
        // signal travelling through the tunnel. It carries the CONNECTED state
        // and every primary action, so the interface has one memorable colour
        // that isn't the system blue every other app defaults to. Links and
        // neutral controls still use `accent` (system blue) — the aurora is
        // spent only on the connect moment and primary CTAs (frontend-design:
        // "spend your boldness in one place").
        static let signalCyan   = Color(hex: 0x36D8F5)   // near-cyan, high-energy end
        static let signalViolet = Color(hex: 0x8B7BFF)   // soft violet, calm end
        static let signalMid    = Color(hex: 0x5EAEFF)   // blue midpoint (blends toward the system accent)

        /// The signature gradient (top-leading cyan → bottom-trailing violet),
        /// used for the connected hero ring and primary-button fills.
        static let auroraGradient = LinearGradient(
            colors: [signalCyan, signalMid, signalViolet],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// A low-opacity wash of the same gradient for glows and translucent
        /// fills behind glass (never for text/controls — decoration only).
        static let auroraSoft = LinearGradient(
            colors: [signalCyan.opacity(0.22), signalViolet.opacity(0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// Tint for the connected-state glow/shadow (the cyan end reads as
        /// "live" against the dark ground).
        static let connectedGlow = signalCyan
    }

    // MARK: - Elevation (#455)
    //
    // Depth is what separates a flat, templated look from a premium one: content
    // sits at the base, cards lift a little off it, and the hero/floating layer
    // lifts more. These are soft, wide, low-opacity shadows (never hard drops) so
    // the lift reads as light, not as a border. Applied via `.olcShadow(_:)`.
    enum Elevation {
        case none, card, floating, glow

        var color: Color {
            switch self {
            case .none:     return .clear
            case .card:     return Color.black.opacity(0.18)
            case .floating: return Color.black.opacity(0.28)
            case .glow:     return Theme.Palette.connectedGlow.opacity(0.45)
            }
        }
        var radius: CGFloat {
            switch self {
            case .none: return 0
            case .card: return 10
            case .floating: return 22
            case .glow: return 26
            }
        }
        var y: CGFloat {
            switch self {
            case .none: return 0
            case .card: return 4
            case .floating: return 10
            case .glow: return 0   // a glow spreads evenly, it doesn't "fall"
            }
        }
    }

    // MARK: - Metrics (spacing / shape)
    // #299 was: a few tokens branched on the Refined/Console "design direction"
    // (#267/#281). The direction is gone — these are the single Refined values.
    enum Metrics {
        static let controlHeight:   CGFloat = 44   // every button, always
        static let controlRadius:   CGFloat = 13
        static let cardRadius:      CGFloat = 20
        static let cardPadding:     CGFloat = 16
        static let cardBorderWidth: CGFloat = 0
        static let rowMinHeight:    CGFloat = 52
        static let sectionGap:      CGFloat = 22
        static let segmentedRadius: CGFloat = 10
        static let chipHeight:      CGFloat = 34   // handoff range 32–38
    }

    // MARK: - Type
    // Mapped to Dynamic Type text styles (not fixed points) so the app's existing
    // font-size slider — `.dynamicTypeSize(...)` in App.swift — keeps scaling
    // these. Approx. handoff sizes noted in comments.
    // #299 was: statusSubtitle/sectionHeader branched on the Console direction
    // (monospaced) — the direction is gone, so these are the proportional values.
    // #455: the whole scale moved to SF Rounded. Rounded terminals read as
    // warmer and more crafted than the default SF — the single cheapest way to
    // lift the type off "system template" without touching a single call site
    // (they all go through these tokens). Data stays monospaced (`metricValue`)
    // so numbers still align in columns. All still map to Dynamic Type text
    // styles, so the font-size slider keeps scaling everything.
    enum Typography {
        static let display        = Font.system(.largeTitle, design: .rounded).weight(.bold)   // #455: hero numerals/state
        static let largeTitle     = Font.system(.largeTitle, design: .rounded).weight(.bold)   // 32 / 800
        static let button         = Font.system(.callout,    design: .rounded).weight(.semibold)   // ~16 / 600
        static let statusTitle    = Font.system(.subheadline, design: .rounded).weight(.semibold)  // ~15 / 600
        static let statusSubtitle = Font.system(.caption,     design: .rounded)
        static let sectionHeader  = Font.system(.caption,     design: .rounded).weight(.semibold)
        static let chip           = Font.system(.subheadline, design: .rounded).weight(.semibold)  // ~14 / 600
        static let segment        = Font.system(.subheadline, design: .rounded).weight(.semibold)  // ~14 / 600
        static let metricLabel    = Font.system(.caption2,    design: .rounded).weight(.semibold)  // ~11 / 600 (tracked + uppercased)
        static let metricValue    = Font.system(.body, design: .monospaced).weight(.semibold)      // ~17 / 600 mono (data aligns)
    }
}

extension Color {
    /// `0xRRGGBB` literal → opaque sRGB Color. Used only for the handful of tokens
    /// with no iOS system-color equivalent (e.g. the segmented control's active
    /// fill). Prefer a semantic `Color(.xxx)` whenever one matches.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

extension UIColor {
    /// #340: UIColor twin of `Color(hex:)` — the dynamic light/dark tokens are
    /// built from UIColor trait closures, which need UIColor end points.
    convenience init(hex: UInt32) {
        self.init(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8)  & 0xFF) / 255,
                  blue:  CGFloat( hex        & 0xFF) / 255,
                  alpha: 1)
    }
}
