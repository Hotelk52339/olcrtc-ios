import Foundation

// MARK: - VPNConfig (#vpn)
//
// The tunnel configuration handed from the main app to the packet-tunnel
// extension. Compiled into BOTH targets (olcrtc-ios and olcrtc-tunnel — the
// extension target lists this file explicitly in project.yml), and carried
// across the process boundary inside
// NETunnelProviderProtocol.providerConfiguration.
//
// providerConfiguration is a plist/JSON dictionary persisted by the system
// into the VPN configuration store, so every value here is limited to
// String / Int / Bool (enforced by the round-trip helpers below). No App
// Group and no keychain sharing is involved in v1 — which also means keyHex
// and wbToken ride the system VPN preferences; an accepted trade-off of the
// minimal-signing-surface decision (vpn-impl-decisions.md).
//
// vp8FPS / vp8Batch mirror OlcrtcConnection's per-connection overrides:
// nil = "let the Go core use its own defaults" (30 / 64, mobile/config.go),
// so the extension never needs SettingsStore. waitReadyTimeoutMs = 0 likewise
// defers to the core's default ready timeout (8 s, mobile/runtime.go).

struct VPNConfig: Codable, Equatable, Sendable {

    /// Loopback SOCKS5 port the core binds INSIDE the extension process.
    /// Fixed and private to the extension — unrelated to proxy mode's port.
    static let defaultSocksPort = 18080

    var carrier:   String        // MobileRuntime.setProvider — jitsi | telemost | wbstream | none
    var transport: String        // setTransport — datachannel | vp8channel | seichannel (videochannel is rejected in VPN mode)
    var roomID:    String        // setRoom — room ID or URL, verbatim
    var clientID:  String        // setDeviceID
    var keyHex:    String        // setKey — 64-char hex (32 bytes)
    var dns:       String        // setDNS — "host:port", e.g. "8.8.8.8:53"
    var vp8FPS:    Int?          // setVP8Options (vp8channel only); nil = core default
    var vp8Batch:  Int?          // setVP8Options (vp8channel only); nil = core default
    var seiFPS:    Int           // setSEIOptions (seichannel only)
    var seiBatch:  Int
    var seiFrag:   Int
    var seiACK:    Int
    var wbToken:   String        // setProviderToken — empty for non-wbstream carriers
    var waitReadyTimeoutMs: Int  // Runtime.waitReady; 0 = core default (8 s)
    var socksPort: Int           // in-extension loopback SOCKS port (defaultSocksPort)

    /// DNS server host with the port stripped, for NEDNSSettings(servers:).
    /// Handles "8.8.8.8:53", bracketed IPv6 "[2001:db8::1]:53", and a bare
    /// host with no port.
    var dnsHost: String {
        let raw = dns.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("["), let close = raw.firstIndex(of: "]") {
            return String(raw[raw.index(after: raw.startIndex)..<close])
        }
        // A lone colon separates host:port; multiple colons without brackets
        // mean a bare IPv6 host (no port to strip).
        let parts = raw.split(separator: ":")
        if parts.count == 2, let first = parts.first { return String(first) }
        return raw
    }

    // MARK: Construction

    init(carrier: String, transport: String, roomID: String, clientID: String,
         keyHex: String, dns: String, vp8FPS: Int? = nil, vp8Batch: Int? = nil,
         seiFPS: Int = 30, seiBatch: Int = 10, seiFrag: Int = 1200, seiACK: Int = 1,
         wbToken: String = "", waitReadyTimeoutMs: Int = 0,
         socksPort: Int = VPNConfig.defaultSocksPort) {
        self.carrier   = carrier
        self.transport = transport
        self.roomID    = roomID
        self.clientID  = clientID
        self.keyHex    = keyHex
        self.dns       = dns
        self.vp8FPS    = vp8FPS
        self.vp8Batch  = vp8Batch
        self.seiFPS    = seiFPS
        self.seiBatch  = seiBatch
        self.seiFrag   = seiFrag
        self.seiACK    = seiACK
        self.wbToken   = wbToken
        self.waitReadyTimeoutMs = waitReadyTimeoutMs
        self.socksPort = socksPort
    }

