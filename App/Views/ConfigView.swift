import SwiftUI

// MARK: - Tunnel settings sections (#457, was ConfigView — #301 → #vpn)
//
// #457: the Config TAB is gone. Five tabs became three (Connect / Servers /
// Settings), and a whole tab holding one 2-option picker plus one toggle — while
// nine sibling settings lived in SettingsView — was the clearest possible proof
// it was a section, not a destination. Its two live sections moved here as small
// section views that `SettingsView.tunnelGroup` composes FIRST in the Settings
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
//
// #460: the owner singled that comparison out as the pattern that reads well,
// so it stays exactly as it is, and `TunnelSettingsComparisonRow` / `…Cell` are
// the shape to reuse anywhere else two options have to be compared. The second
// section here is no longer "Reliability" — see `TunnelSettingsOnOpenSection`.
//
// #471 (design pass D): not one cell of that table changed — it moved behind a
// `DisclosureGroup`. It answers a question asked once, and it was the FIRST
// thing in Settings, permanently open. The mode section gained the one fact
// proxy mode is used through: the address, which lives with the port it
// belongs to under Settings › Advanced › Proxy (#474).

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
            // boc #471
            // In proxy mode the port is the ANSWER to "where do I point the
            // other app?", so it is readable here without a push; editing it
            // lives on Settings › Advanced › Proxy, where it is a decision
            // rather than a fact. In VPN mode there is no local listener to
            // point anything at, so the row would be a number that means
            // nothing — it is not drawn.
            // #474 was: `TunnelSettingsPortRow()` — a bare number on the first
            // screen of Settings. What someone pointing another app at the
            // tunnel needs is the whole address, and that now sits with the port
            // it belongs to, under Advanced › Proxy.
            // #471 was: `TunnelSettingsComparison()` mounted directly — a 3×2
            // prose table, six cells, permanently the first thing in Settings,
            // explaining a choice that is made once. The table itself is the
            // pattern the owner singled out as reading well, so not one cell of
            // it changed; it is one tap away instead of always open.
            DisclosureGroup(L10n.tunnelCompareDisclosure.localized()) {
                TunnelSettingsComparison()
            }
            // eoc #471
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
            // #470 was: `disabled: vpnUnavailableReason != nil`. The capability
            // flips to `.unavailable` both when the entitlement is missing AND
            // when the user simply declined the system consent alert — and a
            // declined consent is retryable, but the chip locked them out until
            // relaunch. The reason is still spelled out under the picker
            // (`TunnelSettingsUnavailableNote`) and in VoiceOver.
            OlcOption(value: TunnelMode.vpn, label: TunnelMode.vpn.title,
                      disabled: false,
                      disabledReason: vpnUnavailableReason),
        ]
    }
}

// MARK: - Port summary (#471)


// MARK: - When the app opens (#460, was Reliability / auto-failover — #453)

/// #460 (requirement 26): the RELIABILITY section held two unrelated things —
/// auto-failover between protocols, and "re-check what you own on entry". The
/// failover control moved to the Connections screen, next to the list of
/// protocols it switches between, and must exist in exactly ONE place; the
/// storage did not move (`SettingsStore.autoFailover` is the same value, bound
/// from there now). What is left here is launch behaviour, so the header names
/// that: connect by yourself, and check by yourself.
///
/// #460 was: `TunnelSettingsReliabilitySection` — header `configReliabilityHeader`
/// ("Reliability"), rows `configFailoverToggle` + `configFailoverExplainer`,
/// footer `configFailoverProxyOnlyFooter` ("Applies in proxy mode."). The
/// Connections card re-uses the toggle label and the proxy-only line; the
/// header and the long explainer have no reader left.
struct TunnelSettingsOnOpenSection: View {
    @ObservedObject private var settings = SettingsStore.shared

    /// Explicit (and empty) so the initializer is unambiguously `internal` —
    /// every stored property here is `private`, and SettingsView.swift builds
    /// this from another file.
    init() {}

    var body: some View {
        Section {
            // #460: auto-connect came out of the eight-row "Connection" section
            // (finding 13). It is launch behaviour, and it reads as one subject
            // with the check below it.
            Toggle(L10n.autoConnectOnLaunchLabel.localized(), isOn: $settings.autoConnectOnLaunch)
            TunnelSettingsNote(text: L10n.autoConnectOnLaunchNote.localized())
            // #458: check what you own when the app opens, so the first screen is
            // current instead of showing whatever was true when you last looked.
            Toggle(L10n.settingsRefreshOnEntryToggle.localized(), isOn: $settings.refreshOnEntry)
            TunnelSettingsNote(text: L10n.settingsRefreshOnEntryExplainer.localized())
        } header: {
            Text(L10n.settingsSectionOnOpen.localized())
        }
        // #460: no section footer — each explanation is a note under its own
        // toggle, so nothing can describe a control four rows away (finding 10).
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
                // #471 was: `.font(.footnote)` — a step the six-step scale does
                // not have. The cell's text is untouched (design section C).
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared notes

/// #457: one quiet inline note treatment for the tunnel section — the same
/// guidance voice (footnote, secondary) the rest of Settings uses in its footers.
/// #460: now the treatment for EVERY per-row explanation in Settings. A `Form`
/// footer belongs to its whole section, so an explanation written for one
/// control ended up under an unrelated row (findings 10, 11, 20); a note sits
/// under the control it describes and cannot drift.
struct TunnelSettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            // #471 was: `.font(.footnote)` — not a step on the six-step scale
            // (Theme.swift). This one line renders every per-row explanation in
            // Settings, so it is the single biggest type-scale site in the app.
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}

/// The capability gate's verdict: a red lead-in plus the reason, verbatim from
/// the Config tab's mode section.
struct TunnelSettingsUnavailableNote: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // #471 was: `.font(.footnote)` on both lines — same step swap as
            // `TunnelSettingsNote`, which this note sits beside.
            Text(L10n.configVPNUnavailableFooter.localized())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.red)
            Text(reason)
                .font(Theme.Typography.caption)
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
        TunnelSettingsOnOpenSection()
    }
    .preferredColorScheme(.dark)
}
#Preview("Tunnel settings — Light") {
    Form {
        TunnelSettingsModeSection(tunnel: TunnelManager())
        TunnelSettingsOnOpenSection()
    }
    .preferredColorScheme(.light)
}
#endif
