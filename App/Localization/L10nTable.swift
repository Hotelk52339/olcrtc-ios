import Foundation

// MARK: - L10nTable
//
// Per-language translation dictionaries. Every key in `L10n` must appear in
// every dictionary — the unit test in `L10nTests.swift` enforces this.
//
// Missing translations fall back to English; missing in English too falls back
// to the case's raw name (which makes the gap visible without crashing).

enum L10nTable {

    static func value(for key: L10n, in locale: AppLocale) -> String {
        switch locale {
        case .english: return english[key] ?? key.rawValue
        case .russian: return russian[key] ?? english[key] ?? key.rawValue
        }
    }

    // MARK: English (canonical / fallback)

    static let english: [L10n: String] = [
        // Common
        .ok:                "OK",
        .cancel:            "Cancel",
        .save:              "Save",
        .close:             "Close",
        .done:              "Done",
        .error:             "Error",
        .edit:              "Edit",
        .okPrompt:          "Result",   // #457 was: "Done" — this titles failures too

        // Tabs
        .tabConnections:    "Connections",
        // #457 was: "Manage VPS" — the app called one place three names ("Manage
        // VPS" here, "VPS list" as the screen title, "the Servers tab" inside
        // `healthActionOnServersTab_fmt`), so a suggested fix pointed at a tab
        // that did not exist under that name. One noun: server.
        .tabServers:        "Servers",
        .tabSettings:       "Settings",
        .autoDetectedContainer_fmt: "Auto-detected existing container: %@",

        // Tunnel mode (#vpn)
        .tunnelModeProxy:           "Proxy",
        .tunnelModeVPN:             "VPN",
        .configModeSectionHeader:   "Tunnel mode",
        .configVPNUnavailableFooter: "VPN mode is unavailable on this install:",
        // #461 was: "videochannel" — the raw id. Every picker names it "Video".
        .vpnVideochannelUnsupported: "The Video transport is not supported in VPN mode. Switch the connection to another transport, or use proxy mode.",
        .vpnDisconnected:           "VPN tunnel disconnected",
        .vpnSettingsEntryName:      "OlcRTC",
        .vpnCapabilityUnavailable_fmt: "The system rejected the VPN configuration (%@). This happens when VPN access was declined, or when the app was signed with a free Apple ID — the Network Extension entitlement requires a paid Apple Developer team. Proxy mode still works.",

        // #453: auto-failover. #460: the control lives on the Connections
        // screen now, so these two are the card's title and its condition line.
        // #460 was: `.configFailoverExplainer` — "If the active protocol stops
        // responding, automatically switch to another protocol running on the
        // same server." Replaced by the one-line `connectAutoSwitchHint`.
        .configFailoverToggle:       "Auto-switch protocols",
        .configFailoverProxyOnlyFooter: "Applies in proxy mode.",
        .settingsRefreshOnEntryToggle:  "Check on opening",
        .settingsRefreshOnEntryExplainer: "When you open the app, re-check your servers and every protocol on them, so what you see is current. Anything checked in the last couple of minutes is left alone.",
        .failoverSwitching_fmt:      "Protocol %@ is failing — switching to %@",
        .failoverAllFailed:          "All protocols on this server failed",
        // #454/#459: the health card is now the "This session" block of the
        // Diagnostics card, so it no longer has a title, a throughput row or a
        // refresh glyph of its own.
        .healthProtocolLabel:        "Protocol",
        .healthExitLabel:            "Exit",
        // #460 was: `.healthLatencyLabel` ("Latency") — see `diagResponseLabel`.
        .healthLatencyMs_fmt:        "%d ms",
        .healthLocationUnknown:      "Location unknown",
        // #455: premium redesign editorial additions
        // #461 was: "Telemost … (vp8channel only) … datachannel … WBStream" —
        // three raw ids and a carrier spelled unlike its own label, in the
        // footer under the picker that shows all four as words.
        .carrierChoiceFooter:        "Yandex Telemost is the hardest to block (VP8 only). Jitsi with DataChannel is the fastest and most stable. WB Stream needs an account token.",
        // #460 was: `.configReliabilityHeader` ("Reliability") — its section
        // held only the auto-switch toggle, which moved to Connections.
        .unitSeconds:                "s",
        .sshTestInvalidPort:         "Invalid port",
        .sshTestReachable_fmt:       "Reachable (%@)",
        .sshTestUnreachable:         "Unreachable",
        .logLevelOff:                "Off",
        .logLevelErrors:             "Errors only",
        .logLevelNormal:             "Normal",
        .logLevelDebug:              "Debug",
        .logLevelVerbose:            "Verbose (all)",
        // #455: reset-to-defaults
        .resetSettingsAction:        "Reset all settings",
        .resetSettingsFooter:        "Restores every setting to its default, including the tunnel mode. Your connections and servers are kept.",
        .resetSettingsConfirmTitle:  "Reset all settings?",
        .resetSettingsConfirmBody:   "Every setting returns to its default, including the tunnel mode. Connections and servers are not affected.",

        // Routing
        .routingHeader:     "Routing",
        .routingAllTunnel:  "All through tunnel",
        .routingAllDirect:  "All direct",
        .routingViaTunnel:  "via tunnel",
        .routingDirect:     "direct",

        // Connection state
        .stateDisconnected: "Disconnected",
        .stateConnecting:   "Connecting…",
        .stateConnected:    "Connected",
        .stateConnectFailed: "Connection failed",
        .stateWaitingForNetwork: "Waiting for network…",
        .stateErrorPrefix_fmt: "Error: %@",

        // ConnectionsView
        .emptyNoConnections:         "No connections yet",
        // #303 was: "Tap + to add a connection manually. If you have a VPS, go to the Servers tab to install and link automatically."
        .emptyNoConnectionsHint:     "A connection is one route out — one protocol on one of your servers.",
        .actionConnect:              "Connect",
        .actionRetry:                "Retry",
        .shareAction:                "Share",
        .copyURIAction:              "Copy URI",
        .shareConnectionTitle:       "Share connection",
        .shareConnectionExplanation: "Share this URI to let others connect through your server. It contains the carrier, room ID, and encryption key — your server SSH credentials are not included.",
        .shareConnectionURIHeader:   "Connection URI",
        .copiedURI_fmt:              "📋 URI copied: %@",
        // #135: full-access (co-admin) share
        .shareFullAccessTitle:       "Share full access (SSH)",
        .shareFullAccessHeader:      "Full access (SSH)",
        .shareFullAccessWarning:     "This link contains your SSH login and password. Anyone with it can fully control this VPS — install, reconfigure, reboot, or wipe it. Share only with someone you trust to co-administer the server.",
        .shareFullAccessReveal:      "Reveal full-access link",
        .shareFullAccessCopy:        "Copy full-access link",
        .shareFullAccessCopied_fmt:  "🔑 Full-access link copied: %@",
        // #366
        .fullAccessImportTitle:      "Import full access?",
        .fullAccessImportBody_fmt:   "This link grants full SSH control of the VPS “%@” — its address, login and password will be saved on this device. Only import links you trust.",
        .fullAccessImportAddAction:  "Add full access",
        .fullAccessImportInvalid:    "This full-access link is invalid.",

        // AddConnectionView
        .newConnectionTitle:         "New connection",
        .editConnectionTitle:        "Edit connection",
        .nameField:                  "Label",
        .namePlaceholder:            "My server",
        .groupField:                 "Group",
        // #344 was: "Servers" — the Connections tab lists *connections*, not
        // servers (display-only; the persisted raw group value stays "Servers"
        // and is mapped via ConnectionRecord.displayGroupName).
        .groupDefault:               "Connections",
        .importByURI:                "Import from URI",
        .scanQRAction:               "Scan QR",
        .pasteURIAction:             "Paste URI",
        // #458 was: "Tap Paste …" — the button above reads "Paste URI"; a hint may
        // only use a control's OWN name (audit: every named control must exist).
        .importHint:                 "Tap Paste URI to import a URI or a subscription from the clipboard, or Scan QR. The fields below fill in automatically.", // #381 was: "If you have a URI from the server — paste it here and tap «Parse». The fields below will be filled in automatically." — buttons are Scan QR / Paste (Paste also imports subscriptions since #361), there is no "Parse" button.
        .clientIDFooter:             "Your device identifier in the room. 'default' works for single-device setups. Use a unique value when multiple devices share the same room.",
        .keyPlaceholder:             "64-char hex key",
        .roomIDLabel:                "Room ID",
        .clientIDLabel:              "Client ID",
        .keyHexLabel:                "Key (hex)",
        .vp8ParamsHeader:            "VP8 parameters",
        .socksAuthHeader:            "SOCKS5 authentication",
        .socksAuthFooter:            "Username and password that apps must supply to use the local SOCKS5 proxy. Only needed if other apps on this device should be restricted from using the tunnel.",
        .socksUserLabel:             "User",
        .socksPassLabel:             "SOCKS password",
        .socksUserPlaceholder:       "empty = no auth",
        .vp8FpsLabel:                "FPS",
        .vp8BatchLabel:              "Batch size",
        .globalDefault_fmt:          "global (%d)",
        .overrideHint:               "Overrides global settings for this connection only. «×» resets to global.",
        // #365: per-connection seichannel params
        .seiParamsHeader:            "SEI parameters",
        .seiFpsLabel:                "FPS",
        .seiBatchLabel:              "Batch size",
        .seiFragLabel:               "Fragment size",
        .seiAckLabel:                "ACK timeout (ms)",
        // #461 was: "seichannel" — the id; the picker calls this one "SEI".
        .seiParamsHint:              "Tuning for the SEI channel. Sent only when the transport is SEI; stored either way.",

        // ServersView
        // #457 was: "VPS list" — the screen title disagreed with its own tab and
        // with the copy that points at it. Same noun everywhere.
        .serversTitle:               "Servers",
        .emptyNoServers:             "No servers",
        .emptyNoServersHint:         "Add a server over SSH and the app installs one container per protocol. Each protocol becomes a connection you can use or share.",
        .newServerTitle:             "New server",
        .editServerTitle:            "Edit",
        .sshAccessHeader:            "SSH access",
        .hostField:                  "Host",
        .portField:                  "Port",
        .loginField:                 "Login",
        .passwordField:              "Password",
        .actionInstall:              "Install",
        .actionUninstall:            "Remove container from server",
        // (audit) was: "Update binary (git pull + rebuild)" — stale since the
        // pinned-SHA migration: SSHRunner now fetches AppConstants.upstreamCorePin
        // (git fetch --depth 1 + checkout), no git pull / moving branch.
        .actionUpdate:               "Update binary (fetch pinned build + rebuild)",
        .actionReboot:               "Reboot",
        .actionChangeRoomTransport:  "Change room / transport",
        .actionContainerLogs:        "Container logs",
        .actionDone:                 "Done",
        .actionRemoveFromList:       "Remove host from list",
        .removeHostConfirmTitle:     "Remove %@?",
        // #458 was: "use Uninstall first" — no control is called "Uninstall";
        // the menu item is `actionUninstall`, "Remove container from server".
        .removeHostConfirmMessage:   "The host will be removed from this device's list. The container on the VPS is NOT touched — use «Remove container from server» first if you want to wipe it. SSH password is removed from Keychain.",
        .uninstallConfirmTitle:      "Uninstall container?",
        .uninstallConfirmBody:       "Every olcrtc container on this server (all protocols), the deploy directory and the encryption key will be removed. Podman, the golang image (~300 MB) and the Go module cache stay. Reinstallation is fast (~1–2 min).",
        .deepUninstallConfirmBody:   "Removes container, Go cache (~300 MB), and encryption key. Podman and image stay.",
        .rebootConfirmTitle:         "Reboot server?",
        .rebootConfirmBody:          "This will reboot the entire VPS. The olcrtc container will restart automatically once the server is back online.",

        // #303: Recover connection from server
        .actionRecoverConnection:    "Recover connection",
        .recoverConfirmTitle:        "Recover connection from this server?",
        .recoverConfirmBody:         "Reads the carrier, room, transport and encryption key already deployed on this server (read-only) and adds them as a new connection here.",
        .recoverConfirmAction:       "Recover",
        .provisioningRecovering:     "Reading server config…",
        .recoverResultSuccess_fmt:   "Recovered %@/%@ — connection added",
        .recoverErrorMissingYAML:    "Server config not found — the deployed server.yaml could not be read.",
        .recoverErrorMissingField_fmt: "Server config is missing '%@'",

        // #314: generate-new-key fallback (server.yaml unreadable/unparseable)
        .rotateKeyConfirmTitle:      "Server config unreadable — generate a new key?",
        .rotateKeyConfirmBody:       "The deployed server.yaml could not be read, so the existing connection cannot be recovered. This generates a new encryption key on the server, repairs its config, restarts it, and adds the resulting connection here. Warning: all other devices using this server will lose access until they import the new connection.",
        .rotateKeyConfirmAction:     "Generate new key",
        .provisioningRotatingKey:    "Generating new server key…",
        .rotateKeyResultSuccess:     "New key active. Any link you shared before has stopped working.",
        .rotateKeyResultAdded_fmt:   "New key generated — %@/%@ connection added",
        .rotateKeyFailedNoURI:       "Key rotation finished but the server did not print a URI — check the provisioning log.",

        // Container status
        .containerRunning_fmt:       "Container running: %@",
        .containerStopped_fmt:       "Container stopped: %@",
        .containerNotFound:          "Container not found",
        .containerNotFoundShort:     "not found",
        // #458 was: "… — tap «Install»." This fires from `startContainer` /
        // `stop` / `recoverConnection` / `rotateKey` / `addCarrier`, and in
        // exactly those states the card's button is «Check server» or «Retry» —
        // Install is not on the screen. State the fact; the card's own primary
        // action already offers the right next step for the state it is in.
        .containerNotInstalled:      "No olcrtc container is installed on this server yet.",
        .readinessNoPodman:              "Ready to install (Podman not found, full setup ~5–7 min)",
        .readinessNoImage:               "Podman ready — first install pulls image (~300 MB, ~3–5 min)",
        .readinessImageReady:            "Image cached — reinstall takes ~1–2 min",
        .readinessContainerStopped_fmt:  "Stopped: %@",
        .readinessContainerRunning_fmt:  "Running: %@",

        // VPS status card (#258/#261)
        .vpsTitleUnknown:         "Not checked",
        .vpsTitleReady:           "Ready to install",
        .vpsTitlePodmanReady:     "Podman ready",
        .vpsTitleStopped:         "Stopped",
        .vpsTitleRunning:         "Running",
        .vpsSubUnknown:           "No test has been run on this server.",
        .vpsSubNoPodman:          "Full setup ~5–7 min",
        .vpsSubNoImage:           "First install pulls image (~300 MB)",
        .vpsSubImageReady:        "Image cached — fast reinstall",
        .vpsSubStopped:           "Container present, not running",
        .vpsSubRunning:           "The container is running. Nothing has gone through it yet.",
        .vpsVerbChecking:         "Checking",
        .vpsVerbInstalling:       "Installing",
        .vpsVerbStarting:         "Starting",
        .vpsVerbStopping:         "Stopping",
        .vpsVerbReconfiguring:    "Reconfiguring",
        .vpsVerbUpdating:         "Updating",
        .vpsVerbUninstalling:     "Uninstalling",
        .vpsVerbDeepUninstalling: "Deep uninstalling",
        .vpsVerbRebooting:        "Rebooting",
        .vpsConnecting:           "Connecting…",
        .vpsCheckServer:          "Check server",
        .vpsWorking:              "Working…",
        .vpsOpFailed_fmt:         "%@ failed",

        // ContainerLogsView
        // #339 was: emptyLogsTitle + emptyLogsHint_fmt (ContainerLogsView sheet, deleted)
        .closeAction:                "Close",

        // LogsView
        .logsTitle:                  "Logs",
        .logsSearchPlaceholder:      "Search",
        .emptyLogsGeneric:           "Empty",
        // #316 was: `emptyLogsGenericHint`, "Run an operation in the Connections
        // or Manage VPS tab" — deleted in #457 with the Logs tab itself; a
        // pushed log names its own subject and never points at a tab.
        .noSearchResults:            "Nothing found",
        .noSearchResultsHint_fmt:    "No matches for «%@».",
        .categoryConnection:         "Connection",
        .categoryDiagnostics:        "Diagnostics",
        .categoryProvisioning:       "VPS",
        .categoryContainerLogs:      "Container",

        // #294: per-source Logs tabs
        // #316 was: lowercase fragments shown under the tab title — now they
        // open the empty-state hint, so they read as sentences.
        .logsTabDescConnection:      "Connection logs",
        .logsTabDescDiagnostics:     "IP and speed test logs",
        .logsTabDescVPS:             "VPS provisioning logs",
        .logsTabDescContainer:       "Server container extracted logs",
        .logsFileNameLabel_fmt:      "File: %@",
        .logsContainerSelectServer:  "Server",
        .logsContainerNoServers:     "No servers configured",

        // #295: per-server container log files
        .duplicateServerNameError:   "A server with this name already exists",

        // #296: Container tab always-present load button
        // #338 was: logsDownloadFromServer ("Download logs from server")
        .logsCheckServer:            "Check server",
        .logsContainerEmptyHint:     "Nothing loaded yet. Tap Fetch to pull the newest lines from this server.",
        // #316: single-stack Logs tab — segmented-control short labels + line count
        .logsSegConnection:          "Conn",
        .logsSegDiagnostics:         "Diag",
        .logsSegVPS:                 "VPS",
        .logsSegContainer:           "Container",
        .logsLineCount_fmt:          "%d lines",
        .logsPeerCount_fmt:          "👥 %d peers",
        // #338: inline container fetch — source card + monotonic phases
        .logsFetchAction:            "Fetch",
        .logsFetchFromHost_fmt:      "Fetch from %@",
        .logsPhaseConnecting:        "Connecting…",
        .logsPhaseCommand_fmt:       "podman logs --tail %d %@",
        .logsPhaseReceiving:         "Receiving output…",
        // #332: rendered-line cap notice
        .logsRenderTruncated_fmt:    "Showing the newest %d lines — Share or Copy all exports the full history.",
        .logsShareThisAction:        "Share this log",
        .logsExportAllAction:        "Export all logs",
        .earlyRestartWedgeLabel:     "Auto-restart a stuck session",
        .wedgeRestartLog:            "⚠ Session appears wedged — restarting early",
        .wedgeRestartReason:         "stuck session",
        // #461 was: "wbstream token" — the id, not the label the picker shows.
        .wbTokenHeader:              "WB Stream token",
        .wbTokenFieldLabel:          "Account token (optional)",
        // #461 was: "wbstream" / "datachannel" — raw ids.
        .wbTokenFooter:              "Paste the WB Stream account token. Leave empty for an anonymous guest; a token is required for DataChannel.",

        // SettingsView
        .settingsTitle:              "Settings",
        .sectionSOCKS5:              "SOCKS5",
        .sectionDNS:                 "DNS",
        // #460 (finding 12, verifier pass) was: "vp8channel" — the raw
        // transport id. Every picker in the app names this transport "VP8"
        // (`transportVp8channel`), so a Settings header spelling it the
        // internal way was the last place that id surfaced in the UI.
        .sectionVP8:                 "VP8 video transport",
        // #460 was: `.sectionConnection` ("Connection") over eight rows and at
        // least four subjects. One header per subject now, so a footer under
        // any of them can only mean the row above it.
        .settingsSectionOnOpen:      "When the app opens",
        .settingsSectionStart:       "Starting a connection",
        .settingsSectionStayConnected: "Staying connected",
        .settingsSectionSpeedTest:   "Speed test",
        .settingsSectionUpdates:     "Updates",
        .sectionLogs:                "Logs",
        .sectionIPSources:           "IP-check sources",
        .ipSourcesFooter:            "Services queried by the IP check. The RU-zone options stay reachable when public resolvers are blocked. If none are selected, the defaults are used.",
        .sectionSpeedProvider:       "Speed-test provider",
        // #460 (verifier pass) was: "…if Cloudflare is slow" — it named one
        // provider by brand, so it read as false advice to anyone who had
        // already switched away from it.
        .speedProviderFooter:        "Server the speed test runs against. Switch if the one selected is slow or blocked on your network.",
        .speedAllFailed:             "All measurements failed",
        // #458 was: "…Reconfigure the server to datachannel…" — capital-R
        // "Reconfigure" reads as a control name, and no control carries it; the
        // item is `actionChangeRoomTransport`, on the server card.
        // #461 was: "(vp8channel/sei/video)" and "to datachannel" — raw ids in
        // advice about a picker that spells all four out.
        .speedDatachannelHint:       "Tip: the video transports (VP8, SEI, Video) trade bandwidth for looking like a call. For more speed, switch the server's transport to DataChannel with «Change room / transport» on the Servers tab, where your network allows it.",
        .settingsPortLabel:          "Port",
        .checkPortAction:            "Check port",
        .randomPortAction:           "Random",
        .portFree:                   "free",
        .portBusy:                   "busy",
        .logPortFree_fmt:            "✓ Port %d free",
        .logPortBusyOther_fmt:       "✗ Port %d busy",
        .logPortBusyOlcrtc_fmt:      "✓ Port %d in use by olcrtc tunnel",
        .socksPortChangeNote:        "Port change takes effect on the next connection.",
        .dnsFreeFormPlaceholder:     "IP:port",
        .dnsFooter:                  "Passed to the Go runtime and to the server install script. Format: IP:port. RU carrier presets only resolve from inside that carrier's network.",
        // #460 (finding 12) was: `.vp8Footer` — "MobileSetVP8Options only
        // applies when transport=vp8channel…". A gomobile symbol and a config
        // literal in a Settings footer.
        // #460 (verifier pass) also was: the raw ids "vp8channel" and
        // "wbstream" in the replacement sentence. `CarrierTransportMatrix`
        // displays those two as "VP8" and "WB Stream" in every picker, so
        // the note now uses the words the user was shown when they chose.
        // #461: "Telemost" -> "Yandex Telemost", to match the carrier label.
        .vp8Note:                    "These two matter only when the server sends its traffic as video — the VP8 transport, which is what WB Stream uses by default. More frames and bigger batches move more data, but look less like an ordinary video call. The defaults, 60 and 64, are tuned for Yandex Telemost.",
        .startTimeoutLabel:          "Ready timeout",
        .startTimeoutNote:           "How long to wait for a connection to come up before giving up and reporting a failure.",
        .autoConnectOnLaunchLabel:   "Auto-connect on launch",
        .autoConnectOnLaunchNote:    "Starts the connection shown on the Connections tab as soon as the app opens.",
        .autoRemoveConnectionOnUninstallLabel: "Remove linked connection when VPS is uninstalled",
        .autoRemoveOnUninstallNote:  "When you uninstall a server on the Servers tab, the connection it created is removed from your Connections list too.",
        .tunnelCheckLabel:           "Tunnel check",
        .keepAliveOff:               "off",
        .backgroundAudioLabel:       "Background work (audio)",
        .backgroundAudioNote:        "Keeps the tunnel alive while the app is in the background by playing a silent audio track. Uses more battery.",
        .earlyRestartWedgeNote:      "Restarts the session as soon as it stops passing traffic, without waiting for it to drop. Off by default.",
        .localSocksAuthLabel:        "Require proxy authentication",
        .logLevelLabel:              "Log level",
        .logLevelNote:               "How much detail is recorded. Higher levels help when you are chasing a problem, and fill the log faster.",
        // #460 (verifier pass) was: "…every N seconds" — an algebra variable
        // for the number in the field this note now sits directly under.
        .footerKeepAlive:            "Sends an end-to-end probe through SOCKS5 at the interval set here. On failure the tunnel reconnects automatically. Set to 0 to disable.",
        .footerLogBuffer:            "Maximum number of lines kept in memory per log category.",
        .logBufferLabel:             "Log buffer",
        // #460 (finding 12 class, verifier pass) was: "Container logs (tail)"
        // — `tail` is the shell command this ends up running, not something
        // the label needs to say; the note under it already explains it.
        .containerLogsTailLabel:     "Container log lines",
        .containerLogsTailNote:      "How many of the newest lines to pull from a server's container log.",
        .clearAllLogsAction:         "Clear all logs",
        .copyAllAction:              "Copy all",
        .clearCategoryAction:        "Clear this category",
        .fontSizeLabel:              "Font size",
        .fontSizeSystem:             "System",
        .fontPreviewText:            "Preview text — this is how labels and headings will look across the app.",
        // #460 (finding 18) was: `.fontFooter` — "Applied app-wide (via SwiftUI
        // dynamicTypeSize)". A framework API named in a Settings footer.
        .fontNote:                   "Sets the text size everywhere in the app. Smaller fits more on screen, larger is easier to read. «System» follows the text size from iOS Settings.",
        .languageLabel:              "Language",
        .themeLabel:                 "Theme",

        // #340/#299: appearance scheme picker. #457 was: this comment still
        // listed a fourth "Gray" scheme, deleted in #456.
        .appearanceLabel:            "Appearance",
        .appearanceSystem:           "System",
        .appearanceLight:            "Light",
        .appearanceDark:             "Dark",
        // #342: fixed-footprint hero footer

        // InstallOptionsView
        .installTitle:               "Install olcrtc",
        .reconfigureTitle:           "Change room / transport",
        .reconfigureInfoFooter:      "The container will be restarted with the new -carrier/-id/-transport flags. No reinstall (no apt-get / go build).",
        .reconfigureTransportTuningFooter: "Changing the transport resets vp8/sei tuning on the server to its defaults. Reinstall to set custom tuning.",
        .parametersHeader:           "Parameters",
        .roomIDAutoGenHint:          "Room ID will be generated by the server.",
        .roomIDTelemostHint:         "Create a meeting on telemost.yandex.ru and paste its ID (the part after /j/ in the link).",
        .roomIDWbstreamHint:         "Create a room on stream.wb.ru under your account and paste its ID.",
        .matrixRecommended_fmt:      "★ Recommended for %@.",
        .matrixWorks_fmt:            "Works with %@.",
        .matrixQuestion_fmt:         "⚠ Working with %@ is uncertain.",
        .matrixFail_fmt:             "✗ Does not work with %@ — choose another transport.",
        .matrixUnknown_fmt:          "No compatibility data for %@.",
        .carrierFooter:          "client-id=ios-<random> (auto-generated) · key=hex64 (auto-generated) · DNS and VP8 from Settings",
        .transportSectionHeader:     "Transport",
        .roomIDSectionHeader:        "Room ID",
        .jitsiServerHeader:          "Jitsi server",
        .jitsiServerFooter:          "Shared public instance — point at your own Jitsi for reliability and to avoid overloading it.",
        .seiSettingsHeader:          "SEI Settings",
        // #461 was: "SEI params sent to srv.sh for seichannel." — a script
        // filename and a raw transport id in a footer the user reads.
        .seiSettingsFooter:          "SEI parameters, sent to the server on install. Used only by the SEI transport.",
        .actionQR:                   "QR",

        // Status banner

        // TunnelManager log lines
        .mobileStartOK:              "✓ MobileStart OK, waiting for WaitReady…",
        .mobileStartFailed_fmt:      "✗ MobileStart: %@",
        .bgKeeperFailed_fmt:         "⚠ Background audio keeper failed: %@ — app may be suspended after backgrounding",
        .transportUsesServerDefaults_fmt: "Server defaults will be used for %@ tunables — advanced parameters are not yet exposed in the iOS settings UI.",
        .waitReadyFailed_fmt:        "✗ WaitReady: %@",
        .connectNoPeer:              "No peer joined in time — check the key matches the server, the room is correct, or try another carrier/transport.",
        .waitReadyOK:                "✓ WaitReady OK — SOCKS5 listening, verifying tunnel…",
        .tunnelOK:                   "✓ Tunnel works — traffic is flowing through the server",
        .tunnelFailed:               "✗ Tunnel not responding (server unreachable or 403 Forbidden IP)",
        .keepAliveOK:                "♡ Keep-alive OK",
        .keepAliveLost:              "✗ Keep-alive: tunnel not responding",
        .serverConnectionLost:       "Connection to the conferencing server lost",
        .serverNotResponding:        "Conferencing server not responding",
        .disconnectingArrow:         "→ Disconnecting",
        .netPathLost:                "⚠ Network lost — waiting for connectivity",
        .waitingForPortRelease:      "⏳ Waiting for port release…",
        .netPathRestored:            "network restored",
        .netPathChanged:             "network path changed",
        .reconnecting_fmt:           "↻ Reconnecting (%@)",
        .reconnectAttempt_fmt:       "↻ attempt %d/%d in %ds",
        .reconnectGaveUp:            "✗ Reconnect failed — tap Retry",
        .rejoinSettle_fmt:           "⏳ Room settle: %.1fs before re-join",
        .connectingOlcrtc_fmt:       "→ olcrtc carrier=%@ transport=%@ clientID=%@",

        // TunnelManager errors
        .validateClientIDEmpty:      "Client ID cannot be empty",
        .validateClientIDWhitespace: "Client ID must not contain spaces",
        .validateKeyLength_fmt:      "Key must be 64 hex characters (got: %d)",
        .validateKeyNonHex:          "Key contains non-hex characters",
        .validateRoomIDEmpty:        "Room ID cannot be empty",
        .errorPortBusy_fmt:          "Port %d is busy — free it or change the port in Settings",
        .errorSecretsLocked:         "Unlock the device and reopen the app to load your saved key.",
        .errorRuntimeStillStopping:  "Previous session is still shutting down — try again in a few seconds.",

        // OlcrtcURI errors
        .uriErrorInvalidScheme:      "URI must start with olcrtc://",
        .uriErrorMissingField_fmt:   "Missing field: %@",
        .uriErrorMixedBrackets:      "URI payload brackets are mismatched (expected [...] or <...>)",

        // Provisioning
        .provisioningSSHConnecting:  "Connecting via SSH…",
        .provisioningRebootSSH:      "Reboot: connecting via SSH…",
        .provisioningUninstallSSH:   "Delete: connecting via SSH…",
        .provisioningRebooting:      "Rebooting…",
        .provisioningUninstalling:   "Removing container and files…",
        .provisioningUpdating:       "Updating binary…",
        .provisioningReconfiguring:  "Reconfiguring container…",
        .provisioningStatusFetching: "Container status…",
        .provisioningLogsFetching:   "Container logs…",
        .installStep1Upload:         "[1/3] Uploading script…",
        .installStep2Launch:         "[2/3] Running install script…",
        .installStep3PollRetry_fmt:  "[3/3] Server temporarily unavailable, retry (%d)…",
        .installPhaseWaiting:        "Waiting…",
        .installPhaseSystemDeps:     "Installing system dependencies…",
        .installPhaseClone:          "Cloning repository…",
        .installPhasePullImage:      "Pulling Go image…",
        .installPhaseDeps:           "Downloading Go modules…",
        .installPhaseBuild:          "Building olcrtc…",
        .installPhaseStart:          "Starting olcrtc…",
        .installFailedNoURI_fmt:     "Script finished without URI. Last lines:\n%@",
        .installTimeout25min:        "Install timed out (25 minutes)",
        .installResultSuccess_fmt:   "olcrtc server installed (%@/%@)",
        .uninstallResultSuccess:     "Container removed. Connections through it no longer work.",
        .updateResultSuccess:        "Binary updated",
        .provisioningStarting:       "Starting server…",
        .startResultSuccess:         "Server started",
        .actionStart:                "Start server",
        .provisioningStopping:       "Stopping server…",
        .stopResultSuccess:          "Server stopped",
        .actionStop:                 "Stop server",
        .scanningContainers:         "Scanning for olcrtc containers…",
        .actionScanVPS:              "Scan for installed olcrtc",
        .scanNoContainers:           "No olcrtc containers found on this server.",
        .scanRestoreAction:          "Restore",
        .actionDeepUninstall:        "Wipe all olcrtc data from server",
        .deepUninstallResultSuccess:          "All olcrtc data removed",
        .reconfigureResultSuccess_fmt: "Parameters updated (%@/%@)",
        .rebootResultSuccess:        "Reboot command sent",
        .logsBytesReceived_fmt:      "Logs received (%d bytes)",
        .provisionPasswordMissing:   "Password not found in Keychain",
        .provisionSSHPrefix_fmt:     "SSH: %@",
        .provisionCommandPrefix_fmt: "Command: %@",
        .provisionParsePrefix_fmt:   "Failed to parse output: %@",
        .sshAttemptFailed_fmt:       "✗ SSH attempt %d/2 failed: %@",
        .sshRetryIn4s:               "  retry in 4 s…",
        .sshPortNotResponding_fmt:   "Port %d on %@ did not respond — verify SSH is open and the VPS is reachable",
        .serverUnreachable_fmt:      "Server %@ is not responding — check the VPS is online and SSH port is reachable",
        .sshTunnelDroppedMidOp_fmt:  "The SSH session was riding the app's own tunnel and that tunnel dropped mid-operation — the command may already have run on the server. Reconnect, then re-check the server state. (%@)",

        // NetPing
        .pingTCPOK_fmt:              "TCP/%d responded in %@ ms",
        .pingTCPFail_fmt:             "TCP/%d unreachable",

        // ConnectionsView per-connection ping (#234)
        .pingNoFreePort:             "No free local port available for ping",
        .pingFailed:                 "Ping failed",

        // ServersView alerts
        .alertPasswordMissingShort:  "Password not found",
        .alertKeyMissingShort:       "SSH key not found",
        .shareFullAccessKeyHostUnavailable: "Full access can't be shared for this server: it authenticates with an SSH key, and the link would embed your private key. Share the connection URI instead, or switch the server to password auth.",

        // AddServerHostView
        .nameSettingLabel:           "Name",
        .sectionDescription:         "Description",
        .testSSHAction:              "Test SSH",
        // #451: SSH auth-method picker + private-key entry
        .authMethodPickerLabel:      "Authentication",
        .authMethodPassword:         "Password",
        .authMethodKey:              "SSH key",
        .sshKeyFooter:               "Paste the contents of an OpenSSH private-key file (ed25519 or RSA), e.g. ~/.ssh/id_ed25519. The key is stored only in the device Keychain.",
        .sshKeyPasteButton:          "Paste key from clipboard",
        .sshKeyPassphraseField:      "Key passphrase",
        .sshKeyDetected_fmt:         "✓ %@ key detected",
        .sshKeyDetectedEncrypted_fmt: "✓ %@ key detected — encrypted, passphrase required",
        .sshKeyErrorECDSA:           "ECDSA keys are not supported. Use an ed25519 or RSA key (ssh-keygen -t ed25519).",
        .sshKeyErrorUnsupportedFormat: "Unsupported key format. Convert it to OpenSSH format: ssh-keygen -p -o -f <keyfile>.",
        .sshKeyErrorNotAKey:         "This doesn't look like a private key. Paste the whole file including the BEGIN OPENSSH PRIVATE KEY lines (not the .pub file).",

        // ConnectionsView misc
        .diagnosticsTitle:           "Diagnostics",
        .ipCheckTitle:               "IP check",
        .ipCheckRun:                 "Check IP",
        .speedTestRun:               "Run test",

        // #311 — speed-tile metric labels/units + upload-fallback log line
        .speedLabelDL:               "DL",
        .speedLabelUL:               "UL",
        // #342 was: "%.0f ms" / "%.1f Mbps" — unit moved to OlcMetric(unit:)
        .speedRateValue_fmt:         "%.1f",
        .speedUnitMbps:              "Mbps",
        .speedUploadFallback_fmt:    "  upload: %@ has no upload endpoint — using %@",

        // #236/#237 — UI strings localized after the i18n pass
        .ipChecking:                 "Checking…",
        .ipNotChecked:               "Not checked yet",
        .ipDnsLeak:                  "IPs differ — possible DNS leak",
        .ipSourcesAgree_fmt:         "✓ %@ (%d sources)",
        .socksProxyAddr_fmt:         "SOCKS5 proxy: 127.0.0.1:%@",
        .portInUseByOlcrtc:          "in use by olcrtc tunnel",
        .roomPrefix_fmt:             "room: %@",
        .qrCodeURIA11y:              "Connection URI QR Code",
        .qrCodeHintA11y:             "Scan this code to import the connection on another device",
        .cameraUnavailableTitle:     "Camera not available",
        .cameraUnavailableBody:      "QR scanning requires a physical device with a camera.",
        .sectionCarrier:             "Carrier",
        .labelTransport:             "Transport",
        // #461 was: "Telemost". Complaint 1 is that the hero must name the
        // service the traffic hides inside; that service is a Yandex product
        // and "Telemost" alone reads as a generic word.
        .carrierTelemost:            "Yandex Telemost",
        .carrierWbstream:            "WB Stream",
        .carrierJitsi:               "Jitsi",
        .transportDatachannel:       "DataChannel",
        .transportVp8channel:        "VP8",
        .transportSeichannel:        "SEI",
        .transportVideochannel:      "Video",
        .fieldRoomID:                "Room ID",
        .fieldJitsiURL:              "https://meet.example.org",

        // DNS carrier labels
        .dnsLabelMts:                "MTS",
        .dnsLabelBeeline:            "Beeline",
        .dnsLabelMegafon:            "MegaFon",
        .dnsLabelTele2:              "Tele2",
        .dnsLabelYota:               "Yota",

        // SubscriptionFetcher
        .subDohFailed_fmt:           "DoH could not resolve %@",
        .subInvalidResponse_fmt:     "HTTP %d",
        .subNoAddress:               "DoH returned an empty address list",

        // #111: subscription import (olcrtc-sub:// links)
        .subImportTitle:             "Import subscription",
        .subImportConfirm_fmt:       "Add %d connection(s) from “%@”?",
        .subImportAddAction:         "Add",
        .subInvalidLink:             "Subscription link must look like olcrtc-sub://host/path",
        .subEmptyList:               "The subscription contains no valid connections",
        .subImportPastedSource:      "pasted list",

        // #363: surfaced subscription metadata
        .subMetaSource:              "Source",
        .subMetaServers:             "Servers",
        .subMetaRefresh:             "Refresh",
        .subMetaRefreshNever:        "Never",
        .subMetaRefreshInterval_fmt: "every %@",
        .subMetaUsed:                "Used",
        .subMetaAvailable:           "Available",
        .subMetaMultipleSources_fmt: "%d sources",   // #396

        // #346: VPS-card mini-stat labels (abbreviations; ru = en per operator)
        .vpsStatPing:                "Ping",
        .vpsStatDisk:                "Disk",
        .vpsStatRAM:                 "RAM",
        .vpsStatUp:                  "Up",
        .scanRestored_fmt:           "Restored: %@",

        // #337: screenshot-safe IP masking
        .maskIPsLabel:               "Hide IP addresses",
        // #460 (verifier pass) was: "Masks IP addresses… Logs are not masked."
        // The toggle above it is called "Hide IP addresses"; a footer that
        // renames the control it explains reads as being about something else.
        .maskIPsFooter:              "Hides IP addresses on the Connections diagnostics and VPS cards for safe screenshots. Display-only — copy actions and stored values stay real. Logs still contain the real addresses.",

        // #328: active-carrier endpoints with one-tap copy
        // #460 (finding 23) was: `.carrierEndpointsTitle` ("Carrier endpoints")
        // and `.carrierEndpointsHint` ("Add these as DIRECT rules in your proxy
        // app so its own traffic doesn't loop through olcrtc."). Written for
        // someone who already knew what it meant, on the main screen, with
        // nothing saying who needs it. The row now opens with the question that
        // selects its audience; the sheet explains itself before the list.
        // #461: this is a ⋯ menu item on the live connection now, not a ~90 pt
        // card row, so it is a label. `carrierEndpointsRowHint`,
        // `carrierEndpointsRowConnectHint` and `carrierEndpointsShowAction`
        // went with the row; `carrierEndpointsLead` still explains the sheet.
        .carrierEndpointsRowTitle:   "Using another proxy app?",
        .carrierEndpointsScreenTitle: "Send these direct",
        // "DIRECT" stays capitalised: it is the literal name of the rule in the
        // proxy apps this screen exists for, and the word the reader must find.
        .carrierEndpointsLead:       "Only needed if another proxy or VPN app is handling this phone's traffic. Add every address below to that app's DIRECT (bypass) list, so it lets olcrtc's own video call out untouched — otherwise it captures the call the tunnel is built on and nothing connects.",
        .carrierEndpointsFootnote:   "These belong to the conferencing service, and were looked up when this screen opened. They rotate — open it again after a reconnect.",
        .carrierEndpointHost:        "Host",
        .carrierEndpointResolvedIPs: "Resolved IPs",
        .carrierEndpointResolving:   "Resolving…",
        .carrierEndpointUnresolved:  "Could not resolve",
        .carrierEndpointNoHost:      "This carrier's room ID isn't a host — nothing to exclude.",
        .carrierEndpointCopied_fmt:  "📋 Copied: %@",
        .carrierEndpointRefresh:     "Re-resolve",
        // #460 was: `.carrierEndpointsCheckAction` ("Check" — it read as "check
        // whether these endpoints are healthy", which the button does not do),
        // plus `.carrierEndpointsConnectHint` / `.carrierEndpointsReadyHint`.
        .carrierEndpointCopyAll:     "Copy host & IPs",

        // #359: accessibility for the hero connect toggle + icon toolbar buttons
        .a11yConnectToggle:          "Connect",
        .a11yConnectHintSelectFirst: "Select a connection first",
        .a11yStateConnected:         "Connected",
        .a11yStateConnecting:        "Connecting",
        .a11yStateDisconnected:      "Disconnected",

        // #360: in-app update checker (GitHub Releases)
        .updateCheckLabel:           "Check for updates",
        .updateCheckFooter:          "Once a day, checks GitHub Releases for a newer build and tells you how to sideload it. Anonymous — no account, no install id, no download is sent. Turn off to never contact GitHub.",
        .updateAvailableTitle_fmt:   "Update available — %@",
        .updateAvailableBody:        "A newer build is on GitHub. Open the release page or, if you sideload, tap your installer below to fetch the unsigned build.",
        .updateOpenReleasePage:      "Open release page",
        .updateInstallSideStore:     "Install with SideStore",
        .updateInstallLiveContainer: "Install with LiveContainer",
        .updateLater:                "Later",

        // Bot settings (#416–#420)
        .botPlatformTelegram:        "Telegram",
        .botPlatformMax:             "Max",
        .botDeploying:               "Deploying bot…",
        .botDeploySuccess:           "Bot deployed",
        .botChecking:                "Checking for bot…",
        .botRemoving:                "Removing bot…",
        .botRemoveSuccess:           "Bot removed",
        .botErrorNoSystemd:          "This server has no systemd, so the bot can't run as a service.",
        .botErrorNoPython:           "Couldn't install python3 on this server (required to run the bot).",
        .botErrorNoRoot:             "Root or sudo access is required to install the bot.",
        .botErrorGeneric_fmt:        "Bot setup failed: %@",
        .botErrorNotActive:          "The bot was installed but its service didn't start.",
        .botSheetTitle:              "Bot",
        .botSheetFooter:             "Send the start or stop command to your bot to control this server. One bot per server.",
        .botSelectLabel:             "Bot",
        .botCommandsHeader:          "Commands",
        .botRepliesHeader:           "Replies",
        .botStartCmdLabel:           "Start command",
        .botStopCmdLabel:            "Stop command",
        .botStartReplyLabel:         "Reply on start",
        .botStopReplyLabel:          "Reply on stop",
        .botUnknownReplyLabel:       "Reply on unknown command",
        .botDefaultStartReply:       "Success",
        .botDefaultStopReply:        "Success",
        .botDefaultUnknownReply:     "Please try again later",
        .botCheckAction:             "Check server",
        .botDeployAction:            "Deploy bot",
        .botRemoveAction:            "Remove bot from server",
        .botStatusRunning:           "Running",
        .botStatusInstalledIdle:     "Installed, not running",
        .botStatusNone:              "No bot on this server",
        .botNoBotsTitle:             "No bots yet",
        .botNoBotsHint:              "Add a bot in Settings → Bots, then deploy it here.",
        .botMissingTokenError:       "This bot has no token yet — add one in Settings → Bots.",
        .botUnknownFound_fmt:        "Found a bot “%@” that isn't in your Settings.",
        .botRemoveConfirmTitle:      "Remove bot from this server?",
        .botRemoveConfirmBody:       "The bot service is stopped and removed from the server. Its token stays saved in Settings.",
        .sectionBots:                "Bots",
        .botsFooter:                 "These names are used to find your bots on servers. Deleting a bot here stops detecting it (a bot already running on a server keeps working) and erases its saved token.",
        .botsEmptyHint:              "No bots configured.",
        .botAddTitle:                "Add bot",
        .botEditTitle:               "Edit bot",
        .botAddAction:               "Add bot",
        .botDeleteAction:            "Delete bot",
        .botNameLabel:               "Name",
        .botNamePlaceholder:         "olcrtc_server_bot",
        .botPlatformLabel:           "Platform",
        .botTokenLabel:              "Token",
        .botTokenPlaceholder:        "Paste token",
        .botTokenSavedHint:          "A token is saved. Paste to replace; leave blank to keep.",
        .botTokenNoneHint:           "No token saved yet.",
        .botTokenStatusSaved:        "Saved",
        .botTokenStatusMissing:      "Not set",
        .botTokenManageHint:         "The token is set in Settings → Bots.",
        .botTokenCreateHint:         "Create the bot on the platform and get its token first, then paste it here.",
        .botCopyTokenAction:         "Copy token",
        .botTokenCopied:             "📋 Token copied",
        .botNameTakenError:          "A bot with this name already exists",

        // #452: multi-carrier VPS — protocol rows + extras install
        .protocolsSectionHeader:      "Protocols",
        .addProtocolAction:           "Add protocol",
        .addProtocolTitle:            "Add protocol",
        .removeProtocolAction:        "Remove from server",
        .removeProtocolConfirmTitle_fmt: "Remove %@ from this server?",
        .removeProtocolConfirmBody:   "Stops and deletes this protocol's container and its config on the VPS. The matching connection is removed from your list too. The other protocols keep running.",
        .protocolConnectAction:       "Connect via this protocol",
        // #460 (findings 7 / 16) was: `.protocolConnectedBadge` ("Connected") —
        // the longest word on a title line too narrow for it, which SwiftUI
        // hyphenated into "Connec-ted". Keep any translation short.
        .protocolLiveBadge:           "Live",
        .protocolPrimaryBadge:        "primary",
        .protocolRecordMissing:       "No saved connection matches this protocol — use «Recover connection» in the row menu.",
        .protocolAdded_fmt:           "Added %@/%@ — connection saved",
        .protocolRemoved_fmt:         "Removed %@ from the server",
        .installExtrasHeader:         "Additional protocols",
        .installExtrasFooter:         "Installed on the same server right after the primary protocol, sharing one encryption key. Each protocol gets its own connection in the list — pick which one to use at connect time.",
        .installExtraToggle_fmt:      "Also install %@",
        .installExtrasPartialFail_fmt: "Some protocols failed to install: %@",

        // #456: verified health vocabulary. Nothing below claims success
        // without a probe behind it; "Working" is granted only by an
        // end-to-end result that is still inside the freshness window.
        .healthNeverChecked:          "Not checked yet",
        // #459 was: "Tap Verify to push a real request through this connection."
        // — the row's Verify menu item is gone (its chip is the affordance), so
        // the sentence named a control that is not on that screen. It now just
        // states the fact, which is what `healthNeverProbedHint` was added for.
        .healthNeverCheckedHint:      "No request has been pushed through this connection yet.",
        .healthChecking:              "Checking…",
        .healthCheckingHint:          "Joining the room and loading a test page",
        .healthVerified:              "Working",
        // #459 was: "Verified %@ ago · %d ms" — with an age of "just now" that
        // read "Verified just now ago". `HealthAge.phrase` now carries the
        // preposition, so no sentence here may add one.
        .healthVerifiedHint_fmt:      "Verified %@ · %d ms",
        .healthVerifiedNoRTTHint_fmt: "Verified %@",
        .healthFading:                "Worked recently",
        .healthHandshake:             "Connects, but no data",
        .healthHandshakeHint_fmt:     "Joined the room %@, but no traffic passed",
        .healthStale:                 "Out of date",
        .healthStaleHint_fmt:         "Last checked %@ — too old to trust",
        .healthInconclusive:          "Couldn't check",
        .healthCheckedAgo_fmt:        "checked %@",
        .healthChipNever:             "not checked",
        // #459 was: "%@ old" — which rendered "just now old".
        .healthChipStale_fmt:         "last seen %@",
        .healthChipFaded_fmt:        "was %@ · %@",
        .healthChipFadedNoRTT_fmt:   "worked %@",
        .healthChipFailed_fmt:        "failed %@",
        .healthChipHandshake_fmt:     "no data · %@",
        .healthChipUnchecked:         "couldn't check",
        // #459: two forms. `phrase` is a whole fragment — nothing may append
        // "ago" to it. `short` is a bare duration for a chip that already has a
        // value beside it ("215 ms · 2m"). Both are plural-safe at 1.
        .ageJustNow:                  "just now",
        .ageMinutesAgo_fmt:           "%d min ago",
        .ageHoursAgo_fmt:             "%d hr ago",
        .ageDaysAgo_fmt:              "%d d ago",
        .ageNowShort:                 "now",
        .ageMinutes_fmt:              "%dm",
        .ageHours_fmt:                "%dh",
        .ageDays_fmt:                 "%dd",

        // #456: failure reasons — what happened AND what to do next.
        .healthReasonKeyMismatch:      "The server's key has changed, so your saved key no longer matches. Use Recover connection to read the new one.",
        .healthReasonKeyMismatchShort: "Key no longer matches",
        .healthReasonNoPeer:           "Nobody answered in the room. The server may be stopped, on a different room, or its key may no longer match after a reinstall.",
        .healthReasonNoPeerShort:      "No answer in the room",
        .healthReasonRoomInvalid:      "The room ID isn't valid for this carrier. Check it in Change room / transport.",
        .healthReasonRoomInvalidShort: "Room ID rejected",
        .healthReasonCarrierRejected:  "The conferencing service refused the connection. The room may be gone, or the account token may be wrong.",
        .healthReasonCarrierRejectedShort: "Service refused",
        .healthReasonNetworkDown:      "This device has no internet connection, so this says nothing about the server.",
        .healthReasonNetworkDownShort: "No internet",
        .healthReasonHostUnreachable:  "The VPS didn't answer. It may be off, rebooting, or blocked by your network.",
        .healthReasonHostUnreachableShort: "VPS didn't answer",
        .healthReasonSSHAuth:          "SSH login was refused. The password or key saved for this VPS is wrong.",
        .healthReasonSSHAuthShort:     "SSH login refused",
        .healthReasonPortBusy:         "Another app is holding the local SOCKS port. Free it, or pick a different port in Settings.",
        .healthReasonPortBusyShort:    "Local port busy",
        .healthReasonVPNActive:        "Other nodes can't be tested while the system VPN is on. Turn it off and check again.",
        .healthReasonVPNActiveShort:   "System VPN is on",
        .healthReasonContainerStopped: "The server container isn't running. Start it, then check again.",
        .healthReasonContainerStoppedShort: "Server stopped",
        .healthReasonTimedOut:         "The test ran out of time before any data came back.",
        .healthReasonTimedOutShort:    "Timed out",
        // #458 was: "The Logs tab has the raw details." — #457 deleted the Logs
        // TAB (five tabs became Connect / Servers / Settings). The log lives at
        // Settings → `settingsViewLogsRow`, so that is what this must name.
        // #460: that row was renamed, so this sentence was renamed with it.
        .healthReasonUnknown:          "The check came back with no clear answer. Settings → View all logs has the raw details.",
        .healthReasonUnknownShort:     "No clear answer",

        // #456: health actions — same wording as the same action elsewhere.
        .healthActionRecover:         "Recover connection",
        .healthActionCheckRoom:       "Change room / transport",
        .healthActionStart:           "Start server",
        .healthActionPortSettings:    "Open port settings",
        .healthActionRetry:           "Retry",
        .healthActionVerify:          "Verify",
        .healthShowReasonAction:      "What's wrong?",
        .healthLatencyNotMeasured:    "not measured",

        // #456: VPS card headlines. "Couldn't check" is not "stopped".
        .vpsHeadlineOpFailed:            "Last action failed",
        .vpsHeadlineUnreachable:         "Can't reach the server",
        .vpsHeadlineUnreachableHint_fmt: "SSH didn't answer (%@)",
        .vpsHeadlineUnreachableHintNever: "SSH didn't answer",
        .vpsHeadlineNotChecked:          "Not checked yet",
        .vpsHeadlineNotCheckedHint:      "Checking the server…",
        .vpsHeadlineStopped:             "Server stopped",
        .vpsHeadlineStoppedHint:         "The container exists but isn't running — tap Start server",

        // #456: misc UI copy
        .shareConnectionOnlyBadge:    "Connection link — no server access",
        .shareConnectionOnlySub:      "The link below lets someone connect through your server. It carries no SSH login, and it cannot manage, reconfigure, or wipe the VPS.",
        .roomIDLastUsed_fmt:          "Use last room: %@",
        .installExistingFoundTitle_fmt: "This VPS already runs %@",
        .installExistingFoundBody:    "Reinstalling deletes it and every other olcrtc container on this server, along with their rooms and keys.",
        .installUseExistingAction:    "Use the existing one",
        .installReinstallAction:      "Reinstall anyway",

        // MARK: #457 Tunnel-mode picker (the Config tab is gone; the picker
        // lives on the Connect screen now). Three questions, plainly answered —
        // the choice changes what the word "Connected" means.
        .tunnelModeLockedNote:       "You can't switch while a connection is live. Disconnect first.",
        .tunnelCompareScope:         "What goes through it",
        .tunnelCompareScopeProxy:    "Only apps you point at 127.0.0.1",
        .tunnelCompareScopeVPN:      "Everything on this device",
        .tunnelCompareNeeds:         "What it needs",
        .tunnelCompareNeedsProxy:    "Nothing — it just runs",
        .tunnelCompareNeedsVPN:      "A VPN profile iOS asks you to approve",
        .tunnelCompareRuns:          "Where it runs",
        .tunnelCompareRunsProxy:     "Inside this app, while it's open",
        .tunnelCompareRunsVPN:       "In the background, app closed",

        // #457: Logs is a detail view of the thing it explains, so its title
        // names that subject instead of saying "Logs" four times over.
        // #460 (finding 21c) was: `.settingsOpenLogsRow` ("Diagnostics and
        // logs") — the third thing in the app called "Diagnostics", and the
        // only one of the three that opens a log reader. It says so now.
        .settingsViewLogsRow:        "View all logs",
        .logsSubjectConnection:      "Connection log",
        .logsSubjectProvisioning:    "Server operations log",
        .logsSubjectContainer_fmt:   "Server log · %@",
        .logsEmptySubjectHint:       "Nothing has been recorded here yet.",

        // #457: the Connect hero. The evidence line never claims more than was
        // measured — "connected" and "checked" are two different facts.
        .actionDisconnect:           "Disconnect",
        .heroSubjectNone:            "No connection yet",
        .heroLastUsedLabel:          "Last used",
        // #459 (audit): was "Pick a connection below." — this line renders ONLY
        // when `subject == nil`, and `ConnectionStore.primary` falls back to the
        // first record, so nil means the list is EMPTY. It pointed at a list that
        // was not there; the empty state below offers the one real next step.
        .heroPickAConnection:        "Add a connection first.",
        .heroEvidenceStarting_fmt:   "starting… %d s",
        .heroEvidenceUnverified:     "connected · no data checked through it yet",
        .heroEvidenceNoNetwork:      "holding the session until the network returns",
        // #461 was: "Proxy · only apps you point at 127.0.0.1:%@" — a sentence
        // where a caption was wanted. Same %@ (the bound port).
        .heroScopeProxy_fmt:         "Proxy · apps pointed at 127.0.0.1:%@",
        .heroScopeVPN:               "VPN · everything on this device",

        // #457/#459: connection rows. The live connection is the hero's subject
        // and is not drawn in the list, so no row needs a "Live" badge.
        .connectRowTapHint:          "Connects through this connection",
        .connectRowRemove:           "Remove connection",
        .connectGroupFailing_fmt:    "%d of %d not working",

        // #457: a suggested action that lives on another screen says where.
        .healthActionOnServersTab_fmt: "%@ — on the Servers tab",
        .healthActionInSettings_fmt:   "%@ — in Settings",
        .healthNeverMeasured:        "never measured",

        // #457/#459: the server card. The headline says what the server is
        // doing; all the caption adds is WHEN that was read (`vpsReadAge_fmt`),
        // or that it never has been.
        .vpsProtocolsFailing_fmt:    "%d of %d protocols are not working",
        .vpsProcessUnread:           "Nothing has been read from this server yet",
        .protocolStoppedNote:        "Not running on the server",
        .vpsScanBeforeInstall:       "Looking for an existing install…",
        .vpsScanFailed_fmt:          "Couldn't look at what's on this server. %@",

        // #458: unknown is its own answer. None of these name a control that
        // is not on the same screen — that was the bug.
        .protocolsNotReadYet:        "The protocol list hasn't been read from this server yet",
        .addProtocolAllInstalled:    "Every supported protocol is already installed on this server.",
        .healthNeverProbedHint:      "No request has been pushed through this connection yet",
        .connectRowVerifyHint:       "Checks this connection with a real request",

        // #459: the one-window redesign. The hero owns the live connection, the
        // list under it is a switcher, Health and Diagnostics are one card, and
        // the server card's thirteen-item menu is five safe items plus a pushed
        // "Manage server" screen.
        // #461 was: "Switch to" — complaint 3: the header ran into the server
        // label under it and read "Switch to — zaza". The protocol is the
        // subject on this screen, so the header says so and the row supplies it.
        .connectListOtherHeader:     "Switch protocol",
        .diagSessionHeader:          "This session",
        .diagToolsHeader:            "Checks",
        // #459: the owner asked, of the exit country and IP, "where do they even
        // come from?". Both hints name the service that answers.
        // #460 (findings 3 / 22) was: `.diagExitSourceHint` — "Asked ipinfo.io
        // through the tunnel", three words squeezed into the row's narrow
        // right-hand value column, where they wrapped into a ragged stack. The
        // note is full width now and says what was measured, not only who
        // answered — the city and the country are read off that one answer.
        .diagExitNote:               "Your exit IP address, looked up with ipinfo.io through the tunnel — the city and country come from that same answer.",
        // #460 (findings 2 / 15): the screen showed 1109 ms in red here and
        // 133 ms on a connection's chip, called both "the latency", and #460
        // explained the gap in a 250-character note.
        // #461: the owner asked twice for the numbers to agree, not for the
        // difference to be explained. Both sides now take the best of several
        // round-trips on one kept-alive connection, so the figures match, the
        // note is gone, and this row uses the same word as the chips.
        // #461 was: "Response time" and `.diagResponseNote`.
        .diagResponseLabel:          "Latency",
        // The count is enabled sources, which the user can set to 1 — hence the
        // colon rather than "%d services", which would read "1 services".
        .diagIPSourceHint_fmt:       "Asks public services for your address, over the current route. Sources: %d.",
        .vpsReadAge_fmt:             "read %@",
        .vpsManageServer:            "Manage server",
        .vpsAdvancedTitle_fmt:       "Manage %@",
        .vpsAdvancedConnectionHeader:  "Connection",
        .vpsAdvancedMaintenanceHeader: "Maintenance",
        .vpsAdvancedRemoveHeader:      "Remove",
        // Every destructive row says what it destroys — the sentence a menu row
        // could not carry, and the reason this screen exists.
        .vpsAdvancedRebootFooter:      "Restarts the whole server. Everything running on it stops until it comes back.",
        .vpsAdvancedUninstallFooter:   "Deletes every olcrtc container on this server, its deploy directory and the key. Every connection saved for it stops working.",
        .vpsAdvancedDeepUninstallFooter: "Deletes every olcrtc container, image and deploy directory on the server.",
        .vpsAdvancedRemoveHostFooter:  "Forgets this server in the app. Nothing on the machine itself changes.",

        // #460: screenshot rounds 2–4.
        // #461 was: `.heroExitSourceNote` — a full sentence of provenance under
        // the hero's country line, on the screen the owner asked to fit in one
        // page. `diagExitNote` says the same thing once, on the card.
        // Instruction 26: auto-switch moved off Settings and onto the screen
        // holding the protocols it switches between, so its explainer had to
        // shrink from a settings paragraph to one line on a card.
        .connectAutoSwitchHint:      "If the protocol in use stops answering, switch to another one on the same server.",

        // #461: with one installed protocol the switcher had a header and no
        // rows. The hint names the screen that fixes it — this screen never
        // draws a control that navigates away — and says why a second one is
        // worth installing, which is the whole point of the switcher.
        .connectSwitcherOnlyOne:     "Only one protocol on this server",
        .connectSwitcherAddHint:     "Install a second one on the Servers tab, so you can switch when one stops working.",

        // MARK: #463 One-button Telemost room renewal
        // Yandex expires a Telemost link 24 hours after it is created, and the
        // owner used to fix that by hand over SSH — the one channel a whitelist
        // window closes. These strings cover the whole errand in one sheet.

        // Create-call failures. Each names the cause AND the next move, and none
        // of them may ever carry the session cookie or an internal symbol.
        .telemostErrNoAccount:       "No Yandex account is linked. Sign in to create Telemost rooms.",
        .telemostErrSessionRejected: "Yandex rejected the saved sign-in. Sign in again.",
        .telemostErrRateLimited:     "Yandex is refusing new meetings right now. Wait a minute and try again.",
        .telemostErrNetwork:         "Could not reach Yandex. Check the connection and try again.",
        .telemostErrMalformed:       "Yandex sent an answer the app could not read. Try again.",
        .telemostErrStatus_fmt:      "Yandex returned an error (HTTP %d). Try again in a minute.",

        // The sign-in web view. This warning is the most important string in the
        // feature: the saved sign-in opens the whole Yandex account without the
        // password, so it is shown above the web view, before anything is typed.
        .yandexLoginTitle:           "Yandex sign-in",
        .yandexLoginWarning:         "Use a throwaway Yandex account. This device will store a sign-in token that opens that account's mail, Disk and payments without the password.",

        // The sheet. One name for the menu item and the sheet it opens.
        .telemostNewRoomAction:      "New Telemost room",
        .telemostRoomServerLine_fmt: "Yandex Telemost on %@",
        .telemostRoomExplainer:      "A Telemost link stops working 24 hours after it is created. This makes a fresh room in your Yandex account and points the server at it.",
        .telemostRoomNoAccountTitle: "No Yandex account linked",
        .telemostRoomNoAccountBody:  "Creating a room needs a signed-in Yandex account. Sign in with a throwaway one — the token is kept in the Keychain and never leaves this device.",
        .telemostRoomSignInAction:   "Sign in to Yandex",
        .telemostRoomIdleTitle:      "Yandex account linked",
        .telemostRoomIdleBody:       "One tap creates the room and moves this server into it.",
        .telemostRoomCreateAction:   "Create room and apply",
        .telemostRoomWorkingTitle:   "Working",
        .telemostRoomWorkingCreate:  "Creating the room in Telemost…",
        .telemostRoomWorkingApply:   "Sending the new room to the server…",
        .telemostRoomDoneTitle:      "Room replaced",
        .telemostRoomDoneBody:       "The server is in the new room. Its link is good for the next 24 hours.",
        .telemostRoomFailedTitle:    "Couldn't finish",
        .telemostRoomRetryAction:    "Try again",
        .telemostRoomOtherAccountAction:  "Use another account",
        .telemostRoomForgetAccountAction: "Forget this Yandex account",
        .telemostRoomKeychainNote:   "The sign-in token is kept in this device's Keychain only.",

        // The live-row hazard. Renewing the protocol the tunnel is riding on
        // restarts the container that carries the app's own SSH, so the command
        // loses its transport mid-flight. Say so plainly, and offer the safe
        // route first when the server has one.
        .telemostRenewLiveSwitchable_fmt: "You are connected through this protocol. Replacing its room restarts it, so the connection will drop. Connect through %@ first and it won't.",
        .telemostRenewSwitchAction_fmt:   "Connect through %@ first",
        .telemostRenewLiveOnly:      "You are connected through this protocol, and this server has no other one to use instead. Replacing the room restarts it, so the connection will drop mid-command — the app saves the new room and reconnects to it.",
        .telemostRenewDropped_fmt:   "The connection dropped while the server was switching to room %@ — expected when you renew the protocol you are connected through. The new room is saved and the app is reconnecting; run Verify from the protocol's menu to confirm the server took it.",
        .logsContainerPrimary:       "Primary",
        .vpsHeadlineProbeFailed:     "Couldn't check the server",
        .subMetaUpdatedPull_fmt:     "Updated %@ · pull down to refresh",
        .protocolStopAction:         "Stop this protocol",
        .protocolStartAction:        "Start this protocol",
        .telemostExpiryTitle:        "Telemost room expires soon",
        .telemostExpiryBody_fmt:     "The room behind \"%@\" stops working in about %d min, and the tunnel goes with it. Renewing now drops the connection for a few seconds.",
        .telemostExpiryRenewAction:  "Renew now",
        .later:                      "Later",
    ]

