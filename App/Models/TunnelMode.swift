import Foundation

// MARK: - TunnelMode (#vpn)
//
// Which backend `TunnelManager.connect(record:)` starts a session through:
//
//   .proxy — the in-app SOCKS5 tunnel (OlcrtcEngine runs the Go core inside
//            the app process; apps opt in by speaking SOCKS to the local
//            port). Works under any signing identity — the default.
//   .vpn   — the system-wide packet tunnel: the NEPacketTunnelProvider appex
//            runs the core and ALL device traffic routes through it. Needs
//            the Network Extension entitlement, which only a paid Apple
//            Developer team signature carries — free-Apple-ID sideloads lose
//            it at re-sign (VPNController.capability gates the UI).
//
// Persisted by rawValue in SettingsStore (`settings.tunnelMode`) and read
// ONCE per session, at connect time — a live session never switches backend.

enum TunnelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case proxy
    case vpn

    var id: String { rawValue }

    /// Picker label in the Config tab.
    var title: String {
        switch self {
        case .proxy: return L10n.tunnelModeProxy.localized()
        case .vpn:   return L10n.tunnelModeVPN.localized()
        }
    }
}