    // App-target-only bridge. OlcrtcConnection is NOT compiled into the
    // olcrtc-tunnel target (it would drag OlcrtcURI → L10n/SettingsStore/
    // LogStore along), so project.yml must add OLCRTC_TUNNEL_EXTENSION to the
    // tunnel target's SWIFT_ACTIVE_COMPILATION_CONDITIONS to exclude this
    // init there. The extension only ever uses init?(providerConfiguration:).
    #if !OLCRTC_TUNNEL_EXTENSION
    /// Builds the extension config from a saved connection. `key`/`wbToken`
    /// must already be restored from ConnectionSecretStore (they are Keychain-
    /// only and never ride OlcrtcConnection's own Codable form).
    ///
    /// `fallbackVP8FPS`/`fallbackVP8Batch` are the app-global values (from
    /// SettingsStore); the per-connection overrides win, matching
    /// OlcrtcEngine's `params.vp8FPS ?? settings.vp8FPS` resolution. Leaving
    /// them nil defers to the Go core's own defaults.
    init(from connection: OlcrtcConnection, dns: String, timeoutMs: Int,
         socksPort: Int = VPNConfig.defaultSocksPort,
         fallbackVP8FPS: Int? = nil, fallbackVP8Batch: Int? = nil) {
        self.init(
            carrier:   connection.carrier,
            transport: connection.transport,
            roomID:    connection.roomID,
            clientID:  connection.clientID,
            keyHex:    connection.key,
            dns:       dns,
            vp8FPS:    connection.vp8FPS       ?? fallbackVP8FPS,
            vp8Batch:  connection.vp8BatchSize ?? fallbackVP8Batch,
            seiFPS:    connection.seiFPS,
            seiBatch:  connection.seiBatch,
            seiFrag:   connection.seiFrag,
            seiACK:    connection.seiACK,
            wbToken:   connection.wbToken,
            waitReadyTimeoutMs: timeoutMs,
            socksPort: socksPort)
    }
    #endif

    // MARK: providerConfiguration round-trip

    /// One shared key set for Codable AND the providerConfiguration dict, so
    /// the two serialisations can never drift.
    private enum CodingKeys: String, CodingKey {
        case carrier, transport, roomID, clientID, keyHex, dns
        case vp8FPS, vp8Batch
        case seiFPS, seiBatch, seiFrag, seiACK
        case wbToken, waitReadyTimeoutMs, socksPort
    }

    /// Plist/JSON-safe dictionary for NETunnelProviderProtocol
    /// .providerConfiguration. Values are String/Int only; nil vp8 overrides
    /// are omitted entirely (absence = core default).
    func providerConfiguration() -> [String: Any] {
        var dict: [String: Any] = [
            CodingKeys.carrier.rawValue:   carrier,
            CodingKeys.transport.rawValue: transport,
            CodingKeys.roomID.rawValue:    roomID,
            CodingKeys.clientID.rawValue:  clientID,
            CodingKeys.keyHex.rawValue:    keyHex,
            CodingKeys.dns.rawValue:       dns,
            CodingKeys.seiFPS.rawValue:    seiFPS,
            CodingKeys.seiBatch.rawValue:  seiBatch,
            CodingKeys.seiFrag.rawValue:   seiFrag,
            CodingKeys.seiACK.rawValue:    seiACK,
            CodingKeys.wbToken.rawValue:   wbToken,
            CodingKeys.waitReadyTimeoutMs.rawValue: waitReadyTimeoutMs,
            CodingKeys.socksPort.rawValue: socksPort,
        ]
        if let vp8FPS   { dict[CodingKeys.vp8FPS.rawValue]   = vp8FPS }
        if let vp8Batch { dict[CodingKeys.vp8Batch.rawValue] = vp8Batch }
        return dict
    }

    /// Rebuilds the config in the extension process. Returns nil when any
    /// required field is missing or mistyped (the provider then fails
    /// startTunnel with .configurationInvalid). Numeric values come back from
    /// the system as NSNumber; `as? Int` bridges them.
    init?(providerConfiguration dict: [String: Any]) {
        guard
            let carrier   = dict[CodingKeys.carrier.rawValue]   as? String,
            let transport = dict[CodingKeys.transport.rawValue] as? String,
            let roomID    = dict[CodingKeys.roomID.rawValue]    as? String,
            let clientID  = dict[CodingKeys.clientID.rawValue]  as? String,
            let keyHex    = dict[CodingKeys.keyHex.rawValue]    as? String,
            let dns       = dict[CodingKeys.dns.rawValue]       as? String
        else { return nil }
        self.init(
            carrier:   carrier,
            transport: transport,
            roomID:    roomID,
            clientID:  clientID,
            keyHex:    keyHex,
            dns:       dns,
            vp8FPS:    dict[CodingKeys.vp8FPS.rawValue]   as? Int,
            vp8Batch:  dict[CodingKeys.vp8Batch.rawValue] as? Int,
            seiFPS:    dict[CodingKeys.seiFPS.rawValue]   as? Int ?? 30,
            seiBatch:  dict[CodingKeys.seiBatch.rawValue] as? Int ?? 10,
            seiFrag:   dict[CodingKeys.seiFrag.rawValue]  as? Int ?? 1200,
            seiACK:    dict[CodingKeys.seiACK.rawValue]   as? Int ?? 1,
            wbToken:   dict[CodingKeys.wbToken.rawValue]  as? String ?? "",
            waitReadyTimeoutMs: dict[CodingKeys.waitReadyTimeoutMs.rawValue] as? Int ?? 0,
            socksPort: dict[CodingKeys.socksPort.rawValue] as? Int ?? VPNConfig.defaultSocksPort)
    }
}