    // MARK: Russian

    static let russian: [L10n: String] = [
        // Common
        .ok:                "OK",
        .cancel:            "Отмена",
        .save:              "Сохранить",
        .close:             "Закрыть",
        .done:              "Готово",
        .error:             "Ошибка",
        .edit:              "Изменить",
        .okPrompt:          "Результат",   // #457 was: «Готово» — этим же заголовком показывались ошибки

        // Tabs
        .tabConnections:    "Подключения",
        // #457 was: «Управление VPS» — см. английскую таблицу: одно место
        // называлось тремя именами, и подсказка «на вкладке «Серверы»»
        // указывала на вкладку с другим названием.
        .tabServers:        "Серверы",
        .tabSettings:       "Настройки",
        .autoDetectedContainer_fmt: "Обнаружен существующий контейнер: %@",

        // Tunnel mode (#vpn)
        .tunnelModeProxy:           "Прокси",
        .tunnelModeVPN:             "VPN",
        .configModeSectionHeader:   "Режим туннеля",
        .configVPNUnavailableFooter: "Режим VPN недоступен в этой установке:",
        // #461 было: «videochannel» — сырой id; во всех списках он «Видео».
        .vpnVideochannelUnsupported: "Транспорт «Видео» не поддерживается в режиме VPN. Переключи подключение на другой транспорт или используй режим прокси.",
        .vpnDisconnected:           "VPN-туннель отключён",
        .vpnSettingsEntryName:      "OlcRTC",
        .vpnCapabilityUnavailable_fmt: "Система отклонила конфигурацию VPN (%@). Так бывает, если доступ к VPN был отклонён или приложение подписано бесплатным Apple ID — для Network Extension нужна платная команда Apple Developer. Режим прокси продолжает работать.",

        // #453: auto-failover. #460: элемент управления переехал на экран
        // «Подключения», к тем самым протоколам, между которыми он переключает,
        // поэтому это теперь заголовок карточки и строка условия под ней.
        // #460 было: `.configFailoverExplainer` — длинная фраза для страницы
        // настроек; на карточке её заменил однострочный `connectAutoSwitchHint`.
        .configFailoverToggle:       "Авто-переключение протоколов",
        .configFailoverProxyOnlyFooter: "Работает в режиме прокси.",
        .settingsRefreshOnEntryToggle:  "Проверять при открытии",
        // #460: «чтобы вы видели» → безличная форма; остальная таблица на «ты».
        .settingsRefreshOnEntryExplainer: "При открытии приложения заново проверять серверы и все протоколы на них, чтобы на экране было актуальное состояние. То, что проверялось пару минут назад, не трогается.",
        .failoverSwitching_fmt:      "Протокол %@ не отвечает — переключаюсь на %@",
        .failoverAllFailed:          "Все протоколы этого сервера недоступны",
        // #454/#459: карточка здоровья стала блоком «Текущая сессия» внутри
        // «Диагностики» — своего заголовка, строки скорости и кнопки обновления
        // у неё больше нет.
        .healthProtocolLabel:        "Протокол",
        .healthExitLabel:            "Выход",
        // #460 было: `.healthLatencyLabel` («Задержка») — см. `diagResponseLabel`.
        .healthLatencyMs_fmt:        "%d мс",
        .healthLocationUnknown:      "Местоположение неизвестно",
        // #455: premium redesign editorial additions
        // #461 было: «Telemost … (только vp8channel) … datachannel … WBStream» —
        // три сырых id и имя оператора, написанное не так, как в самом списке.
        .carrierChoiceFooter:        "«Яндекс Телемост» сложнее всего заблокировать (только VP8). Jitsi с DataChannel — самый быстрый и стабильный. WB Stream требует токен аккаунта.",
        // #460 было: `.configReliabilityHeader` («Надёжность») — в этом разделе
        // настроек остался только переключатель авто-переключения, а он переехал.
        .unitSeconds:                "с",
        .sshTestInvalidPort:         "Некорректный порт",
        .sshTestReachable_fmt:       "Доступен (%@)",
        .sshTestUnreachable:         "Недоступен",
        .logLevelOff:                "Выкл.",
        .logLevelErrors:             "Только ошибки",
        .logLevelNormal:             "Обычный",
        .logLevelDebug:              "Отладка",
        .logLevelVerbose:            "Подробный (всё)",
        // #455: reset-to-defaults
        .resetSettingsAction:        "Сбросить все настройки",
        .resetSettingsFooter:        "Вернёт все настройки к значениям по умолчанию, включая режим туннеля. Подключения и серверы сохранятся.",
        .resetSettingsConfirmTitle:  "Сбросить все настройки?",
        .resetSettingsConfirmBody:   "Все настройки вернутся к значениям по умолчанию, включая режим туннеля. Подключения и серверы не затрагиваются.",

        // Routing
        .routingHeader:     "Маршрутизация",
        .routingAllTunnel:  "Всё через туннель",
        .routingAllDirect:  "Всё напрямую",
        .routingViaTunnel:  "через туннель",
        .routingDirect:     "напрямую",

        // Connection state
        .stateDisconnected: "Отключено",
        .stateConnecting:   "Подключение…",
        .stateConnected:    "Подключено",
        .stateConnectFailed: "Сбой подключения",
        .stateWaitingForNetwork: "Ожидание сети…",
        .stateErrorPrefix_fmt: "Ошибка: %@",

        // ConnectionsView
        .emptyNoConnections:         "Нет подключений",
        // #303 was: "Нажми + чтобы добавить подключение вручную. Если есть VPS — перейди во вкладку Управление VPS для автоматической установки."
        .emptyNoConnectionsHint:     "Подключение — это один маршрут наружу: один протокол на одном из твоих серверов.",
        .actionConnect:              "Подключить",
        .actionRetry:                "Повторить",
        .shareAction:                "Поделиться",
        .copyURIAction:              "Скопировать URI",
        .shareConnectionTitle:       "Поделиться подключением",
        .shareConnectionExplanation: "Отправь этот URI чтобы другой пользователь мог подключиться через твой сервер. Содержит carrier, room ID и ключ шифрования — SSH-данные сервера не включены.",
        .shareConnectionURIHeader:   "URI подключения",
        // #135: full-access (co-admin) share
        .shareFullAccessTitle:       "Поделиться полным доступом (SSH)",
        .shareFullAccessHeader:      "Полный доступ (SSH)",
        .shareFullAccessWarning:     "Эта ссылка содержит SSH-логин и пароль. Любой, у кого она есть, получит полный контроль над VPS — установка, перенастройка, перезагрузка и удаление. Делись только с тем, кому доверяешь администрирование сервера.",
        .shareFullAccessReveal:      "Показать ссылку полного доступа",
        .shareFullAccessCopy:        "Скопировать ссылку полного доступа",
        .shareFullAccessCopied_fmt:  "🔑 Ссылка полного доступа скопирована: %@",
        // #366
        .fullAccessImportTitle:      "Импортировать полный доступ?",
        .fullAccessImportBody_fmt:   "Эта ссылка даёт полный SSH-доступ к серверу «%@» — его адрес, логин и пароль будут сохранены на этом устройстве. Импортируйте только доверенные ссылки.",
        .fullAccessImportAddAction:  "Добавить полный доступ",
        .fullAccessImportInvalid:    "Недействительная ссылка полного доступа.",
        .copiedURI_fmt:              "📋 URI скопирован: %@",

        // AddConnectionView
        .newConnectionTitle:         "Новое подключение",
        .editConnectionTitle:        "Редактирование",
        .nameField:                  "Метка",
        .namePlaceholder:            "Мой сервер",
        .groupField:                 "Группа",
        .groupDefault:               "Подключения",   // #344 was: "Основная"
        .importByURI:                "Импорт по ссылке",
        .scanQRAction:               "Сканировать QR",
        .pasteURIAction:             "Вставить URI",
        // #458 was: «Нажми «Вставить»…» — the button reads «Вставить URI».
        .importHint:                 "Нажми «Вставить URI», чтобы импортировать URI или подписку из буфера обмена, либо «Сканировать QR». Поля ниже заполнятся автоматически.", // #381 was: "Если у тебя есть URI с сервера — вставь сюда и нажми «Распознать». Поля ниже заполнятся автоматически." — кнопки «Сканировать QR» / «Вставить» (с #361 «Вставить» импортирует и подписки), кнопки «Распознать» нет.
        .clientIDFooter:             "Идентификатор устройства в комнате. «default» подходит для одного устройства. Используй уникальное значение если несколько устройств подключаются к одной комнате.",
        .keyPlaceholder:             "64-символьный hex-ключ",
        .roomIDLabel:                "Идентификатор комнаты",
        .clientIDLabel:              "ID клиента",
        .keyHexLabel:                "Ключ (hex)",
        .vp8ParamsHeader:            "VP8 параметры",
        .socksAuthHeader:            "SOCKS5 авторизация",
        .socksAuthFooter:            "Логин и пароль для доступа к локальному SOCKS5-прокси. Нужно только если хочешь ограничить другие приложения от использования туннеля.",
        .socksUserLabel:             "Пользователь",
        .socksPassLabel:             "Пароль SOCKS",
        .socksUserPlaceholder:       "пусто = без auth",
        .vp8FpsLabel:                "FPS",
        .vp8BatchLabel:              "Размер пачки",
        .globalDefault_fmt:          "глобальный (%d)",
        .overrideHint:               "Переопределяют глобальные настройки только для этого подключения. «×» сбрасывает к глобальному.",
        // #365: параметры seichannel для соединения
        .seiParamsHeader:            "Параметры SEI",
        .seiFpsLabel:                "FPS",
        .seiBatchLabel:              "Размер пакета",
        .seiFragLabel:               "Размер фрагмента",
        .seiAckLabel:                "Таймаут ACK (мс)",
        // #461 было: «seichannel» — id; в списке этот транспорт называется «SEI».
        .seiParamsHint:              "Настройки SEI-канала. Отправляются только при транспорте SEI, но сохраняются в любом случае.",

        // ServersView
        // #457 was: «Список VPS» — заголовок экрана расходился с названием
        // вкладки и с текстом, который на него ссылается.
        .serversTitle:               "Серверы",
        .emptyNoServers:             "Нет серверов",
        .emptyNoServersHint:         "Добавь сервер по SSH — приложение поставит по контейнеру на каждый протокол. Каждый протокол станет подключением, которым можно пользоваться и делиться.",
        .newServerTitle:             "Новый сервер",
        .editServerTitle:            "Изменить",
        .sshAccessHeader:            "Доступ по SSH",
        .hostField:                  "Хост",
        .portField:                  "Порт",
        .loginField:                 "Логин",
        .passwordField:              "Пароль",
        .actionInstall:              "Установить",
        .actionUninstall:            "Удалить контейнер с сервера",
        // (audit) was: "… (git pull + rebuild)" — see the English entry.
        .actionUpdate:               "Обновить бинарник (закреплённая сборка + пересборка)",
        .actionReboot:               "Перезагрузить",
        .actionChangeRoomTransport:  "Сменить комнату / транспорт",
        .actionContainerLogs:        "Логи контейнера",
        .actionDone:                 "Готово",
        .actionRemoveFromList:       "Удалить из списка",
        .removeHostConfirmTitle:     "Удалить %@?",
        // #458 was: «сначала нажми Uninstall» — an English word for a control
        // whose Russian name is «Удалить контейнер с сервера» (actionUninstall).
        .removeHostConfirmMessage:   "Сервер исчезнет из списка на этом устройстве. Контейнер на VPS НЕ затрагивается — если хочешь его вычистить, сначала выполни «Удалить контейнер с сервера». Пароль SSH удаляется из Keychain.",
        .uninstallConfirmTitle:      "Удалить контейнер?",
        .uninstallConfirmBody:       "Будут удалены все контейнеры olcrtc на этом сервере (все протоколы), папка развёртывания и ключ шифрования. Podman, образ golang (~300 МБ) и кеш Go-модулей останутся. Повторная установка займёт ~1–2 мин.",
        .deepUninstallConfirmBody:   "Удаляет контейнер, кеш Go (~300 МБ) и ключ шифрования. Podman и образ остаются.",
        .rebootConfirmTitle:         "Перезагрузить сервер?",
        .rebootConfirmBody:          "Будет выполнена перезагрузка всего VPS. Контейнер olcrtc запустится автоматически после того, как сервер поднимется.",

        // #303: Recover connection from server
        .actionRecoverConnection:    "Восстановить подключение",
        .recoverConfirmTitle:        "Восстановить подключение с этого сервера?",
        .recoverConfirmBody:         "Считывает carrier, room, transport и ключ шифрования, уже развёрнутые на этом сервере (только чтение), и добавляет их как новое подключение здесь.",
        .recoverConfirmAction:       "Восстановить",
        .provisioningRecovering:     "Чтение конфигурации сервера…",
        .recoverResultSuccess_fmt:   "Восстановлено %@/%@ — подключение добавлено",
        .recoverErrorMissingYAML:    "Конфигурация сервера не найдена — не удалось прочитать развёрнутый server.yaml.",
        .recoverErrorMissingField_fmt: "В конфигурации сервера отсутствует поле «%@»",

        // #314: generate-new-key fallback (server.yaml unreadable/unparseable)
        .rotateKeyConfirmTitle:      "Конфигурация сервера нечитаема — создать новый ключ?",
        .rotateKeyConfirmBody:       "Развёрнутый server.yaml не удалось прочитать, поэтому восстановить существующее подключение нельзя. Будет создан новый ключ шифрования на сервере, конфигурация восстановлена, сервер перезапущен, а полученное подключение добавлено здесь. Внимание: все другие устройства, использующие этот сервер, потеряют доступ, пока не импортируют новое подключение.",
        .rotateKeyConfirmAction:     "Создать новый ключ",
        .provisioningRotatingKey:    "Создание нового ключа сервера…",
        .rotateKeyResultSuccess:     "Новый ключ активен. Все ссылки, которыми ты делился раньше, перестали работать.",
        .rotateKeyResultAdded_fmt:   "Новый ключ создан — подключение %@/%@ добавлено",
        .rotateKeyFailedNoURI:       "Ротация ключа завершилась, но сервер не вывел URI — проверь журнал provisioning.",

        // Container status
        .containerRunning_fmt:       "Контейнер работает: %@",
        .containerStopped_fmt:       "Контейнер остановлен: %@",
        .containerNotFound:          "Контейнер не найден",
        .containerNotFoundShort:     "не найден",
        // #458 was: «— нажми «Установить».» — see the English entry: «Установить»
        // is not on the card in the states that raise this.
        .containerNotInstalled:      "На этом сервере ещё не установлен контейнер olcrtc.",
        .readinessNoPodman:              "Готов к установке (Podman не найден, полная установка ~5–7 мин)",
        .readinessNoImage:               "Podman установлен — первый раз скачает образ (~300 МБ, ~3–5 мин)",
        .readinessImageReady:            "Образ в кеше — переустановка займёт ~1–2 мин",
        .readinessContainerStopped_fmt:  "Остановлен: %@",
        .readinessContainerRunning_fmt:  "Работает: %@",

        // VPS status card (#258/#261)
        .vpsTitleUnknown:         "Не проверено",
        .vpsTitleReady:           "Готов к установке",
        .vpsTitlePodmanReady:     "Podman готов",
        .vpsTitleStopped:         "Остановлен",
        .vpsTitleRunning:         "Работает",
        .vpsSubUnknown:           "Проверка ещё не запускалась.",
        .vpsSubNoPodman:          "Полная установка ~5–7 мин",
        .vpsSubNoImage:           "Первая установка тянет образ (~300 МБ)",
        .vpsSubImageReady:        "Образ в кэше — быстрая переустановка",
        .vpsSubStopped:           "Контейнер есть, не запущен",
        .vpsSubRunning:           "Контейнер запущен. Через него пока ничего не проходило.",
        .vpsVerbChecking:         "Проверка",
        .vpsVerbInstalling:       "Установка",
        .vpsVerbStarting:         "Запуск",
        .vpsVerbStopping:         "Остановка",
        .vpsVerbReconfiguring:    "Переконфигурация",
        .vpsVerbUpdating:         "Обновление",
        .vpsVerbUninstalling:     "Удаление",
        .vpsVerbDeepUninstalling: "Полное удаление",
        .vpsVerbRebooting:        "Перезагрузка",
        .vpsConnecting:           "Подключение…",
        .vpsCheckServer:          "Проверить сервер",
        .vpsWorking:              "Выполняется…",
        .vpsOpFailed_fmt:         "Сбой: %@",

        // ContainerLogsView
        // #339 was: emptyLogsTitle + emptyLogsHint_fmt (ContainerLogsView sheet, deleted)
        .closeAction:                "Закрыть",

        // LogsView
        .logsTitle:                  "Логи",
        .logsSearchPlaceholder:      "Поиск",
        .emptyLogsGeneric:           "Пусто",
        // #316 was: `emptyLogsGenericHint` — «Запусти операцию во вкладке …»;
        // удалено в #457 вместе с вкладкой логов: экран лога называет свой
        // предмет сам и не отсылает к вкладкам.
        .noSearchResults:            "Ничего не найдено",
        .noSearchResultsHint_fmt:    "По запросу «%@» совпадений нет.",
        .categoryConnection:         "Подключение",
        .categoryDiagnostics:        "Диагностика",
        .categoryProvisioning:       "VPS",
        .categoryContainerLogs:      "Контейнер",

        // #294: per-source Logs tabs
        // #316 was: lowercase fragments (под заголовком таба) — теперь
        // открывают подсказку пустого состояния, читаются как предложения.
        .logsTabDescConnection:      "Логи подключения",
        .logsTabDescDiagnostics:     "Логи проверки IP и скорости",
        .logsTabDescVPS:             "Логи установки VPS",
        .logsTabDescContainer:       "Логи контейнера сервера",
        .logsFileNameLabel_fmt:      "Файл: %@",
        .logsContainerSelectServer:  "Сервер",
        .logsContainerNoServers:     "Нет настроенных серверов",

        // #295: per-server container log files
        .duplicateServerNameError:   "Сервер с таким именем уже существует",

        // #296: Container tab always-present load button
        // #338 was: logsDownloadFromServer ("Загрузить логи с сервера")
        .logsCheckServer:            "Проверить сервер",
        .logsContainerEmptyHint:     "Пока ничего не загружено. Нажми «Загрузить», чтобы получить свежие строки с этого сервера.",
        // #316: single-stack Logs tab — короткие подписи сегментов + счётчик строк
        .logsSegConnection:          "Подкл",
        .logsSegDiagnostics:         "Диаг",
        .logsSegVPS:                 "VPS",
        .logsSegContainer:           "Контейнер",
        .logsLineCount_fmt:          "%d стр.",
        .logsPeerCount_fmt:          "👥 %d участн.",
        // #338: inline container fetch — карточка источника + фазы
        .logsFetchAction:            "Загрузить",
        .logsFetchFromHost_fmt:      "Загрузить с %@",
        .logsPhaseConnecting:        "Подключение…",
        // deliberately English — a literal command line, not translated
        .logsPhaseCommand_fmt:       "podman logs --tail %d %@",
        .logsPhaseReceiving:         "Получение вывода…",
        // #332: rendered-line cap notice
        .logsRenderTruncated_fmt:    "Показаны последние %d строк — «Поделиться» или «Копировать всё» выгружает полную историю.",
        .logsShareThisAction:        "Поделиться этим логом",
        .logsExportAllAction:        "Выгрузить все логи",
        .earlyRestartWedgeLabel:     "Автоперезапуск зависшей сессии",
        .wedgeRestartLog:            "⚠ Похоже, сессия зависла — ранний перезапуск",
        .wedgeRestartReason:         "зависшая сессия",
        // #461 было: «Токен wbstream» — id вместо подписи из списка.
        .wbTokenHeader:              "Токен WB Stream",
        .wbTokenFieldLabel:          "Токен аккаунта (необязательно)",
        // #461 было: «wbstream» / «datachannel» — сырые id.
        .wbTokenFooter:              "Вставьте токен аккаунта WB Stream. Пусто — анонимный гость; для DataChannel токен обязателен.",

        // SettingsView
        .settingsTitle:              "Настройки",
        .sectionSOCKS5:              "SOCKS5",
        .sectionDNS:                 "DNS",
        // #460 (finding 12, проверка) было: «vp8channel» — сырой
        // идентификатор транспорта. Везде в приложении он называется «VP8».
        .sectionVP8:                 "Видеотранспорт VP8",
        // #460 было: `.sectionConnection` («Подключение») — один заголовок над
        // восемью строками и как минимум четырьмя разными темами. Теперь один
        // заголовок = одна тема, и подпись под разделом относится только к ней.
        .settingsSectionOnOpen:      "При открытии приложения",
        .settingsSectionStart:       "Запуск подключения",
        .settingsSectionStayConnected: "Удержание подключения",
        .settingsSectionSpeedTest:   "Тест скорости",
        .settingsSectionUpdates:     "Обновления",
        .sectionLogs:                "Логи",
        .sectionIPSources:           "Источники проверки IP",
        .ipSourcesFooter:            "Сервисы, опрашиваемые при проверке IP. Варианты из ru-зоны остаются доступны, когда публичные резолверы заблокированы. Если ничего не выбрано, используются значения по умолчанию.",
        // #460 было: «Провайдер спидтеста» — раздел над ним называется «Тест
        // скорости», а одна вещь должна называться одним словом.
        .sectionSpeedProvider:       "Провайдер теста скорости",
        .speedProviderFooter:        "Сервер, против которого идёт тест скорости. Смени, если выбранный медленный или заблокирован в твоей сети.",
        .speedAllFailed:             "Все измерения не удались",
        // #458: name the control that does it («Сменить комнату / транспорт»),
        // matching the English entry.
        // #461 было: «(vp8channel/sei/video)» и «на datachannel» — сырые id в
        // совете про список, который пишет все четыре словами.
        .speedDatachannelHint:       "Подсказка: видео-транспорты (VP8, SEI, Видео) жертвуют скоростью ради вида видеозвонка. Для большей скорости смените транспорт сервера на DataChannel через «Сменить комнату / транспорт» на вкладке «Серверы» там, где это позволяет сеть.",
        .settingsPortLabel:          "Порт",
        .checkPortAction:            "Проверить порт",
        .randomPortAction:           "Случайный",
        .portFree:                   "свободен",
        .portBusy:                   "занят",
        .logPortFree_fmt:            "✓ Порт %d свободен",
        .logPortBusyOther_fmt:       "✗ Порт %d занят",
        .logPortBusyOlcrtc_fmt:      "✓ Порт %d занят туннелем olcrtc",
        .socksPortChangeNote:        "Изменение порта применится при следующем подключении.",
        .dnsFreeFormPlaceholder:     "IP:port",
        .dnsFooter:                  "Передаётся в Go-рантайм и в скрипт установки сервера. Формат: IP:port. Пресеты RU-операторов резолвят только внутри сети соответствующего оператора.",
        // #460 (finding 12) было: `.vp8Footer` — «MobileSetVP8Options
        // применяется только если transport=vp8channel…»: символ gomobile и
        // строка конфига в подписи к настройке. Само слово «vp8channel»
        // остаётся — это транспорт, который пользователь выбирает на вкладке
        // «Серверы», а не внутреннее имя.
        // #461: «для Telemost» -> «под «Яндекс Телемост»» — как в списке.
        .vp8Note:                    "Эти два параметра важны, только когда сервер передаёт трафик видео — транспорт VP8, который WB Stream использует по умолчанию. Больше кадров и крупнее пачки — больше данных, но меньше похоже на обычный видеозвонок. Значения по умолчанию, 60 и 64, подобраны под «Яндекс Телемост».",
        .startTimeoutLabel:          "Таймаут готовности",
        .startTimeoutNote:           "Сколько ждать, пока подключение поднимется, прежде чем прекратить попытку и сообщить об ошибке.",
        .autoConnectOnLaunchLabel:   "Авто-подключение при запуске",
        .autoConnectOnLaunchNote:    "Запускает подключение, показанное на вкладке «Подключения», сразу при открытии приложения.",
        .autoRemoveConnectionOnUninstallLabel: "Удалять связанное соединение при удалении VPS",
        .autoRemoveOnUninstallNote:  "При удалении сервера на вкладке «Серверы» созданное им подключение удаляется и из списка на вкладке «Подключения».",
        .tunnelCheckLabel:           "Проверка туннеля",
        .keepAliveOff:               "выкл",
        .backgroundAudioLabel:       "Фоновая работа (через аудио)",
        .backgroundAudioNote:        "Держит туннель живым, пока приложение в фоне, проигрывая беззвучную аудиодорожку. Расходует больше батареи.",
        .earlyRestartWedgeNote:      "Перезапускает сессию, как только она перестаёт пропускать трафик, не дожидаясь разрыва. По умолчанию выключено.",
        .localSocksAuthLabel:        "Требовать аутентификацию прокси",
        .logLevelLabel:              "Уровень логирования",
        .logLevelNote:               "Насколько подробно вести запись. Высокие уровни помогают разобраться с проблемой, но лог заполняется быстрее.",
        .footerKeepAlive:            "С заданным здесь интервалом делает сквозную проверку через SOCKS5. При неудаче туннель переподключается. 0 — отключить.",
        .footerLogBuffer:            "Максимальное количество строк в памяти для каждой категории логов.",
        .logBufferLabel:             "Буфер логов",
        .containerLogsTailLabel:     "Строк из лога контейнера",
        .containerLogsTailNote:      "Сколько последних строк подтягивать из лога контейнера сервера.",
        .clearAllLogsAction:         "Очистить все логи",
        .copyAllAction:              "Копировать всё",
        .clearCategoryAction:        "Очистить категорию",
        .fontSizeLabel:              "Размер шрифта",
        .fontSizeSystem:             "Системный",
        .fontPreviewText:            "Превью текста — так будут выглядеть подписи и заголовки в приложении.",
        // #460 (finding 18) было: `.fontFooter` — «(через SwiftUI
        // dynamicTypeSize)»: имя фреймворка в подписи к настройке.
        .fontNote:                   "Задаёт размер текста во всём приложении. Меньше — помещается больше, больше — легче читать. «Системный» следует размеру текста из настроек iOS.",
        .languageLabel:              "Язык",
        .themeLabel:                 "Тема",

        // #340/#299: переключатель оформления (Системное / Светлое / Тёмное / Серое)
        .appearanceLabel:            "Оформление",
        .appearanceSystem:           "Системное",
        .appearanceLight:            "Светлое",
        .appearanceDark:             "Тёмное",
        // #342: подсказка в подвале hero-карточки

        // InstallOptionsView
        .installTitle:               "Установка olcrtc",
        .reconfigureTitle:           "Сменить комнату / транспорт",
        .reconfigureInfoFooter:      "Контейнер будет перезапущен с новыми флагами -carrier/-id/-transport. Переустановка не нужна (apt-get / go build не запускаются).",
        .reconfigureTransportTuningFooter: "При смене транспорта настройки vp8/sei на сервере сбрасываются на значения по умолчанию. Для тонкой настройки переустановите.",
        .parametersHeader:           "Параметры",
        .roomIDAutoGenHint:          "Room ID будет сгенерирован сервером.",
        .roomIDTelemostHint:         "Создай встречу на telemost.yandex.ru и вставь ID (часть после /j/ в ссылке).",
        .roomIDWbstreamHint:         "Создай комнату на stream.wb.ru под своей учёткой и вставь её ID.",
        .matrixRecommended_fmt:      "★ Рекомендуется для %@.",
        .matrixWorks_fmt:            "Работает с %@.",
        .matrixQuestion_fmt:         "⚠ Работа с %@ под вопросом.",
        .matrixFail_fmt:             "✗ Не работает с %@ — выбери другой транспорт.",
        .matrixUnknown_fmt:          "Нет данных о совместимости с %@.",
        .carrierFooter:          "client-id=ios-<случайный> (генерируется) · key=hex64 (генерируется) · DNS и VP8 из настроек",
        .transportSectionHeader:     "Транспорт",
        .roomIDSectionHeader:        "Room ID",
        .jitsiServerHeader:          "Сервер Jitsi",
        .jitsiServerFooter:          "Общий публичный сервер — укажи свой Jitsi для надёжности, чтобы не перегружать чужой.",
        .seiSettingsHeader:          "SEI-настройки",
        // #461 было: «передаются в srv.sh для seichannel» — имя скрипта и
        // сырой id транспорта в подписи, которую читает пользователь.
        .seiSettingsFooter:          "SEI-параметры, передаются на сервер при установке. Нужны только транспорту SEI.",
        .actionQR:                   "QR",

        // Status banner

        // TunnelManager log lines
        .mobileStartOK:              "✓ MobileStart OK, ожидаем WaitReady…",
        .mobileStartFailed_fmt:      "✗ MobileStart: %@",
        .bgKeeperFailed_fmt:         "⚠ Фоновый audio-keeper не запустился: %@ — приложение может быть остановлено в фоне",
        .transportUsesServerDefaults_fmt: "Будут использованы серверные дефолты для %@ — расширенные параметры пока не вынесены в настройки iOS.",
        .waitReadyFailed_fmt:        "✗ WaitReady: %@",
        .connectNoPeer:              "Пир не присоединился вовремя — проверь, что ключ совпадает с сервером, верна комната, или смените carrier/transport.",
        .waitReadyOK:                "✓ WaitReady OK — SOCKS5 слушает, проверяем туннель…",
        .tunnelOK:                   "✓ Туннель работает — данные идут через сервер",
        .tunnelFailed:               "✗ Туннель не отвечает (сервер недоступен или 403 Forbidden IP)",
        .keepAliveOK:                "♡ Keep-alive OK",
        .keepAliveLost:              "✗ Keep-alive: туннель не отвечает",
        .serverConnectionLost:       "Связь с сервером видеосвязи потеряна",
        .serverNotResponding:        "Сервер видеосвязи не отвечает",
        .disconnectingArrow:         "→ Отключение",
        .netPathLost:                "⚠ Сеть потеряна — ожидание подключения",
        .waitingForPortRelease:      "⏳ Ожидание освобождения порта…",
        .netPathRestored:            "сеть восстановлена",
        .netPathChanged:             "сеть изменилась",
        .reconnecting_fmt:           "↻ Переподключение (%@)",
        .reconnectAttempt_fmt:       "↻ попытка %d/%d через %d с",
        .reconnectGaveUp:            "✗ Не удалось переподключиться — нажми «Повторить»",
        .rejoinSettle_fmt:           "⏳ Очистка комнаты: %.1f с до повторного входа",
        .connectingOlcrtc_fmt:       "→ olcrtc carrier=%@ transport=%@ clientID=%@",

        // TunnelManager errors
        .validateClientIDEmpty:      "Client ID не может быть пустым",
        .validateClientIDWhitespace: "Client ID не должен содержать пробелы",
        .validateKeyLength_fmt:      "Ключ должен быть 64 hex-символа (получено: %d)",
        .validateKeyNonHex:          "Ключ содержит не-hex символы",
        .validateRoomIDEmpty:        "Room ID не может быть пустым",
        .errorPortBusy_fmt:          "Порт %d занят — освободите его или смените порт в Настройках",
        .errorSecretsLocked:         "Разблокируй устройство и снова открой приложение, чтобы загрузить сохранённый ключ.",
        .errorRuntimeStillStopping:  "Предыдущая сессия ещё завершается — попробуй снова через несколько секунд.",

        // OlcrtcURI errors
        .uriErrorInvalidScheme:      "URI должен начинаться с olcrtc://",
        .uriErrorMissingField_fmt:   "Не найдено поле: %@",
        .uriErrorMixedBrackets:      "Скобки полезной нагрузки URI не совпадают (ожидается [...] или <...>)",

        // Provisioning
        .provisioningSSHConnecting:  "Подключение по SSH…",
        .provisioningRebootSSH:      "Reboot: подключение по SSH…",
        .provisioningUninstallSSH:   "Удаление: подключение по SSH…",
        .provisioningRebooting:      "Перезагрузка…",
        .provisioningUninstalling:   "Удаление контейнера и файлов…",
        .provisioningUpdating:       "Обновление бинарника…",
        .provisioningReconfiguring:  "Изменение параметров контейнера…",
        .provisioningStatusFetching: "Статус контейнера…",
        .provisioningLogsFetching:   "Логи контейнера…",
        .installStep1Upload:         "[1/3] Загружаем скрипт…",
        .installStep2Launch:         "[2/3] Запускаем скрипт установки…",
        .installStep3PollRetry_fmt:  "[3/3] Сервер временно недоступен, повтор (%d)…",
        .installPhaseWaiting:        "Ожидание…",
        .installPhaseSystemDeps:     "Установка системных пакетов…",
        .installPhaseClone:          "Клонирование репозитория…",
        .installPhasePullImage:      "Загрузка образа Go…",
        .installPhaseDeps:           "Загрузка Go-модулей…",
        .installPhaseBuild:          "Сборка olcrtc…",
        .installPhaseStart:          "Запуск olcrtc…",
        .installFailedNoURI_fmt:     "Скрипт завершился без URI. Последние строки:\n%@",
        .installTimeout25min:        "Таймаут установки (25 минут)",
        .installResultSuccess_fmt:   "Сервер olcrtc установлен (%@/%@)",
        .uninstallResultSuccess:     "Контейнер удалён. Подключения через него больше не работают.",
        .updateResultSuccess:        "Бинарник обновлён",
        .provisioningStarting:       "Запускаем сервер…",
        .startResultSuccess:         "Сервер запущен",
        .actionStart:                "Запустить сервер",
        .provisioningStopping:       "Останавливаем сервер…",
        .stopResultSuccess:          "Сервер остановлен",
        .actionStop:                 "Остановить сервер",
        .scanningContainers:         "Сканируем VPS на наличие olcrtc…",
        .actionScanVPS:              "Найти установленный olcrtc",
        .scanNoContainers:           "На сервере не найдено olcrtc-контейнеров.",
        .scanRestoreAction:          "Восстановить",
        .actionDeepUninstall:        "Удалить весь olcrtc с сервера",
        .deepUninstallResultSuccess:          "Все данные olcrtc удалены",
        .reconfigureResultSuccess_fmt: "Параметры изменены (%@/%@)",
        .rebootResultSuccess:        "Команда reboot отправлена",
        .logsBytesReceived_fmt:      "Логи получены (%d байт)",
        .provisionPasswordMissing:   "Пароль не найден в Keychain",
        .provisionSSHPrefix_fmt:     "SSH: %@",
        .provisionCommandPrefix_fmt: "Команда: %@",
        .provisionParsePrefix_fmt:   "Не удалось разобрать вывод: %@",
        .sshAttemptFailed_fmt:       "✗ SSH attempt %d/2 failed: %@",
        .sshRetryIn4s:               "  повтор через 4 с…",
        .sshPortNotResponding_fmt:   "Порт %d на %@ не ответил — проверь что SSH открыт и VPS доступен",
        .serverUnreachable_fmt:      "Сервер %@ не отвечает — проверь что VPS включён и SSH-порт открыт",
        .sshTunnelDroppedMidOp_fmt:  "SSH-сессия шла через собственный туннель приложения, и туннель оборвался посреди операции — команда могла уже выполниться на сервере. Переподключись и проверь состояние сервера. (%@)",

        // NetPing
        .pingTCPOK_fmt:              "TCP/%d отвечает за %@ ms",
        .pingTCPFail_fmt:            "TCP/%d недоступен",

        // ConnectionsView per-connection ping (#234)
        .pingNoFreePort:             "Нет свободного локального порта для пинга",
        .pingFailed:                 "Пинг не удался",

        // ServersView alerts
        .alertPasswordMissingShort:  "Пароль не найден",
        .alertKeyMissingShort:       "SSH-ключ не найден",
        .shareFullAccessKeyHostUnavailable: "Полный доступ для этого сервера не передаётся: он использует SSH-ключ, и ссылка содержала бы твой приватный ключ. Поделись URI подключения или переведи сервер на пароль.",

        // AddServerHostView
        .nameSettingLabel:           "Название",
        .sectionDescription:         "Описание",
        .testSSHAction:              "Тест SSH",
        // #451: SSH auth-method picker + private-key entry
        .authMethodPickerLabel:      "Аутентификация",
        .authMethodPassword:         "Пароль",
        .authMethodKey:              "SSH-ключ",
        .sshKeyFooter:               "Вставьте содержимое файла приватного ключа OpenSSH (ed25519 или RSA), напр. ~/.ssh/id_ed25519. Ключ хранится только в Keychain устройства.",
        .sshKeyPasteButton:          "Вставить ключ из буфера",
        .sshKeyPassphraseField:      "Пароль ключа",
        .sshKeyDetected_fmt:         "✓ Обнаружен ключ %@",
        .sshKeyDetectedEncrypted_fmt: "✓ Обнаружен ключ %@ — зашифрован, нужен пароль ключа",
        .sshKeyErrorECDSA:           "Ключи ECDSA не поддерживаются. Используй ed25519 или RSA (ssh-keygen -t ed25519).",
        .sshKeyErrorUnsupportedFormat: "Неподдерживаемый формат ключа. Конвертируйте в формат OpenSSH: ssh-keygen -p -o -f <файл>.",
        .sshKeyErrorNotAKey:         "Это не похоже на приватный ключ. Вставьте файл целиком, включая строки BEGIN OPENSSH PRIVATE KEY (не .pub).",

        // ConnectionsView misc
        .diagnosticsTitle:           "Диагностика",
        .ipCheckTitle:               "Проверка IP",   // #460 было: «IP проверка» — не по-русски
        .ipCheckRun:                 "Проверить IP",
        .speedTestRun:               "Запустить тест",

        // #311 — speed-tile metric labels/units + upload-fallback log line (ru = en, see L10n.swift)
        .speedLabelDL:               "DL",
        .speedLabelUL:               "UL",
        // #342 was: "%.0f ms" / "%.1f Mbps" — unit moved to OlcMetric(unit:)
        .speedRateValue_fmt:         "%.1f",
        .speedUnitMbps:              "Mbps",
        .speedUploadFallback_fmt:    "  upload: %@ has no upload endpoint — using %@",

        // #236/#237 — UI strings localized after the i18n pass
        .ipChecking:                 "Проверка…",
        .ipNotChecked:               "Ещё не проверялось",
        .ipDnsLeak:                  "IP различаются — возможна утечка DNS",
        .ipSourcesAgree_fmt:         "✓ %@ (источников: %d)",
        .socksProxyAddr_fmt:         "SOCKS5-прокси: 127.0.0.1:%@",
        .portInUseByOlcrtc:          "занят туннелем olcrtc",
        .roomPrefix_fmt:             "комната: %@",
        .qrCodeURIA11y:              "QR-код URI подключения",
        .qrCodeHintA11y:             "Отсканируйте этот код, чтобы импортировать подключение на другом устройстве",
        .cameraUnavailableTitle:     "Камера недоступна",
        .cameraUnavailableBody:      "Для сканирования QR нужно физическое устройство с камерой.",
        .sectionCarrier:             "Оператор",
        .labelTransport:             "Транспорт",
        // #461 было: «Телемост» — теперь на главном экране это ИМЯ сервиса,
        // внутри которого прячется трафик, а у сервиса есть бренд.
        .carrierTelemost:            "Яндекс Телемост",
        .carrierWbstream:            "WB Stream",
        .carrierJitsi:               "Jitsi",
        .transportDatachannel:       "DataChannel",
        .transportVp8channel:        "VP8",
        .transportSeichannel:        "SEI",
        .transportVideochannel:      "Видео",
        .fieldRoomID:                "ID комнаты",
        .fieldJitsiURL:              "https://meet.example.org",

        // DNS carrier labels
        .dnsLabelMts:                "МТС",
        .dnsLabelBeeline:            "Билайн",
        .dnsLabelMegafon:            "МегаФон",
        .dnsLabelTele2:              "Tele2",
        .dnsLabelYota:               "Yota",

        // SubscriptionFetcher
        .subDohFailed_fmt:           "DoH не смог разрешить %@",
        .subInvalidResponse_fmt:     "HTTP %d",
        .subNoAddress:               "DoH вернул пустой список адресов",

        // #111: subscription import (olcrtc-sub:// links)
        .subImportTitle:             "Импорт подписки",
        .subImportConfirm_fmt:       "Добавить соединений: %d (из «%@»)?",
        .subImportAddAction:         "Добавить",
        .subInvalidLink:             "Ссылка подписки должна иметь вид olcrtc-sub://host/path",
        .subEmptyList:               "Подписка не содержит действительных соединений",
        .subImportPastedSource:      "вставленный список",

        // #363: отображение метаданных подписки
        .subMetaSource:              "Источник",
        .subMetaServers:             "Серверы",
        .subMetaRefresh:             "Обновление",
        .subMetaRefreshNever:        "Никогда",
        .subMetaRefreshInterval_fmt: "каждые %@",
        .subMetaUsed:                "Использовано",
        .subMetaAvailable:           "Доступно",
        .subMetaMultipleSources_fmt: "%d источников",   // #396

        // #346: подписи мини-статистики карточки VPS (аббревиатуры; ru = en по решению оператора)
        .vpsStatPing:                "Ping",
        .vpsStatDisk:                "Disk",
        .vpsStatRAM:                 "RAM",
        .vpsStatUp:                  "Up",
        .scanRestored_fmt:           "Восстановлено: %@",

        // #337: безопасный для скриншотов режим — скрытие IP
        .maskIPsLabel:               "Скрывать IP-адреса",
        // #460 было: «на вкладке «Соединения»» — вкладка называется
        // «Подключения» (`.tabConnections`); одно место — одно имя.
        .maskIPsFooter:              "Скрывает IP-адреса в диагностике на вкладке «Подключения» и на карточках VPS для безопасных скриншотов. Только отображение — копирование и сохранённые значения остаются настоящими. В логах адреса остаются настоящими.",

        // #328: конечные точки активного оператора с копированием в один тап
        // #460 (finding 23) было: `.carrierEndpointsTitle` («Точки оператора»)
        // и `.carrierEndpointsHint` — язык того, кто это сделал, на главном
        // экране и без единого слова о том, кому это вообще нужно. Строка
        // начинается с вопроса, который отбирает читателя, а экран объясняет
        // себя до списка адресов.
        // #461: теперь это пункт меню ⋯ у активного подключения, а не строка
        // карточки на ~90 pt, — значит, просто подпись. `carrierEndpointsRowHint`,
        // `carrierEndpointsRowConnectHint` и `carrierEndpointsShowAction` ушли
        // вместе со строкой; объяснение осталось в самом экране
        // (`carrierEndpointsLead`).
        .carrierEndpointsRowTitle:   "Пользуешься другим прокси-приложением?",
        .carrierEndpointsScreenTitle: "Отправлять напрямую",
        // «DIRECT» остаётся латиницей и заглавными: так это правило называется
        // в самих прокси-приложениях, и именно это слово надо там найти.
        .carrierEndpointsLead:       "Нужно, только если трафиком телефона управляет другое прокси- или VPN-приложение. Добавь все адреса ниже в его список DIRECT (исключений), чтобы оно выпускало видеозвонок olcrtc без изменений — иначе оно перехватит звонок, на котором держится туннель, и подключения не будет.",
        .carrierEndpointsFootnote:   "Это адреса самого сервиса видеозвонков, они определены при открытии экрана. Адреса меняются — открой экран заново после переподключения.",
        .carrierEndpointHost:        "Хост",
        .carrierEndpointResolvedIPs: "Найденные IP",
        .carrierEndpointResolving:   "Разрешение…",
        .carrierEndpointUnresolved:  "Не удалось разрешить",
        .carrierEndpointNoHost:      "ID комнаты этого оператора не является хостом — исключать нечего.",
        .carrierEndpointCopied_fmt:  "📋 Скопировано: %@",
        .carrierEndpointRefresh:     "Разрешить заново",
        // #460 было: `.carrierEndpointsCheckAction` («Проверить» — читалось как
        // «проверить, живы ли эти адреса», чего кнопка не делает), а также
        // `.carrierEndpointsConnectHint` / `.carrierEndpointsReadyHint`.
        .carrierEndpointCopyAll:     "Скопировать хост и IP",

        // #359: доступность переключателя подключения и кнопок-иконок в тулбаре
        .a11yConnectToggle:          "Подключиться",
        .a11yConnectHintSelectFirst: "Сначала выбери соединение",
        .a11yStateConnected:         "Подключено",
        .a11yStateConnecting:        "Подключение",
        .a11yStateDisconnected:      "Отключено",

        // #360: проверка обновлений (GitHub Releases)
        .updateCheckLabel:           "Проверять обновления",
        .updateCheckFooter:          "Раз в сутки проверяет в GitHub Releases новую сборку и подсказывает, как её установить через сайдлоад. Анонимно — без аккаунта, без идентификатора установки, ничего не отправляется. Отключи, чтобы вообще не обращаться к GitHub.",
        .updateAvailableTitle_fmt:   "Доступно обновление — %@",
        .updateAvailableBody:        "В GitHub есть более новая сборка. Открой страницу релиза или, если ставишь через сайдлоад, нажми кнопку своего установщика ниже, чтобы скачать неподписанную сборку.",
        .updateOpenReleasePage:      "Открыть страницу релиза",
        .updateInstallSideStore:     "Установить через SideStore",
        .updateInstallLiveContainer: "Установить через LiveContainer",
        .updateLater:                "Позже",

        // Настройки бота (#416–#420)
        .botPlatformTelegram:        "Telegram",
        .botPlatformMax:             "Max",
        .botDeploying:               "Установка бота…",
        .botDeploySuccess:           "Бот установлен",
        .botChecking:                "Проверка бота…",
        .botRemoving:                "Удаление бота…",
        .botRemoveSuccess:           "Бот удалён",
        .botErrorNoSystemd:          "На этом сервере нет systemd — бота нельзя запустить как службу.",
        .botErrorNoPython:           "Не удалось установить python3 на сервере (нужен для работы бота).",
        .botErrorNoRoot:             "Для установки бота нужен доступ root или sudo.",
        .botErrorGeneric_fmt:        "Не удалось настроить бота: %@",
        .botErrorNotActive:          "Бот установлен, но его служба не запустилась.",
        .botSheetTitle:              "Бот",
        .botSheetFooter:             "Отправьте боту команду запуска или остановки, чтобы управлять этим сервером. Один бот на сервер.",
        .botSelectLabel:             "Бот",
        .botCommandsHeader:          "Команды",
        .botRepliesHeader:           "Ответы",
        .botStartCmdLabel:           "Команда запуска",
        .botStopCmdLabel:            "Команда остановки",
        .botStartReplyLabel:         "Ответ при запуске",
        .botStopReplyLabel:          "Ответ при остановке",
        .botUnknownReplyLabel:       "Ответ на неизвестную команду",
        .botDefaultStartReply:       "Успех",
        .botDefaultStopReply:        "Успех",
        .botDefaultUnknownReply:     "Пожалуйста, повторите позднее",
        .botCheckAction:             "Проверить сервер",
        .botDeployAction:            "Установить бота",
        .botRemoveAction:            "Удалить бота с сервера",
        .botStatusRunning:           "Работает",
        .botStatusInstalledIdle:     "Установлен, не запущен",
        .botStatusNone:              "На этом сервере нет бота",
        .botNoBotsTitle:             "Ботов пока нет",
        .botNoBotsHint:              "Добавь бота в «Настройки → Боты», затем установи его здесь.",
        .botMissingTokenError:       "У этого бота ещё нет токена — добавь его в «Настройки → Боты».",
        .botUnknownFound_fmt:        "Найден бот «%@», которого нет в настройках.",
        .botRemoveConfirmTitle:      "Удалить бота с этого сервера?",
        .botRemoveConfirmBody:       "Служба бота будет остановлена и удалена с сервера. Токен останется сохранён в настройках.",
        .sectionBots:                "Боты",
        .botsFooter:                 "Эти имена используются для поиска ботов на серверах. Удаление бота здесь прекращает его обнаружение (уже запущенный на сервере бот продолжит работать) и стирает сохранённый токен.",
        .botsEmptyHint:              "Боты не настроены.",
        .botAddTitle:                "Добавить бота",
        .botEditTitle:               "Изменить бота",
        .botAddAction:               "Добавить бота",
        .botDeleteAction:            "Удалить бота",
        .botNameLabel:               "Имя",
        .botNamePlaceholder:         "olcrtc_server_bot",
        .botPlatformLabel:           "Платформа",
        .botTokenLabel:              "Токен",
        .botTokenPlaceholder:        "Вставьте токен",
        .botTokenSavedHint:          "Токен сохранён. Вставьте, чтобы заменить; оставьте пустым, чтобы сохранить.",
        .botTokenNoneHint:           "Токен ещё не сохранён.",
        .botTokenStatusSaved:        "Сохранён",
        .botTokenStatusMissing:      "Не задан",
        .botTokenManageHint:         "Токен задаётся в «Настройки → Боты».",
        .botTokenCreateHint:         "Сначала создайте бота на платформе и получите токен, затем вставьте его сюда.",
        .botCopyTokenAction:         "Скопировать токен",
        .botTokenCopied:             "📋 Токен скопирован",
        .botNameTakenError:          "Бот с таким именем уже существует",

        // #452: мульти-протокольный VPS — строки протоколов + доустановка
        .protocolsSectionHeader:      "Протоколы",
        .addProtocolAction:           "Добавить протокол",
        .addProtocolTitle:            "Добавить протокол",
        .removeProtocolAction:        "Удалить с сервера",
        .removeProtocolConfirmTitle_fmt: "Удалить %@ с этого сервера?",
        .removeProtocolConfirmBody:   "Останавливает и удаляет контейнер этого протокола и его конфиг на VPS. Соответствующее подключение тоже удаляется из списка. Остальные протоколы продолжают работать.",
        .protocolConnectAction:       "Подключиться через этот протокол",
        // #460 (findings 7 / 16) было: `.protocolConnectedBadge` («Подключено»)
        // — самое длинное слово в строке заголовка, которой не хватало ширины,
        // и SwiftUI переносил его посреди слова. Держать перевод коротким.
        .protocolLiveBadge:           "Активен",
        .protocolPrimaryBadge:        "основной",
        .protocolRecordMissing:       "Нет сохранённого подключения для этого протокола — используй «Восстановить подключение» в меню строки.",
        .protocolAdded_fmt:           "Добавлен %@/%@ — подключение сохранено",
        .protocolRemoved_fmt:         "%@ удалён с сервера",
        .installExtrasHeader:         "Дополнительные протоколы",
        .installExtrasFooter:         "Устанавливаются на тот же сервер сразу после основного протокола с общим ключом шифрования. Каждый протокол получает своё подключение в списке — выбирайте нужное при подключении.",
        .installExtraToggle_fmt:      "Также установить %@",
        .installExtrasPartialFail_fmt: "Часть протоколов не установилась: %@",

        // #456: словарь проверенного состояния. Ничего здесь не утверждает
        // успех без реальной проверки; «Работает» даёт только сквозной
        // результат, который ещё не устарел.
        .healthNeverChecked:          "Ещё не проверено",
        // #459 было: «Нажми «Проверить»…» — пункта «Проверить» в меню
        // строки больше нет (его роль играет сама плашка), так что фраза
        // называла контрол, которого на экране нет. Теперь она просто констатирует факт.
        .healthNeverCheckedHint:      "Через это подключение ещё не проходил ни один запрос.",
        .healthChecking:              "Проверяем…",
        .healthCheckingHint:          "Заходим в комнату и загружаем тестовую страницу",
        .healthVerified:              "Работает",
        // #459 было: «Проверено %@ назад · %d мс» — с возрастом «только что»
        // это читалось как «Проверено только что назад». Предлог теперь внутри
        // `HealthAge.phrase`, и ни одна фраза здесь не добавляет свой.
        .healthVerifiedHint_fmt:      "Проверено %@ · %d мс",
        .healthVerifiedNoRTTHint_fmt: "Проверено %@",
        .healthFading:                "Недавно работало",
        .healthHandshake:             "Соединяется, но данные не идут",
        .healthHandshakeHint_fmt:     "Вошли в комнату %@, но трафик не прошёл",
        .healthStale:                 "Устарело",
        .healthStaleHint_fmt:         "Последняя проверка %@ — слишком давно, чтобы на неё полагаться",
        .healthInconclusive:          "Не удалось проверить",
        .healthCheckedAgo_fmt:        "проверено %@",
        .healthChipNever:             "не проверено",
        // #459 было: «давность %@» → «давность только что».
        .healthChipStale_fmt:         "последний раз %@",
        .healthChipFaded_fmt:        "было %@ · %@",
        .healthChipFadedNoRTT_fmt:   "работало %@",
        // #460: «сбой только что» без двоеточия читалось как обрывок фразы.
        .healthChipFailed_fmt:        "сбой: %@",
        .healthChipHandshake_fmt:     "нет данных · %@",
        .healthChipUnchecked:         "не удалось проверить",
        // #459: две формы. `phrase` — законченный оборот, к нему нельзя ничего
        // приписывать. `short` — голая длительность для плашки, рядом с которой
        // уже стоит значение («215 мс · 2 мин»). Обе безопасны при 1.
        .ageJustNow:                  "только что",
        .ageMinutesAgo_fmt:           "%d мин назад",
        .ageHoursAgo_fmt:             "%d ч назад",
        .ageDaysAgo_fmt:              "%d дн. назад",
        .ageNowShort:                 "сейчас",
        .ageMinutes_fmt:              "%d мин",
        .ageHours_fmt:                "%d ч",
        .ageDays_fmt:                 "%d д",

        // #456: причины сбоя — что случилось И что делать дальше.
        .healthReasonKeyMismatch:      "Ключ сервера изменился, и сохранённый у тебя ключ больше не подходит. Нажми «Восстановить подключение», чтобы считать новый.",
        .healthReasonKeyMismatchShort: "Ключ не подходит",
        .healthReasonNoPeer:           "В комнате никто не ответил. Возможно, сервер остановлен, использует другую комнату, или его ключ после переустановки больше не совпадает.",
        .healthReasonNoPeerShort:      "Нет ответа в комнате",
        .healthReasonRoomInvalid:      "Идентификатор комнаты не подходит для этого сервиса. Проверь его в «Сменить комнату / транспорт».",
        .healthReasonRoomInvalidShort: "ID комнаты отклонён",
        .healthReasonCarrierRejected:  "Сервис видеосвязи отклонил подключение. Возможно, комнаты больше нет или неверен токен аккаунта.",
        .healthReasonCarrierRejectedShort: "Сервис отказал",
        .healthReasonNetworkDown:      "У устройства нет интернета, поэтому о сервере это ничего не говорит.",
        .healthReasonNetworkDownShort: "Нет интернета",
        .healthReasonHostUnreachable:  "VPS не ответил. Возможно, он выключен, перезагружается или заблокирован твоей сетью.",
        .healthReasonHostUnreachableShort: "VPS не ответил",
        .healthReasonSSHAuth:          "SSH-вход отклонён. Сохранённый для этого VPS пароль или ключ не подходит.",
        .healthReasonSSHAuthShort:     "SSH-вход отклонён",
        .healthReasonPortBusy:         "Локальный порт SOCKS занят другим приложением. Освободи его или выбери другой порт в настройках.",
        .healthReasonPortBusyShort:    "Локальный порт занят",
        .healthReasonVPNActive:        "Пока включён системный VPN, другие узлы проверить нельзя. Отключи его и проверь снова.",
        .healthReasonVPNActiveShort:   "Системный VPN включён",
        .healthReasonContainerStopped: "Контейнер сервера не запущен. Запусти его и проверь снова.",
        .healthReasonContainerStoppedShort: "Сервер остановлен",
        .healthReasonTimedOut:         "Проверка не уложилась во время — данные так и не пришли.",
        .healthReasonTimedOutShort:    "Истекло время",
        // #458 was: "… на вкладке «Логи»." — the Logs tab is gone (#457); the log
        // is reached from Settings → «Смотреть все логи» (settingsViewLogsRow).
        // #460: строку переименовали — переименована и эта фраза.
        .healthReasonUnknown:          "Проверка не дала ясного ответа. Подробности — в «Настройки → Смотреть все логи».",
        .healthReasonUnknownShort:     "Нет ясного ответа",

        // #456: действия — те же формулировки, что и у этих действий в других местах.
        .healthActionRecover:         "Восстановить подключение",
        .healthActionCheckRoom:       "Сменить комнату / транспорт",
        .healthActionStart:           "Запустить сервер",
        .healthActionPortSettings:    "Открыть настройки порта",
        .healthActionRetry:           "Повторить",
        .healthActionVerify:          "Проверить",
        .healthShowReasonAction:      "Что не так?",
        .healthLatencyNotMeasured:    "не измерено",

        // #456: заголовки карточки VPS. «Не удалось проверить» — это не «остановлен».
        .vpsHeadlineOpFailed:            "Последнее действие не удалось",
        .vpsHeadlineUnreachable:         "Сервер недоступен",
        .vpsHeadlineUnreachableHint_fmt: "SSH не ответил (%@)",
        .vpsHeadlineUnreachableHintNever: "SSH не ответил",
        .vpsHeadlineNotChecked:          "Ещё не проверено",
        .vpsHeadlineNotCheckedHint:      "Проверяем сервер…",
        .vpsHeadlineStopped:             "Сервер остановлен",
        .vpsHeadlineStoppedHint:         "Контейнер есть, но не запущен — нажми «Запустить сервер»",

        // #456: прочие строки интерфейса
        .shareConnectionOnlyBadge:    "Ссылка подключения — без доступа к серверу",
        .shareConnectionOnlySub:      "По ссылке ниже можно подключаться через твой сервер. SSH-доступа она не даёт, управлять VPS, перенастраивать или стирать его по ней нельзя.",
        .roomIDLastUsed_fmt:          "Использовать прошлую комнату: %@",
        .installExistingFoundTitle_fmt: "На этом VPS уже работает %@",
        .installExistingFoundBody:    "Переустановка удалит его и все остальные контейнеры olcrtc на этом сервере — вместе с их комнатами и ключами.",
        .installUseExistingAction:    "Использовать существующий",
        .installReinstallAction:      "Всё равно переустановить",

        // MARK: #457 Выбор режима туннеля (вкладка «Конфиг» удалена — выбор
        // переехал на экран подключения). От него зависит, что вообще означает
        // слово «Подключено».
        .tunnelModeLockedNote:       "Пока подключение работает, режим не переключить. Сначала отключись.",
        .tunnelCompareScope:         "Что идёт через него",
        .tunnelCompareScopeProxy:    "Только приложения, которые ты направишь на 127.0.0.1",
        .tunnelCompareScopeVPN:      "Весь трафик этого устройства",
        .tunnelCompareNeeds:         "Что для этого нужно",
        .tunnelCompareNeedsProxy:    "Ничего — просто работает",
        .tunnelCompareNeedsVPN:      "Профиль VPN — iOS попросит его подтвердить",
        .tunnelCompareRuns:          "Где работает",
        .tunnelCompareRunsProxy:     "Внутри приложения, пока оно открыто",
        .tunnelCompareRunsVPN:       "В фоне, приложение можно закрыть",

        // #457: лог — это подробности того, что его породило, поэтому в
        // заголовке стоит сам предмет, а не слово «Логи».
        // #460 (finding 21c) было: `.settingsOpenLogsRow` («Диагностика и
        // логи») — третье место в приложении со словом «Диагностика», и
        // единственное из трёх, которое открывает лог. Теперь так и написано.
        .settingsViewLogsRow:        "Смотреть все логи",
        .logsSubjectConnection:      "Лог подключения",
        .logsSubjectProvisioning:    "Лог операций с сервером",
        .logsSubjectContainer_fmt:   "Лог сервера · %@",
        .logsEmptySubjectHint:       "Здесь пока ничего не записано.",

        // #457: главный экран. «Подключено» и «проверено» — разные факты, и
        // строка доказательства не обещает больше, чем измерено.
        .actionDisconnect:           "Отключить",
        .heroSubjectNone:            "Пока нет подключений",
        .heroLastUsedLabel:          "Последнее",
        // #459 (audit): было «Выбери подключение ниже.» — списка в этот момент нет.
        .heroPickAConnection:        "Сначала добавь подключение.",
        .heroEvidenceStarting_fmt:   "запуск… %d с",
        .heroEvidenceUnverified:     "подключено · данные через него ещё не проверяли",
        .heroEvidenceNoNetwork:      "держим сессию, пока не вернётся сеть",
        // #461 было: «Прокси · только приложения, которые смотрят на …» —
        // предложение там, где нужна подпись. Тот же один %@ (порт).
        .heroScopeProxy_fmt:         "Прокси · приложения на 127.0.0.1:%@",
        .heroScopeVPN:               "VPN · весь трафик устройства",

        // #457/#459: строки подключений. Активное подключение — это герой
        // экрана, в списке его нет, поэтому плашка «Активно» не нужна.
        .connectRowTapHint:          "Подключиться через это подключение",
        .connectRowRemove:           "Удалить подключение",
        .connectGroupFailing_fmt:    "%d из %d не работает",

        // #457: если действие выполняется на другом экране — сказать, на каком.
        .healthActionOnServersTab_fmt: "%@ — на вкладке «Серверы»",
        .healthActionInSettings_fmt:   "%@ — в настройках",
        .healthNeverMeasured:        "не измерялось",

        // #457: карточка сервера. Подпись про процесс говорит только о том, что
        // считано с сервера, и всегда с возрастом — это не проверка подключения.
        .vpsProtocolsFailing_fmt:    "Не работает протоколов: %d из %d",
        .vpsProcessUnread:           "С этого сервера пока ничего не считано",
        .protocolStoppedNote:        "На сервере не запущен",
        .vpsScanBeforeInstall:       "Ищем уже установленное…",
        .vpsScanFailed_fmt:          "Не удалось посмотреть, что на сервере. %@",

        // #458: «неизвестно» — это тоже ответ. Ни одна строка не называет
        // кнопку, которой нет на том же экране.
        .protocolsNotReadYet:        "Список протоколов ещё не прочитан с этого сервера",
        .addProtocolAllInstalled:    "Все поддерживаемые протоколы уже установлены на этом сервере.",
        .healthNeverProbedHint:      "Через это подключение ещё не проходил ни один запрос",
        .connectRowVerifyHint:       "Проверить это подключение настоящим запросом",

        // #459: редизайн «одного окна». Герой владеет активным подключением,
        // список под ним — переключатель, «Здоровье» и «Диагностика» слились в
        // одну карточку, а меню из тринадцати пунктов на карточке сервера стало
        // пятью безопасными пунктами плюс экран «Управление сервером».
        // #461 было: «Переключиться» — жалоба 3: заголовок сливался с меткой
        // сервера под ним и читался как «Переключиться — zaza». Предмет этого
        // экрана — протокол, о нём заголовок и говорит.
        .connectListOtherHeader:     "Сменить протокол",
        .diagSessionHeader:          "Текущая сессия",
        .diagToolsHeader:            "Проверки",
        // #459: владелец спросил про страну и IP выхода — «откуда они вообще
        // берутся?». Обе подсказки называют сервис, который отвечает.
        // #460 (findings 3 / 22) было: `.diagExitSourceHint` — «Запрошено у
        // ipinfo.io через туннель»: три слова в узкой правой колонке строки,
        // где они разваливались в рваный столбик. Теперь подпись во всю ширину
        // и говорит, что именно измерено, а не только кто ответил.
        .diagExitNote:               "Твой выходной IP-адрес, определён через ipinfo.io по туннелю — город и страна берутся из того же ответа.",
        // #460 (findings 2 / 15): 1109 мс красным здесь и 133 мс на плашке
        // подключения назывались одинаково, и #460 объяснил разницу заметкой
        // на 250 символов.
        // #461: владелец дважды просил, чтобы числа СОВПАДАЛИ, а не чтобы ему
        // объяснили разницу. Теперь обе стороны берут лучший из нескольких
        // круговых замеров по одному живому соединению — заметке нечего
        // примирять, и строка называется тем же словом, что и плашки.
        // #461 было: «Время ответа» и `.diagResponseNote`.
        .diagResponseLabel:          "Задержка",
        // Число — это включённые источники, их может быть и один, поэтому
        // двоеточие, а не «%d сервисов».
        // #459 (audit): «ваш» → «твой» — вся остальная таблица на «ты».
        .diagIPSourceHint_fmt:       "Спрашивает твой адрес у публичных сервисов по текущему маршруту. Источников: %d.",
        .vpsReadAge_fmt:             "считано %@",
        .vpsManageServer:            "Управление сервером",
        .vpsAdvancedTitle_fmt:       "Управление: %@",
        .vpsAdvancedConnectionHeader:  "Подключение",
        .vpsAdvancedMaintenanceHeader: "Обслуживание",
        .vpsAdvancedRemoveHeader:      "Удаление",
        // Каждая опасная строка говорит, что именно она уничтожит, — этого не
        // умеет пункт меню, и ради этого экран и появился.
        .vpsAdvancedRebootFooter:      "Перезагружает сервер целиком. Всё, что на нём работает, остановится, пока он не поднимется.",
        .vpsAdvancedUninstallFooter:   "Удаляет все контейнеры olcrtc с этого сервера, папку развёртывания и ключ. Все сохранённые для него подключения перестанут работать.",
        .vpsAdvancedDeepUninstallFooter: "Удаляет с сервера все контейнеры, образы и каталоги olcrtc.",
        .vpsAdvancedRemoveHostFooter:  "Забывает этот сервер в приложении. На самой машине ничего не меняется.",

        // #460: раунды скриншотов 2–4.
        // #461 было: `.heroExitSourceNote` — целое предложение о происхождении
        // страны под строкой героя, на экране, который просили уместить в одну
        // страницу. То же самое один раз говорит `diagExitNote` на карточке.
        // Инструкция 26: авто-переключение уехало из настроек на экран с теми
        // самыми протоколами, между которыми оно переключает, и объяснение
        // ужалось с абзаца настроек до одной строки на карточке.
        .connectAutoSwitchHint:      "Если работающий протокол перестал отвечать — переключиться на другой на том же сервере.",

        // #461: при одном установленном протоколе у переключателя был заголовок
        // и ни одной строки. Подсказка называет экран, где это чинится (этот
        // экран не рисует кнопок, уводящих в другое место), и говорит, зачем
        // ставить второй, — ради этого переключатель и существует.
        .connectSwitcherOnlyOne:     "На этом сервере только один протокол",
        .connectSwitcherAddHint:     "Установи второй на вкладке «Серверы», чтобы переключаться, когда один перестанет работать.",

        // MARK: #463 Обновление комнаты Телемоста одной кнопкой
        // Яндекс гасит ссылку Телемоста через 24 часа после создания, и раньше
        // владелец чинил это руками по SSH — по тому самому каналу, который
        // перекрывают в белом списке. Теперь весь путь укладывается в один лист.

        // Ошибки создания комнаты. Каждая называет причину И следующий шаг; ни
        // одна не может нести куку сессии или внутреннее имя.
        .telemostErrNoAccount:       "Аккаунт Яндекса не привязан. Войди, чтобы создавать комнаты Телемоста.",
        .telemostErrSessionRejected: "Яндекс отклонил сохранённый вход. Войди заново.",
        .telemostErrRateLimited:     "Яндекс сейчас не даёт создавать встречи. Подожди минуту и попробуй снова.",
        .telemostErrNetwork:         "Не удалось связаться с Яндексом. Проверь соединение и попробуй снова.",
        .telemostErrMalformed:       "Яндекс прислал ответ, который приложение не смогло разобрать. Попробуй снова.",
        .telemostErrStatus_fmt:      "Яндекс вернул ошибку (HTTP %d). Попробуй через минуту.",

        // Веб-вход. Самая важная строка во всей функции: сохранённый вход
        // открывает весь аккаунт Яндекса без пароля, поэтому предупреждение
        // висит над веб-вью — до того, как что-то будет введено.
        .yandexLoginTitle:           "Вход в Яндекс",
        .yandexLoginWarning:         "Используй одноразовый аккаунт Яндекса. Устройство сохранит токен входа, который открывает почту, Диск и платежи этого аккаунта без пароля.",

        // Лист. Одно имя для пункта меню и для листа, который он открывает.
        .telemostNewRoomAction:      "Новая комната Телемоста",
        .telemostRoomServerLine_fmt: "Яндекс Телемост на «%@»",
        .telemostRoomExplainer:      "Ссылка Телемоста перестаёт работать через 24 часа после создания. Кнопка создаёт новую комнату в твоём аккаунте Яндекса и переключает сервер на неё.",
        .telemostRoomNoAccountTitle: "Аккаунт Яндекса не привязан",
        .telemostRoomNoAccountBody:  "Для создания комнаты нужен вход в Яндекс. Войди под одноразовым аккаунтом — токен хранится в Keychain и не покидает устройство.",
        .telemostRoomSignInAction:   "Войти в Яндекс",
        .telemostRoomIdleTitle:      "Аккаунт Яндекса привязан",
        .telemostRoomIdleBody:       "Одно нажатие создаёт комнату и переводит сервер в неё.",
        .telemostRoomCreateAction:   "Создать комнату и применить",
        .telemostRoomWorkingTitle:   "Выполняется",
        .telemostRoomWorkingCreate:  "Создаём комнату в Телемосте…",
        .telemostRoomWorkingApply:   "Передаём новую комнату на сервер…",
        .telemostRoomDoneTitle:      "Комната заменена",
        .telemostRoomDoneBody:       "Сервер в новой комнате. Её ссылка действует ближайшие 24 часа.",
        .telemostRoomFailedTitle:    "Не удалось завершить",
        .telemostRoomRetryAction:    "Повторить",
        .telemostRoomOtherAccountAction:  "Другой аккаунт",
        .telemostRoomForgetAccountAction: "Забыть этот аккаунт Яндекса",
        .telemostRoomKeychainNote:   "Токен входа хранится только в Keychain этого устройства.",

        // Опасность живой строки. Обновление протокола, через который идёт
        // туннель, перезапускает контейнер, несущий собственный SSH приложения, —
        // команда теряет транспорт на полпути. Говорим это прямо и первым
        // предлагаем безопасный путь, если он на сервере есть.
        .telemostRenewLiveSwitchable_fmt: "Сейчас соединение идёт через этот протокол. Замена комнаты перезапустит его, и соединение оборвётся. Сначала подключись через %@ — тогда не оборвётся.",
        .telemostRenewSwitchAction_fmt:   "Сначала подключиться через %@",
        .telemostRenewLiveOnly:      "Сейчас соединение идёт через этот протокол, а других на этом сервере нет. Замена комнаты перезапустит его, и соединение оборвётся посреди команды — приложение сохранит новую комнату и переподключится к ней.",
        .telemostRenewDropped_fmt:   "Соединение оборвалось, пока сервер переходил в комнату %@, — так и должно быть, когда обновляешь протокол, через который идёт соединение. Новая комната сохранена, идёт переподключение; запусти «Проверить» в меню протокола, чтобы убедиться, что сервер её принял.",
        .logsContainerPrimary:       "Основной",
        .vpsHeadlineProbeFailed:     "Не удалось проверить сервер",
        .subMetaUpdatedPull_fmt:     "Обновлено %@ · потяни вниз, чтобы обновить",
        .protocolStopAction:         "Остановить этот протокол",
        .protocolStartAction:        "Запустить этот протокол",
        .telemostExpiryTitle:        "Комната Телемоста скоро истечёт",
        .telemostExpiryBody_fmt:     "Комната под «%@» перестанет работать примерно через %d мин, и туннель уйдёт вместе с ней. Обновление сейчас оборвёт соединение на несколько секунд.",
        .telemostExpiryRenewAction:  "Обновить сейчас",
        .later:                      "Позже",
    ]
}
