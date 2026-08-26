import SwiftUI

// MARK: - ConfigView (#301 → #vpn)
//
// The Config tab now owns the tunnel-mode choice: proxy (in-app SOCKS5, the
// default) vs VPN (system-wide packet tunnel via NetworkExtension). The mode
// persists in SettingsStore and is read by TunnelManager.connect at session
// start, so switching is only offered while disconnected — a live session
// can't change backend. The VPN chip grays out with a reason when the
// capability probe (or a failed start) says this install can't do VPN —
// free-Apple-ID re-signing strips the Network Extension entitlement.
// #301's "Coming soon" placeholder is gone; per-app routing rules remain
// future scope.

struct ConfigView: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            List {
                modeSection
                explainerSection
            }
            // (audit #299) paint the ground from the token: without this the
            // List keeps the system grouped background, so the Gray scheme's
            // mid-gray ground (Theme.Palette.bg) never showed on this tab.
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.bg)
            .navigationTitle(L10n.tabConfig.localized())
            // Side-effect free: only reads existing preferences (a past save
            // proves the entitlement) — never pops the system consent alert.
            .task { await tunnel.vpn.probeCapability() }
        }
    }

    // MARK: Mode picker

    private var modeSection: some View {
        Section {
            OlcCard {
                VStack(alignment: .leading, spacing: 12) {
                    OlcChipPicker(selection: $settings.tunnelMode, options: modeOptions)
                        // The mode is read once, at connect time — switching
                        // mid-session would silently not apply, so don't offer
                        // it (dim the whole picker while a session is live;
                        // custom button styles don't dim on .disabled alone).
                        .disabled(tunnel.state != .disconnected)
                        .opacity(tunnel.state == .disconnected ? 1 : 0.55)
                    if case .unavailable(let reason) = tunnel.vpn.capability {
                        Text(L10n.configVPNUnavailableFooter.localized())
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.red)
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            .olcCardRow()
        } header: {
            Text(L10n.configModeSectionHeader.localized())
        }
    }

    /// The VPN chip stays visible but disabled (with a VoiceOver reason) when
    /// the capability gate says this install can't do VPN — same OlcOption
    /// mechanic as the carrier/transport ✗ combos.
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

    // MARK: What the modes mean

    private var explainerSection: some View {
        Section {
            OlcCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.configProxyExplainer.localized())
                    Text(L10n.configVPNExplainer.localized())
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
            }
            .olcCardRow()
        }
    }
}

// #340: both appearance variants.
#if DEBUG
#Preview("Config — Dark") {
    ConfigView(tunnel: TunnelManager()).preferredColorScheme(.dark)
}
#Preview("Config — Light") {
    ConfigView(tunnel: TunnelManager()).preferredColorScheme(.light)
}
#endif
