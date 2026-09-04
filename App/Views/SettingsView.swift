import SwiftUI

// MARK: - SettingsView
//
// #457: the THIRD and last tab, ordered by consequence. Surfaces values that
// used to be hardcoded, plus the two sections the deleted Config tab held.
//
// #460 (screenshot findings 10, 11, 13, 20, 21): regrouped BY SUBJECT, and
// every explanation now sits with the control it explains.
//
// The old shape had one "Connection" section carrying a start timeout,
// auto-connect, a VPS-uninstall side effect, a keep-alive interval, background
// audio, a wedge-restart toggle, update checking AND the log level — eight rows,
// three or four subjects, one header. Worse, a `Form` footer belongs to its
// whole SECTION, so the keep-alive explainer rendered four rows below the field
// it describes; "Logs" and "Diagnostics" had the same fault. Two fixes, applied
// everywhere: split a section until its header names ONE subject, and when a
// section legitimately holds several controls, move each explanation to a note
// row directly under its own control (`TunnelSettingsNote`) instead of pooling
// them in a trailing footer. A footer survives only where it explains the whole
// section — or the single row above it.
//
// Section order (top-down by consequence):
//   Tunnel mode · When the app opens | Starting a connection · Staying connected
//   | SOCKS5 · DNS · vp8channel | Servers | IP check · Speed test | Logs
//   | Updates · Appearance | About
//
// #460 was: tunnel · SOCKS5 · DNS · vp8channel · Connection · Bots ·
// Diagnostics · Logs · Appearance · info — ten Form children, which is also the
// ViewBuilder ceiling; the sections are grouped into eight `@ViewBuilder`
// properties so the list can keep growing.
//
// Reads/writes go through SettingsStore.shared, which mirrors UserDefaults.
// SwiftUI rebinds on @Published changes automatically.

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    // #300: live tunnel state, needed to tell "port busy because our tunnel
    // reserved it" apart from "port busy because something else holds it" —
    // the old check compared configured ports only, so it reported "in use
    // by tunnel" even while disconnected. #313: the gate now reads
    // `tunnel.boundPort` — the port the session actually bound — so a live
    // port edit in Settings can't mislabel the check either.
    @ObservedObject var tunnel: TunnelManager
    /// #420: bot registry (shared with Servers). Managed in `BotsSettingsView`.
    @ObservedObject var botStore: BotStore
    /// #457: the two stores the pushed `LogsView(subject: .all)` needs — the
    /// per-server container buffers and the host picker's "primary" star.
    @ObservedObject var serverStore: ServerHostStore
    @ObservedObject var connections: ConnectionStore

    @State private var portCheck: PortAvailability.PortState?
    @State private var socksPassInput: String = ""
    @State private var socksPassLoaded = false
    @FocusState private var anyFieldFocused: Bool


    /// #455: confirm before "Reset all settings" — restores defaults (incl.
    /// tunnel mode → proxy), which unsticks any state that would otherwise
    /// need an app reinstall.
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                // #460: the modifier stack is split across two small wrappers,
                // the idiom ConnectionsView/ServersView adopted after this
                // repo's SwiftUI type-checker failures — no single expression
                // carries the whole chain.
                formWiring(formChrome(settingsForm), proxy: proxy)
            }
        }
    }

    /// Eight children — each one a section or a small group of them. Keep it
    /// under ten: `ViewBuilder` has no eleventh-child overload.
    private var settingsForm: some View {
        Form {
            tunnelGroup
            connectionGroup
            networkGroup
            serversSection
            checksGroup
            logsSection
            appGroup
            infoSection
        }
    }

    private func formChrome(_ content: some View) -> some View {
        content
            // (audit #299) paint the ground from the token: without this the
            // Form keeps the system grouped background, so a non-default scheme
            // never showed Theme.Palette.bg on this tab.
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.bg)
            // #460 (audit fix): the same defect Connections had. Hiding the
            // scroll background and painting our own leaves both system bars on
            // their transparent scroll-edge appearance, so scrolled content draws
            // THROUGH them — a title clipped under the nav bar, the last row cut
            // by the tab bar. Visibility only: each bar keeps its system material,
            // so this tab still looks like the others.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.visible, for: .tabBar)
            // #460: requirement 27 — the same gesture as the other two tabs.
            .refreshable { await refreshSettings() }
            // #457 (was ConfigView's `.task`): side-effect free — only reads
            // existing VPN preferences (a past save proves the entitlement),
            // never pops the system consent alert. Drives the VPN chip's
            // enabled state in the mode section.
            .task { await tunnel.vpn.probeCapability() }
            .onDisappear { socksPassLoaded = false }
    }

    private func formWiring(_ content: some View, proxy: ScrollViewProxy) -> some View {
        content
            // #455: reset-to-defaults confirm (unsticks a wedged state
            // without reinstalling; connections and servers are kept).
            .confirmationDialog(L10n.resetSettingsConfirmTitle.localized(),
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(L10n.resetSettingsAction.localized(), role: .destructive) {
                    SettingsStore.shared.reset()
                    Haptics.success()
                }
                Button(L10n.cancel.localized(), role: .cancel) { }
            } message: {
                Text(L10n.resetSettingsConfirmBody.localized())
            }
            .navigationTitle(L10n.settingsTitle.localized())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.done.localized()) { anyFieldFocused = false }
                }
            }
    }

    // MARK: Pull to refresh (#460)

    /// #460: requirement 27 — "the swipe should refresh everything on whichever
    /// screen I am on". Settings owns no server state, but two things here DO go
    /// stale while the screen is open, and both are re-read for real (no faked
    /// spinner): whether the configured SOCKS port is still free, and whether
    /// this install is allowed to run the system VPN at all — a re-signed
    /// sideload loses that entitlement, and the mode picker's VPN chip is gated
    /// on it. The daily update check is NOT reachable from here: `UpdateChecker`
    /// is owned by MainTabView and never passed down.
    private func refreshSettings() async {
        runPortCheck()
        await tunnel.vpn.probeCapability()
    }

    // MARK: Tunnel (#457 — absorbed from the deleted Config tab)

    /// #457: the Config tab's live sections, now FIRST in Settings. Both bodies
    /// live in ConfigView.swift so this file doesn't grow (SwiftUI type-checker
    /// budget) — see `TunnelSettingsModeSection` / `TunnelSettingsOnOpenSection`.
    /// #460 was: `TunnelSettingsReliabilitySection` — see that file.
    @ViewBuilder
    private var tunnelGroup: some View {
        TunnelSettingsModeSection(tunnel: tunnel)
        TunnelSettingsOnOpenSection()
    }

    // MARK: Connection (#460 — was one section for four subjects)

    @ViewBuilder
    private var connectionGroup: some View {
        startSection
        stayConnectedSection
    }

    // MARK: Network (#460 group: the listener, the resolver, the codec)

    @ViewBuilder
    private var networkGroup: some View {
        socksSection
        dnsRowSection
        transportSection
    }

    // MARK: Checks (#460 — was one "Diagnostics" section; findings 20/21)

    @ViewBuilder
    private var checksGroup: some View {
        ipCheckSection
        speedTestSection
    }

    // MARK: App-level (#460)

    @ViewBuilder
    private var appGroup: some View {
        updatesSection
        appearanceSection
    }

    // MARK: SOCKS

    // #343 was: two sections (port+check / auth) with three stacked footers —
    // one section now.
    // #460: the section footer said "Port change takes effect on the next
    // connection" and rendered under the PASSWORD field whenever auth was on —
    // the same fault as findings 10/11/20, one screen down. Both sentences are
    // notes on their own rows now, and `socksAuthFooter` (written in #343, then
    // left unused when its section was merged away) explains the auth toggle
    // again instead of nothing explaining it.
    @ViewBuilder
    private var socksSection: some View {
        Section {
            HStack {
                Text(L10n.settingsPortLabel.localized())
                Spacer()
                TextField("8808", value: $settings.socksPort, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .focused($anyFieldFocused)
                    .frame(width: 90)
                // #455: design-system button (was a raw `.bordered`/`.small`
                // system button — the only one left on this screen) so it
                // matches every other control and taps with haptic feedback.
                OlcButton(L10n.randomPortAction.localized(), role: .secondary, compact: true) {
                    settings.socksPort = Int.random(in: 1024...65535)
                }
            }
            TunnelSettingsNote(text: L10n.socksPortChangeNote.localized())

            // #460 was: the whole check ran inline in this button's action — it
            // is a method now, so the pull-to-refresh gesture runs exactly the
            // same check instead of a second copy of it.
            Button { runPortCheck() } label: { portCheckLabel }

            Toggle(L10n.localSocksAuthLabel.localized(), isOn: $settings.localSocksAuthEnabled)
            TunnelSettingsNote(text: L10n.socksAuthFooter.localized())
            if settings.localSocksAuthEnabled {
                TextField(L10n.socksUserLabel.localized(), text: $settings.localSocksUser)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField(L10n.socksPassLabel.localized(), text: $socksPassInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onAppear {
                        if !socksPassLoaded {
                            socksPassInput = settings.localSocksPass
                            socksPassLoaded = true
                        }
                    }
                    .onChange(of: socksPassInput) { _, v in
                        settings.localSocksPass = v
                    }
            }
        } header: {
            Text(L10n.sectionSOCKS5.localized())
        }
        // #470: the verdict describes the port that was CHECKED. Typing a new
        // one or tapping "Random port" left "free" / "in use" beside a port
        // nobody had checked — the next connect could then fail with OLC-1026.
        .onChange(of: settings.socksPort) { _, _ in portCheck = nil }
    }

    private var portCheckLabel: some View {
        HStack {
            Image(systemName: "checkmark.circle")
            Text(L10n.checkPortAction.localized())
            Spacer()
            if let r = portCheck {
                switch r {
                // #317: ad-hoc .green/.red → Theme.Palette status tokens (#258 invariant)
                // #317 was: .foregroundStyle(.green) / .foregroundStyle(.red)
                case .free:      Text(L10n.portFree.localized()).foregroundStyle(Theme.Palette.green)
                case .busyOurs:  Text(L10n.portInUseByOlcrtc.localized()).foregroundStyle(Theme.Palette.green)
                case .busyOther: Text(L10n.portBusy.localized()).foregroundStyle(Theme.Palette.red)
                }
            }
        }
    }

    private func runPortCheck() {
        let port = UInt16(settings.socksPort)
        // #313: compare against the port the tunnel actually bound
        // (`tunnel.boundPort`, snapshotted at connect; nil unless a
        // session is live). The #300 gate compared two reads of the
        // *configured* port — always equal — so while connected, any
        // value typed into the field was labeled "in use by olcrtc
        // tunnel" even though the tunnel still holds the old port.
        // #313 was: let tunnelHoldsPort = tunnel.state.isConnected
        //     && TunnelManager.socksPort == settings.socksPort
        let tunnelHoldsPort = tunnel.boundPort == settings.socksPort
        let result = PortAvailability.state(port, tunnelHoldsPort: tunnelHoldsPort)
        portCheck = result
        // #287: one L10n key per concept instead of assembling the line
        // from fragments (which drifted between code paths / languages).
        // #300: three states → three log lines.
        let logLine: String
        switch result {
        case .free:      logLine = L10n.logPortFree_fmt.formatted(settings.socksPort)
        case .busyOther: logLine = L10n.logPortBusyOther_fmt.formatted(settings.socksPort)
        case .busyOurs:  logLine = L10n.logPortBusyOlcrtc_fmt.formatted(settings.socksPort)
        }
        LogStore.shared.log(.connection, logLine)
    }

    // MARK: DNS (#343 — submenu)

    // #343 was: dnsSection — a top-level OlcChipPicker "chip wall" over all
    // presets + the free-form field (the MegaFon/Yota shared value also made
    // duplicate ForEach IDs there). Now a summary NavigationLink row; the
    // presets/footer live in DNSSettingsView, same pattern as the IP sources.
    private var dnsRowSection: some View {
        Section {
            NavigationLink {
                DNSSettingsView()
            } label: {
                HStack {
                    Text(L10n.sectionDNS.localized())
                    Spacer()
                    Text(dnsSummary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// "Yandex · 77.88.8.8:53" when the value matches a preset, else the raw value.
    private var dnsSummary: String {
        let v = settings.dnsServer
        let presets: [(String, String)] = AppConstants.dnsPresets.map { ($0.label, $0.value) }
            + AppConstants.ruCarrierDnsPresets.map { ($0.label.localized(), $0.value) }
        if let hit = presets.first(where: { $0.1 == v }) { return "\(hit.0) · \(v)" }
        return v
    }

    // MARK: Numeric field helper
    //
    // Replaces Stepper. TextField for direct entry + quick-pick row for typical
    // values. Out-of-range entries are auto-clamped by SettingsStore.didSet.

    /// A labelled quick-pick value for the log buffer size stepper row.
    private struct Preset { let value: Int; let label: String }

    @ViewBuilder
    private func numericField(_ title: String,
                               value: Binding<Int>,
                               presets: [Preset],
                               unit: String? = nil,
                               note: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .monospacedDigit()
                .focused($anyFieldFocused)
                .frame(width: 80)
            if let unit { Text(unit).foregroundStyle(.secondary) }
        }
        // #258: design-system chip picker (was a row of .mini bordered buttons).
        OlcChipPicker(selection: value, options: presets.map { ($0.value, $0.label) })
        // #460 (findings 10/11): an explanation that belongs to ONE control
        // renders under that control, not in a section footer four rows down.
        if let note {
            TunnelSettingsNote(text: note)
        }
    }

    // MARK: Transport tuning

    private var transportSection: some View {
        Section {
            numericField(L10n.vp8FpsLabel.localized(), value: $settings.vp8FPS,
                         presets: [Preset(value: 15, label: "15"),
                                   Preset(value: 30, label: "30"),
                                   Preset(value: 60, label: "60")])
            numericField(L10n.vp8BatchLabel.localized(), value: $settings.vp8BatchSize,
                         presets: [Preset(value: 1,  label: "1"),
                                   Preset(value: 8,  label: "8"),
                                   Preset(value: 64, label: "64")])
        } header: {
            Text(L10n.sectionVP8.localized())
        } footer: {
            // #460 (finding 12) was: `vp8Footer`, which opened with the gomobile
            // symbol "MobileSetVP8Options" and the literal "transport=vp8channel".
            // Both rows here are that one subject, so a section footer is still
            // the right place — only the words changed.
            Text(L10n.vp8Note.localized())
                .font(.caption2)
        }
    }

    // MARK: Starting a connection (#460)

    // #460 was: part of one "Connection" section that also held auto-connect,
    // the VPS-uninstall side effect, keep-alive, background audio, the wedge
    // toggle, update checking and the log level (finding 13). One row, one
    // subject, and the footer below it can only mean that row.
    private var startSection: some View {
        Section {
            numericField(L10n.startTimeoutLabel.localized(), value: $settings.startTimeoutSeconds,
                         presets: [Preset(value: 30,  label: "30"),
                                   Preset(value: 60,  label: "60"),
                                   Preset(value: 120, label: "120")],
                         unit: L10n.unitSeconds.localized())   // #455: was hardcoded "s"
        } header: {
            Text(L10n.settingsSectionStart.localized())
        } footer: {
            Text(L10n.startTimeoutNote.localized()).font(.caption2)
        }
    }

    // MARK: Staying connected (#460)

    // #460 (finding 10): `footerKeepAlive` used to be this section's footer and
    // rendered after four unrelated rows AND the log-level picker. It is the
    // same sentence, now attached to the field it describes; the other two rows
    // got the notes they never had.
    private var stayConnectedSection: some View {
        Section {
            numericField(L10n.tunnelCheckLabel.localized(), value: $settings.keepAliveSeconds,
                         presets: [Preset(value: 0,  label: L10n.keepAliveOff.localized()),
                                   Preset(value: 30, label: "30"),
                                   Preset(value: 60, label: "60")],
                         unit: L10n.unitSeconds.localized(),
                         note: L10n.footerKeepAlive.localized())
            // #440: opt-in early restart of a stuck session (off by default).
            Toggle(L10n.earlyRestartWedgeLabel.localized(), isOn: $settings.earlyRestartOnWedge)
            TunnelSettingsNote(text: L10n.earlyRestartWedgeNote.localized())
            Toggle(L10n.backgroundAudioLabel.localized(), isOn: $settings.backgroundAudio)
            TunnelSettingsNote(text: L10n.backgroundAudioNote.localized())
        } header: {
            Text(L10n.settingsSectionStayConnected.localized())
        } footer: {
            // #470: all three rows are in-app-proxy machinery — `TunnelManager`
            // starts keep-alive, the wedge reset and the audio keeper only when
            // `activeMode == .proxy`; in VPN mode the core runs in the appex and
            // none of them ever fires. The Connections failover card already
            // says so with this sentence; these notes promised otherwise.
            Text(L10n.configFailoverProxyOnlyFooter.localized()).font(.caption2)
        }
    }

    // MARK: Servers (#460 — the two settings that are about your VPS list)

    // #460 was: `autoRemoveConnectionOnUninstall` sat under "Connection" (it is
    // a Servers-tab side effect), and Bots was a section of its own holding one
    // link row.
    private var serversSection: some View {
        Section {
            Toggle(L10n.autoRemoveConnectionOnUninstallLabel.localized(),
                   isOn: $settings.autoRemoveConnectionOnUninstall)
            TunnelSettingsNote(text: L10n.autoRemoveOnUninstallNote.localized())
            NavigationLink {
                BotsSettingsView(botStore: botStore)
            } label: {
                HStack {
                    Text(L10n.sectionBots.localized())
                    Spacer()
                    Text("\(botStore.bots.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(L10n.serversTitle.localized())
        }
    }

    // MARK: Logs

    // #343 was: three sections (buffer / container tail / clear-all) with two
    // footers. #460 (finding 11) was: one "Logs" section whose single footer
    // ("Maximum number of lines kept in memory per log category") rendered under
    // the "Clear all logs" BUTTON. Everything here is one subject — logs — so
    // the section stays whole and each explanation moved onto its own row.
    private var logsSection: some View {
        Section {
            // #457: Logs stopped being a tab. This is its unscoped entrance —
            // every OTHER way in is a push from the thing the log explains
            // (a connection attempt, a provisioning run, one server's container).
            // #460 (finding 21) was: `settingsOpenLogsRow` = "Diagnostics and
            // logs" — a third destination sharing the word "Diagnostics" with a
            // Connections card and a Settings section. It opens the log reader,
            // so it says that.
            NavigationLink {
                LogsView(subject: .all, serverStore: serverStore, connections: connections)
            } label: {
                Text(L10n.settingsViewLogsRow.localized())
            }
            Picker(L10n.logLevelLabel.localized(), selection: $settings.logLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            TunnelSettingsNote(text: L10n.logLevelNote.localized())
            numericField(L10n.logBufferLabel.localized(), value: $settings.logBufferSize,
                         presets: [Preset(value: 500,  label: "500"),
                                   Preset(value: 1000, label: "1k"),
                                   Preset(value: 5000, label: "5k")],
                         note: L10n.footerLogBuffer.localized())
            numericField(L10n.containerLogsTailLabel.localized(), value: $settings.containerLogsTailLines,
                         presets: [Preset(value: 100,  label: "100"),
                                   Preset(value: 200,  label: "200"),
                                   Preset(value: 1000, label: "1k")],
                         note: L10n.containerLogsTailNote.localized())
            // #258: danger design-system button (was a plain destructive row).
            OlcButton(L10n.clearAllLogsAction.localized(), systemImage: "trash",
                      role: .danger, fillWidth: true) {
                LogStore.shared.clearAll()
                // #455: the clear is instant and its effect is off-screen (the
                // log reader is a pushed destination since #457), so confirm it fired.
                Haptics.success()
            }
        } header: {
            Text(L10n.sectionLogs.localized())
        }
    }

    // MARK: Updates (#460)

    // #460 was: the update toggle sat in "Connection" with no explanation at
    // all, while `updateCheckFooter` — written for exactly this row — sat unused
    // in the L10n table. Own section, own footer, one row.
    private var updatesSection: some View {
        Section {
            // #360: opt-out of the daily, anonymous GitHub-Releases update check.
            Toggle(L10n.updateCheckLabel.localized(), isOn: $settings.updateCheckEnabled)
        } header: {
            Text(L10n.settingsSectionUpdates.localized())
        } footer: {
            Text(L10n.updateCheckFooter.localized()).font(.caption2)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker(L10n.languageLabel.localized(),
                   selection: Binding(
                    get: { AppLocale(rawValue: settings.language) ?? .english },
                    set: { settings.language = $0.rawValue }
                   )) {
                ForEach(AppLocale.allCases) { locale in
                    Text(locale.displayName).tag(locale)
                }
            }

            // #340: appearance scheme — System / Light / Dark (applied via
            // preferredColorScheme in App.swift). #343: relabeled "Theme" —
            // the section header carries "Appearance" now.
            // #456 was: "+ Gray, a real fourth colour scheme". Gray is gone (a
            // fourth scheme diluted the palette and forced a full TabView rebuild
            // to refresh Theme's tokens); the picker iterates allCases, so it
            // dropped out of this list with the case, and Light is now tuned to
            // be genuinely good rather than a fallback.
            Picker(L10n.themeLabel.localized(), selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            // #470 was: the font-size row, slider and live preview. The app now
            // follows the device's Text Size (iOS › Display & Brightness) instead
            // of duplicating that setting behind a custom slider.
        } header: {
            // #343 was: sectionFont ("Font"). #470: and the font control itself
            // is gone — the section is language + theme.
            Text(L10n.appearanceLabel.localized())
        }
    }

    // MARK: IP check (#460 — half of the old "Diagnostics" section)

    // #460 (findings 20/21) was: one "Diagnostics" section holding IP sources,
    // the speed-test provider AND "Hide IP addresses", with a footer about the
    // SPEED TEST rendering under the IP toggle. Two subjects, two sections; each
    // footer now sits under the row it describes. "Diagnostics" also named a
    // card on Connections and the log-viewer row below — this half is "IP check".
    private var ipCheckSection: some View {
        Section {
            NavigationLink {
                IPSourcesSettingsView()
            } label: {
                HStack {
                    Text(L10n.sectionIPSources.localized())
                    Spacer()
                    Text("\(settings.enabledIPSources.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            // #337: screenshot-safe mode — masks IPs in the Connections
            // diagnostics rows and on VPS cards (display-only; copy + Logs
            // stay real).
            Toggle(L10n.maskIPsLabel.localized(), isOn: $settings.maskIPs)
        } header: {
            Text(L10n.ipCheckTitle.localized())
        } footer: {
            // The IP-sources explanation lives in its own subscreen, so the one
            // footer here belongs to the row directly above it. #460: wires
            // `maskIPsFooter`, which #337 wrote and left unused.
            Text(L10n.maskIPsFooter.localized())
                .font(.caption2)
        }
    }

    // MARK: Speed test (#460 — the other half)

    private var speedTestSection: some View {
        Section {
            Picker(L10n.sectionSpeedProvider.localized(), selection: $settings.speedTestProviderID) {
                ForEach(AppConstants.SpeedTest.providers) { p in
                    Text(Self.providerName(p)).tag(p.id)
                }
            }
            // #460 (finding 19): the picker used to show the provider's `label`,
            // which is a HOSTNAME — a menu picker prints its value on one line,
            // so it arrived clipped ("speed.cl…are.com"). The name identifies the
            // provider; the host is data and gets a full line of its own.
            Text(speedProviderHost)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.settingsSectionSpeedTest.localized())
        } footer: {
            Text(L10n.speedProviderFooter.localized())
                .font(.caption2)
        }
    }

    private var speedProviderHost: String {
        AppConstants.SpeedTest.provider(id: settings.speedTestProviderID).host
    }

    /// #460: display name for a speed-test provider. Two of the three labels
    /// already carry the brand in parentheses ("proof.ovh.net (OVH)"); otherwise
    /// take the host's registrable label ("speed.cloudflare.com" → "Cloudflare").
    /// Derived, not a hardcoded brand table — a new provider needs no change
    /// here, and a brand name is the same word in every language.
    private static func providerName(_ p: SpeedTestProvider) -> String {
        if let open = p.label.firstIndex(of: "("),
           let close = p.label.lastIndex(of: ")"), open < close {
            let inside = p.label[p.label.index(after: open)..<close]
            let trimmed = inside.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        let parts = p.host.split(separator: ".")
        guard parts.count >= 2 else { return p.host }
        let name = String(parts[parts.count - 2])
        return name.prefix(1).uppercased() + String(name.dropFirst())
    }

    // MARK: Info

    private var infoSection: some View {
        Section {
            HStack {
                Text("olcrtc-ios")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appVersion)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // #455: a reset that gets the app out of any wedged state (e.g. a
            // tunnel mode that can't be switched back) without reinstalling.
            OlcButton(L10n.resetSettingsAction.localized(), systemImage: "arrow.counterclockwise",
                      role: .danger, fillWidth: true) {
                showResetConfirm = true
            }
        } footer: {
            Text(L10n.resetSettingsFooter.localized()).font(.caption2)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v).\(b)"
    }
}

// MARK: - IPSourcesSettingsView (#293)
//
// Dedicated sub-screen for the IP-check source checkboxes (moved out of the main
// Settings list, which #286 had crowded). Pushed from the "IP check sources" row;
// the model + default subset + empty-set fallback live in SettingsStore.

struct IPSourcesSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(AppConstants.ipCheckServices, id: \.label) { svc in
                    Toggle(isOn: Binding(
                        get: { settings.enabledIPSources.contains(svc.label) },
                        set: { on in
                            if on { settings.enabledIPSources.insert(svc.label) }
                            else  { settings.enabledIPSources.remove(svc.label) }
                        }
                    )) {
                        Text(svc.label)
                    }
                }
            } footer: {
                Text(L10n.ipSourcesFooter.localized())
                    .font(.caption2)
            }
        }
        // (audit #299) token ground, like the parent Settings Form.
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bg)
        .navigationTitle(L10n.sectionIPSources.localized())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - DNSSettingsView (#343)
//
// DNS presets as rows (name + monospaced address + checkmark) + the free-form
// field, moved off the main Settings list into a subscreen — same pattern as
// IPSourcesSettingsView (#293). The top-level row shows the current summary.

struct DNSSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @FocusState private var fieldFocused: Bool

    // boc #470
    /// The free-form field edits a DRAFT; only a valid `host:port` reaches the
    /// store. Master's `SetDNS` rejects anything else (`validateHostPort`:
    /// net.SplitHostPort, non-empty host, port 1…65535), so a bare "8.8.8.8" or
    /// a trailing space failed EVERY connect with the raw Go error, and
    /// `installEnv` baked the same string into the server's `dns:` line.
    @State private var dnsDraft: String = SettingsStore.shared.dnsServer

    private var dnsDraftBinding: Binding<String> {
        Binding(get: { dnsDraft }, set: { value in
            dnsDraft = value
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isValidResolver(trimmed) { settings.dnsServer = trimmed }
        })
    }

    private var draftIsValid: Bool {
        Self.isValidResolver(dnsDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// PURE: the Go runtime's rule, so the field refuses exactly what the core
    /// would refuse. Tested in Tests/Review470Chunk5Tests.swift.
    static func isValidResolver(_ value: String) -> Bool {
        guard let colon = value.lastIndex(of: ":") else { return false }
        var host = String(value[..<colon])
        let portText = String(value[value.index(after: colon)...])
        if host.hasPrefix("[") {
            guard host.hasSuffix("]") else { return false }
            host = String(host.dropFirst().dropLast())
        } else if host.contains(":") {
            return false   // an unbracketed IPv6 literal — "too many colons" to SplitHostPort
        }
        guard !host.isEmpty, host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let port = Int(portText), (1...65535).contains(port) else { return false }
        return true
    }
    // eoc #470

    /// Global presets + RU-carrier presets (labels localized). Keyed by label
    /// — values are NOT unique (Yota shares MegaFon's resolver).
    private var presets: [(label: String, value: String)] {
        AppConstants.dnsPresets.map { ($0.label, $0.value) }
            + AppConstants.ruCarrierDnsPresets.map { ($0.label.localized(), $0.value) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(presets, id: \.label) { preset in
                    Button {
                        settings.dnsServer = preset.value
                        dnsDraft = preset.value   // #470: the field mirrors the pick
                    } label: {
                        HStack {
                            Text(preset.label)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text(preset.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            if settings.dnsServer == preset.value {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.accent)
                            }
                        }
                    }
                }
            } footer: {
                // The long explanation lives here now, off the main list (#343).
                Text(L10n.dnsFooter.localized())
                    .font(.caption2)
            }

            Section {
                // #470 was: `text: $settings.dnsServer` — every keystroke reached the store.
                TextField(L10n.dnsFreeFormPlaceholder.localized(), text: dnsDraftBinding)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .focused($fieldFocused)
                // #470: the row says WHY the value is not taking effect.
                if !draftIsValid {
                    Text(L10n.dnsInvalidNote.localized())
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.red)
                }
            }
        }
        // (audit #299) token ground, like the parent Settings Form.
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bg)
        .navigationTitle(L10n.sectionDNS.localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.done.localized()) { fieldFocused = false }
            }
        }
    }
}

// MARK: - BotsSettingsView (#420)
//
// Manages the bot registry: list bots (name + platform), add / edit / delete.

struct BotsSettingsView: View {
    @ObservedObject var botStore: BotStore
    @State private var editorBot: BotIdentity?
    @State private var addingNew = false

    var body: some View {
        Form {
            Section {
                if botStore.bots.isEmpty {
                    Text(L10n.botsEmptyHint.localized()).foregroundStyle(.secondary)
                } else {
                    ForEach(botStore.bots) { bot in
                        Button { editorBot = bot } label: {
                            HStack {
                                Text(bot.name).foregroundStyle(Theme.Palette.textPrimary)
                                Spacer()
                                Text(bot.platform.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { botStore.remove(at: $0) }
                }
            } footer: {
                Text(L10n.botsFooter.localized()).font(.caption2)
            }
        }
        // (audit #299) token ground, like the parent Settings Form.
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bg)
        .navigationTitle(L10n.sectionBots.localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L10n.botAddTitle.localized())
            }
        }
        .sheet(item: $editorBot) { bot in
            BotEditorView(botStore: botStore, existing: bot)
        }
        .sheet(isPresented: $addingNew) {
            BotEditorView(botStore: botStore, existing: nil)
        }
    }
}

// MARK: - BotEditorView (#420)
//
// Add / edit one registry bot: name, platform (Telegram first, Max second), and
// token. The token field is masked and paste-only with a Copy button (no reveal).

struct BotEditorView: View {
    @ObservedObject var botStore: BotStore
    var existing: BotIdentity?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var platform: BotPlatform = .telegram
    @State private var token = ""
    @State private var copied = false

    private var isDuplicateName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return botStore.bots.contains {
            $0.id != existing?.id && $0.name.lowercased() == trimmed.lowercased()
        }
    }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDuplicateName
    }
    private var hasAnyToken: Bool {
        !token.isEmpty || (existing.map { botStore.hasToken($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormField(label: L10n.botNameLabel.localized(),
                              placeholder: L10n.botNamePlaceholder.localized(), text: $name)
                    if isDuplicateName {
                        Text(L10n.botNameTakenError.localized())
                            .font(.caption).foregroundStyle(Theme.Palette.red)
                    }
                    Picker(L10n.botPlatformLabel.localized(), selection: $platform) {
                        ForEach(BotPlatform.allCases) { p in Text(p.title).tag(p) }
                    }
                }
                Section {
                    // Masked, paste-only token field — no reveal (a screenshot
                    // shows only dots). Copy retrieves it without displaying it.
                    SecureField(L10n.botTokenPlaceholder.localized(), text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if token.isEmpty {
                        Text((existing.map { botStore.hasToken($0) } ?? false)
                             ? L10n.botTokenSavedHint.localized()
                             : L10n.botTokenNoneHint.localized())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { copyToken() } label: {
                        Label(copied ? L10n.botTokenCopied.localized()
                                     : L10n.botCopyTokenAction.localized(),
                              systemImage: "doc.on.doc")
                    }
                    .disabled(!hasAnyToken)
                } header: {
                    Text(L10n.botTokenLabel.localized())
                } footer: {
                    // #428: tell the user the token comes from the platform first.
                    Text(L10n.botTokenCreateHint.localized()).font(.caption2)
                }
            }
            .navigationTitle(existing == nil ? L10n.botAddTitle.localized()
                                             : L10n.botEditTitle.localized())
            .navigationBarTitleDisplayMode(.inline)
            .olcSheet(confirm: L10n.save.localized(), disabled: !isValid) { save() }
            .onAppear { prefill() }
        }
    }

    private func copyToken() {
        let value = token.isEmpty ? (existing.map { botStore.token(for: $0) } ?? "") : token
        guard !value.isEmpty else { return }
        UIPasteboard.general.string = value
        copied = true
    }

    private func save() {
        var bot = existing ?? BotIdentity(name: "", platform: .telegram)
        bot.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        bot.platform = platform
        if existing == nil {
            botStore.add(bot, token: token)
        } else {
            botStore.update(bot, token: token.isEmpty ? nil : token)
        }
        dismiss()
    }

    private func prefill() {
        guard let e = existing else { return }
        name = e.name
        platform = e.platform
        // Token left blank: paste to replace, blank keeps the stored one.
    }
}

// #340: both appearance variants.
#if DEBUG
#Preview("Settings — Dark") {
    SettingsView(tunnel: TunnelManager(), botStore: BotStore(),
                 serverStore: ServerHostStore(), connections: ConnectionStore())
        .preferredColorScheme(.dark)
}
#Preview("Settings — Light") {
    SettingsView(tunnel: TunnelManager(), botStore: BotStore(),
                 serverStore: ServerHostStore(), connections: ConnectionStore())
        .preferredColorScheme(.light)
}
#endif
