import SwiftUI

// MARK: - Tunnel settings sections (#457, was ConfigView — #301 → #vpn)
//
// #457: the Config TAB is gone. Five tabs became three (Connect / Servers /
// Settings), and a whole tab holding one 2-option picker plus one toggle — while
// nine sibling settings lived in SettingsView — was the clearest possible proof
// it was a section, not a destination. Its two live sections moved here as small
// section views that `SettingsView.tunnelSection` composes FIRST in the Settings
// form: this is the most consequential setting in the app (it changes what the
// word "Connected" MEANS — one SOCKS port versus the whole device), so it leads.
//
// Behaviour is UNCHANGED from the Config tab: the mode persists in SettingsStore
// and is read once by TunnelManager.connect at session start, so switching is
// only offered while no session is live; the VPN chip grays out with a reason
// when the capability probe (or a failed start) says this install can't do VPN —
// free-Apple-ID re-signing strips the Network Extension entitlement.
//
// #457 was: `struct ConfigView` (a NavigationStack + List + `.navigationTitle
// (L10n.tabConfig)`) and its `explainerSection` — two ARCHITECTURE paragraphs
// ("a local SOCKS5 server inside the app…", "a system-wide tunnel via a Network
// Extension…"). Replaced by `TunnelSettingsComparison`: three consequence rows
// written for the user, not for the implementer.

// MARK: - Mode picker

/// #457: proxy-vs-VPN, moved out of the deleted Config tab. The card wrapper and
/// `.olcCardRow()` chrome are dropped so it renders as a native Settings row —
/// one container idiom per screen, and SettingsView is a `Form`.
struct TunnelSettingsModeSection: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var settings = SettingsStore.shared

    /// #455: a live session (not merely "not disconnected") — the only state in
    /// which the tunnel-mode switch must be locked. `.failed` is deliberately
    /// NOT live, so a refused VPN start doesn't trap the user on VPN mode.
    private var sessionLive: Bool {
        tunnel.state.isConnected || tunnel.state.isConnecting || tunnel.state == .waitingForNetwork
    }

    var body: some View {
        Section {
            // The mode is read once, at connect time — switching mid-session
            // would silently not apply, so don't offer it (dim the whole picker
            // while a session is live; custom button styles don't dim on
            // `.disabled` alone).
            OlcChipPicker(selection: $settings.tunnelMode, options: modeOptions)
                .disabled(sessionLive)
                .opacity(sessionLive ? 0.55 : 1)
            // #457: say WHY it is dimmed instead of leaving the user to discover
            // it by tapping.
            if sessionLive {
                TunnelSettingsNote(text: L10n.tunnelModeLockedNote.localized())
            }
            if case .unavailable(let reason) = tunnel.vpn.capability {
                TunnelSettingsUnavailableNote(reason: reason)
            }
            TunnelSettingsComparison()
        } header: {
            Text(L10n.configModeSectionHeader.localized())
        }
    }

    /// The VPN chip stays visible but disabled (with a VoiceOver reason) when
    /// the capability gate says this install can't do VPN — same OlcOption
    /// mechanic as the carrier/transport combos.
    private var modeOptions: [OlcOption<TunnelMode>] {
        var vpnUnavailableReason: String?
        if case .unavailable(let reason) = tunnel.vpn.capability {
            vpnUnavailableReason = reason
        }
        return [
            OlcOption(value: TunnelMode.proxy, label: TunnelMode.proxy.title),
            OlcOption(value: TunnelMode.vpn, label: TunnelMode.vpn.title,
                      disabled: vpnUnavailableReason != nil,
                      disabledReason: vpnUnavailableReason),
        ]
    }
}

// MARK: - Reliability / auto-failover (#453)

/// #453 + #457: auto-failover between protocols on one server. Moved verbatim
/// out of the Config tab; only the card wrapper is gone (see above).
struct TunnelSettingsReliabilitySection: View {
    @ObservedObject private var settings = SettingsStore.shared

    /// Explicit (and empty) so the initializer is unambiguously `internal` —
    /// every stored property here is `private`, and SettingsView.swift builds
    /// this from another file.
    init() {}

