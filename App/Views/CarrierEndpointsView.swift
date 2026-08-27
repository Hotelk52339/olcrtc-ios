import SwiftUI

// MARK: - CarrierEndpointsView (#406 — was #328's inline Connections card)
//
// Opened from Connections → Diagnostics → "Using another proxy app?" while a
// tunnel is up (#460 was: a row titled "Carrier endpoints", which named the
// mechanism rather than the situation, so nobody could tell whether it applied
// to them). Shows the carrier base host (derived from the connection params) plus its
// freshly-resolved IP(s) — the endpoints an external proxy app (Shadowrocket
// etc.) must route DIRECT so the olcrtc tunnel's own carrier traffic doesn't
// loop back through the SOCKS port. Copy the host, an IP, or host + all IPs.
//
// #406 was: an always-on Section in ConnectionsView that appeared the instant
// the tunnel connected and shifted the whole screen. The exclusions are debug
// info, not a permanent fixture, so they now live behind this on-demand sheet,
// which owns its own resolve state (IPs rotate, so it re-resolves on demand).
//
// Accuracy honesty (unchanged from #328): Mobile.objc.h exposes no live ICE /
// STUN / TURN endpoints, so this is the carrier base host + a resolver pass, a
// best-effort hint — not the addresses the running session actually negotiated.

struct CarrierEndpointsView: View {
    let params: OlcrtcConnection
    @Environment(\.dismiss) private var dismiss

    @State private var ips: [String] = []
    @State private var resolving = false

    /// nil when the carrier's roomID is an opaque ID, not a host (telemost /
    /// wbstream) — there's then nothing to exclude.
    private var host: String? { CarrierEndpoints.baseHost(for: params) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // #460 (finding 23): say WHO this screen is for and WHAT
                    // breaks without it, before showing a list of addresses.
                    // Reached from a row on the main screen, it previously
                    // opened straight onto raw hosts and IPs with one line of
                    // insider shorthand underneath them.
                    leadIn
                    if let host {
                        OlcCard {
                            VStack(alignment: .leading, spacing: 12) {
                                endpointRow(label: L10n.carrierEndpointHost.localized(), value: host)
                                Divider().overlay(Theme.Palette.separator)
                                resolvedIPsRow(host: host)
                                Divider().overlay(Theme.Palette.separator)
                                // #406: copy the host + every resolved IP at once.
                                OlcButton(L10n.carrierEndpointCopyAll.localized(),
                                          systemImage: "doc.on.doc.fill",
                                          role: .secondary, fillWidth: true) {
                                    copyAll(host: host)
                                }
                                .disabled(resolving)
                            }
                        }
                    } else {
                        OlcCard {
                            Text(L10n.carrierEndpointNoHost.localized())
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    // #460 was: `carrierEndpointsHint` — "Add these as DIRECT
                    // rules in your proxy app so its own traffic doesn't loop
                    // through olcrtc." The instruction survives (it moved up
                    // into `leadIn`, where it can be read before the list); the
                    // footnote now carries the thing the list itself cannot say
                    // — that these addresses expire.
                    Text(L10n.carrierEndpointsFootnote.localized())
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Theme.Palette.bg)
            // #460 was: `carrierEndpointsTitle` ("Carrier endpoints") — the
            // vocabulary of the person who built it, not of the person who needs
            // it. The title now names the action the screen exists to support.
            .navigationTitle(L10n.carrierEndpointsScreenTitle.localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.closeAction.localized())
                }
            }
        }
        // IPs rotate, so resolve on appear; the row offers a re-resolve too.
        .task { if let host, ips.isEmpty { await resolve(host) } }
    }

    /// #460: the "is this screen for me?" paragraph. Plain prose, no card — it is
    /// read once and then ignored by everyone whose phone has only olcrtc on it.
    private var leadIn: some View {
        Text(L10n.carrierEndpointsLead.localized())
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    /// One copyable endpoint: label + monospaced value + a copy button.
    private func endpointRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            copyButton { copy(value) }
        }
    }

    /// The resolved-IPs row: a re-resolve action + each IP copyable.
    @ViewBuilder
    private func resolvedIPsRow(host: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.carrierEndpointResolvedIPs.localized())
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Button(L10n.carrierEndpointRefresh.localized()) {
                    Task { await resolve(host) }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
                .disabled(resolving)
            }
            if resolving {
                Text(L10n.carrierEndpointResolving.localized())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else if ips.isEmpty {
                Text(L10n.carrierEndpointUnresolved.localized())
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                ForEach(ips, id: \.self) { ip in
                    HStack(spacing: 8) {
                        Text(ip)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        copyButton { copy(ip) }
                    }
                }
            }
        }
    }

    private func copyButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.copyURIAction.localized())
    }

    /// Copies one value (host or IP) and logs it.
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        Haptics.success()   // #455: copy confirmation
        LogStore.shared.log(.connection, L10n.carrierEndpointCopied_fmt.formatted(value))
    }

    /// Copies the host plus every resolved IP, newline-separated, in one action.
    private func copyAll(host: String) {
        let all = ([host] + ips).joined(separator: "\n")
        UIPasteboard.general.string = all
        Haptics.success()   // #455: copy confirmation
        LogStore.shared.log(.connection, L10n.carrierEndpointCopied_fmt.formatted(host))
    }

    /// Resolves the carrier base host's current IPs (DNS pass). Re-runnable.
    private func resolve(_ host: String) async {
        guard !resolving else { return }
        resolving = true
        ips = await CarrierEndpoints.resolve(host: host)
        resolving = false
    }
}