    var body: some View {
        Section {
            Toggle(L10n.configFailoverToggle.localized(), isOn: $settings.autoFailover)
            TunnelSettingsNote(text: L10n.configFailoverExplainer.localized())
        } header: {
            Text(L10n.configReliabilityHeader.localized())
        } footer: {
            Text(L10n.configFailoverProxyOnlyFooter.localized())
                .font(.caption2)
        }
    }
}

// MARK: - What the two modes mean FOR THE USER (#457)

/// #457: three consequence rows instead of two architecture paragraphs. Each row
/// is one question the user actually has, answered for both modes side by side,
/// so the choice is made by comparing outcomes rather than by parsing prose.
struct TunnelSettingsComparison: View {
    /// One question plus its two answers. `id` is a stable literal, not a UUID —
    /// the list is rebuilt on every body pass.
    private struct Line: Identifiable {
        let id: String
        let question: String
        let proxy: String
        let vpn: String
    }

    private var lines: [Line] {
        [
            Line(id: "scope",
                 question: L10n.tunnelCompareScope.localized(),
                 proxy: L10n.tunnelCompareScopeProxy.localized(),
                 vpn: L10n.tunnelCompareScopeVPN.localized()),
            Line(id: "needs",
                 question: L10n.tunnelCompareNeeds.localized(),
                 proxy: L10n.tunnelCompareNeedsProxy.localized(),
                 vpn: L10n.tunnelCompareNeedsVPN.localized()),
            Line(id: "runs",
                 question: L10n.tunnelCompareRuns.localized(),
                 proxy: L10n.tunnelCompareRunsProxy.localized(),
                 vpn: L10n.tunnelCompareRunsVPN.localized()),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(lines) { line in
                TunnelSettingsComparisonRow(question: line.question,
                                            proxyLabel: TunnelMode.proxy.title,
                                            proxyValue: line.proxy,
                                            vpnLabel: TunnelMode.vpn.title,
                                            vpnValue: line.vpn)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One comparison row: the question, then the two answers. Restacks vertically at
/// accessibility sizes — a fixed two-column HStack squeezes both answers to
/// nothing at AX3 (HIG Typography: keep the hierarchy, change the layout).
struct TunnelSettingsComparisonRow: View {
    let question: String
    let proxyLabel: String
    let proxyValue: String
    let vpnLabel: String
    let vpnValue: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { cells }
            } else {
                HStack(alignment: .top, spacing: 14) { cells }
            }
        }
    }

    @ViewBuilder
    private var cells: some View {
        TunnelSettingsComparisonCell(mode: proxyLabel, value: proxyValue)
        TunnelSettingsComparisonCell(mode: vpnLabel, value: vpnValue)
    }
}

/// One answer: the mode's own name over the consequence, so the column is
/// labelled in place and never read from a header two rows up.
struct TunnelSettingsComparisonCell: View {
    let mode: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mode)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared notes

/// #457: one quiet inline note treatment for the tunnel section — the same
/// guidance voice (footnote, secondary) the rest of Settings uses in its footers.
struct TunnelSettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}

/// The capability gate's verdict: a red lead-in plus the reason, verbatim from
/// the Config tab's mode section.
struct TunnelSettingsUnavailableNote: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.configVPNUnavailableFooter.localized())
                .font(.footnote)
                .foregroundStyle(Theme.Palette.red)
            Text(reason)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

// #340: both appearance variants. #457 was: previews of the whole ConfigView
// screen — the sections now render inside SettingsView's Form.
#if DEBUG
#Preview("Tunnel settings — Dark") {
    Form {
        TunnelSettingsModeSection(tunnel: TunnelManager())
        TunnelSettingsReliabilitySection()
    }
    .preferredColorScheme(.dark)
}
#Preview("Tunnel settings — Light") {
    Form {
        TunnelSettingsModeSection(tunnel: TunnelManager())
        TunnelSettingsReliabilitySection()
    }
    .preferredColorScheme(.light)
}
#endif
