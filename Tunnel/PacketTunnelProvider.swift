import Foundation
import NetworkExtension
import Mobile

// MARK: - PacketTunnelProvider (#vpn)
//
// The system-VPN provider (target olcrtc-tunnel, NSExtensionPrincipalClass).
// It runs the ENTIRE olcrtc Go core in the extension process — the app can be
// suspended while the tunnel runs, and NEPacketTunnelFlow packets arrive here —
// plus the tunstack tun2socks layer from the same Mobile.xcframework:
//
//   packetFlow.readPackets ──▶ TunstackTunnel.writePacket ──▶ lwIP ──▶
//   SOCKS5 CONNECT to 127.0.0.1:<socksPort> (the in-process core listener)
//   ──▶ olcrtc carrier ▶ … and back via TunWriter ──▶ packetFlow.writePackets
//
// Loop avoidance: iOS routes provider-process-originated sockets (pion
// ICE/DTLS, the core's protected DNS) to the underlying interface, NOT into
// this tunnel — so there are NO excludedRoutes and includeAllNetworks is
// NEVER set (it would pull our own traffic into the tunnel and loop).
//
// Memory: the extension lives under a ~50 MB jetsam cap. Before the core
// starts we set a 30 MiB Go soft memory limit + GC at 20% (shim
// MobileTuneForNetworkExtension) and shrink smux receive buffers from
// 32 MiB/4 MiB to 8 MiB/1 MiB (MobileSetMuxBuffers); memory-pressure events
// trigger MobileFreeOSMemory.
//
// UDP: the core's SOCKS5 is CONNECT-only, so no UDP crosses the tunnel.
// tunstack's dnstruncate answers UDP DNS with the TC bit → the OS resolver
// retries DNS over TCP:53 through the tunnel; all other UDP is dropped
// (QUIC falls back to TCP; mandatory-UDP apps do not work in VPN mode).
//
// NAMING CAUTION — this machine cannot run gomobile; verify the generated
// selector names against Mobile.objc.h on the first CI bind:
//   MobileNew() -> MobileRuntime?                      (mobile.New)
//   MobileSetLogWriter(MobileLogWriterProtocol?)       (logbridge shim)
//   MobileTuneForNetworkExtension(Int64)               (memory shim)
//   MobileSetMuxBuffers(Int, Int)                      (memory shim)
//   MobileFreeOSMemory()                               (memory shim)
//   TunstackNewTunnel(String?, Int, TunstackTunWriterProtocol?, NSErrorPointer) -> TunstackTunnel?
//   TunstackTunnel.writePacket(Data?) throws           (WritePacket([]byte) error)
//   TunstackTunnel.close() throws / rxBytes() -> Int64 / txBytes() -> Int64
//   TunstackTunWriterProtocol { func writePacket(_ p: Data?) }
//   runtime.set*(...) throws for error-returning Go setters; state()/isRunning()

final class PacketTunnelProvider: NEPacketTunnelProvider {

    /// Matches OlcrtcEngine.stopTimeoutMs — Runtime.Stop blocks until the
    /// generation's goroutine exits or this many ms pass.
    private static let stopTimeoutMs = 5_000

    /// Serialises start/stop/teardown so completion-handler callbacks and the
    /// system's stop cannot race the blocking Go calls.
    private let workQueue = DispatchQueue(label: "io.github.hotelk52339.olcrtc-ios.tunnel.work")

    private var runtime: MobileRuntime?
    private var tunnel: TunstackTunnel?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var startedAt: Date?

    private let logBuffer = LogRingBuffer(capacity: 400)
    private let logCapture = ExtensionLogCapture()

    // MARK: Start

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let dict = proto.providerConfiguration,
              let config = VPNConfig(providerConfiguration: dict) else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }
        // videochannel runs a real 1080p VP8 codec (~16 MiB decoder queue per
        // remote track) — it cannot fit the extension's memory cap. VPN mode
        // allows datachannel / vp8channel / seichannel only (the latter two
        // are header-wrapping fakes with no codec).
        guard config.transport != "videochannel" else {
            logBuffer.append("startTunnel rejected: videochannel transport exceeds the Network Extension memory budget")
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }
        workQueue.async { self.doStart(config, completionHandler) }
    }

    private func doStart(_ config: VPNConfig, _ completionHandler: @escaping (Error?) -> Void) {
        // Memory knobs FIRST: the smux limits are read when a session is
        // created, and the GC limit should precede any real allocation.
        MobileTuneForNetworkExtension(30 << 20)      // 30 MiB Go soft limit + GC 20%
        MobileSetMuxBuffers(8 << 20, 1 << 20)        // smux session 8 MiB, stream 1 MiB

        // Core log lines -> in-extension ring buffer (served via
        // handleAppMessage "logs"; no App Group in v1, by design).
        // Capture the buffer, not self: logCapture is retained by the Go side
        // via MobileSetLogWriter and must not create a cycle through self.
        logCapture.onLog = { [buffer = logBuffer] line in buffer.append(line) }
        MobileSetLogWriter(logCapture)

        guard let rt = MobileNew() else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }

        // Setter sequence mirrors OlcrtcEngine.start (App/Core/TunnelEngine
        // .swift); master's setters VALIDATE and THROW — surface the Go error.
        do {
            try rt.setDNS(config.dns)
            try rt.setProvider(config.carrier)      // jitsi | telemost | wbstream | none
            try rt.setTransport(config.transport)
            try rt.setRoom(config.roomID)           // ID or URL, verbatim
            rt.setDeviceID(config.clientID)
            try rt.setKey(config.keyHex)
            if config.transport == "vp8channel", let fps = config.vp8FPS, let batch = config.vp8Batch {
                try rt.setVP8Options(fps, batchSize: batch)
                // nil overrides fall through to the core defaults (30 / 64).
            }
            if config.transport == "seichannel" {
                try rt.setSEIOptions(config.seiFPS, batchSize: config.seiBatch,
                                     fragmentSize: config.seiFrag,
                                     ackTimeoutMillis: config.seiACK)
            }
            // Same gentle liveness values as proxy mode (#230).
            try rt.setLivenessOptions(30_000, timeoutMillis: 10_000, failures: 3)
            // Unconditional: empty clears a previous token (same rule as #436).
            rt.setProviderToken(config.wbToken)
            // Loopback listener, private to this process. NO SOCKS credentials:
            // the core requires them only for non-loopback binds, and the
            // tunstack SOCKS client deliberately sends none.
            try rt.setSocksListenHost("127.0.0.1")
            try rt.setSocksPort(config.socksPort)
        } catch {
            logBuffer.append("configure failed: \(error.localizedDescription)")
            completionHandler(error)
            return
        }

        do {
            try rt.start()                          // spawns the run goroutine
        } catch {
            logBuffer.append("start failed: \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        runtime = rt

        do {
            // Blocks until the carrier rendezvoused and the SOCKS listener is
            // up (0 -> core default 8 s). Safe to block: we are on workQueue.
            try rt.waitReady(config.waitReadyTimeoutMs)
        } catch {
            logBuffer.append("waitReady failed: \(error.localizedDescription)")
            try? rt.stop(Self.stopTimeoutMs)
            runtime = nil
            completionHandler(error)
            return
        }

        // tun2socks against the now-ready loopback listener.
        let writer = FlowWriter(flow: packetFlow)
        var bindError: NSError?
        guard let tun = TunstackNewTunnel("127.0.0.1", config.socksPort, writer, &bindError) else {
            let error = bindError ?? NEVPNError(.connectionFailed) as NSError
            logBuffer.append("tunstack failed: \(error.localizedDescription)")
            try? rt.stop(Self.stopTimeoutMs)
            runtime = nil
            completionHandler(error)
            return
        }
        tunnel = tun

        setTunnelNetworkSettings(Self.makeSettings(dnsHost: config.dnsHost)) { [weak self] settingsError in
            guard let self else {
                completionHandler(NEVPNError(.connectionFailed))
                return
            }
            self.workQueue.async {
                if let settingsError {
                    self.logBuffer.append("setTunnelNetworkSettings failed: \(settingsError.localizedDescription)")
                    self.teardownLocked()
                    completionHandler(settingsError)
                    return
                }
                self.startedAt = Date()
                self.installMemoryPressureHandler()
                self.startLivenessWatch()   // #469
                self.startPacketPump()
                self.logBuffer.append("tunnel up: \(config.carrier)/\(config.transport), socks 127.0.0.1:\(config.socksPort)")
                completionHandler(nil)
            }
        }
    }

    // MARK: Network settings

    static func makeSettings(dnsHost: String) -> NEPacketTunnelNetworkSettings {
        // tunnelRemoteAddress is a placeholder — a WebRTC carrier has no
        // stable remote IP. 198.18.0.0/24 is the RFC 2544 benchmark range
        // (collision-free with real LANs).
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]        // 0.0.0.0/0
        // NO excludedRoutes (provider-own sockets bypass the tunnel on iOS)
        // and NEVER includeAllNetworks (would loop our own carrier traffic).
        settings.ipv4Settings = ipv4
        // boc #469 was: no ipv6Settings at all — "v1 is IPv4-only: on v6-capable
        // networks IPv6 traffic BYPASSES the tunnel". On a dual-stack carrier
        // (the norm here) every host with an AAAA record was reached DIRECTLY
        // from the real address while the hero said "everything on this
        // device". Claim the v6 default route so that traffic enters the tunnel
        // — where the pump drops it (AF_INET only) — instead of leaking. A
        // blackhole is honest; a bypass is not. ULA address, RFC 4193.
        let ipv6 = NEIPv6Settings(addresses: ["fd6f:6c63:7274:6300::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]        // ::/0
        settings.ipv6Settings = ipv6
        // eoc #469
        settings.dnsSettings = NEDNSSettings(servers: [dnsHost])  // host only, e.g. "8.8.8.8"
        settings.mtu = NSNumber(value: 1500)
        return settings
    }

    // MARK: Packet pump (OS -> lwIP)

    private func startPacketPump() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, let tunnel = self.tunnel else { return }  // stops the pump after teardown
            for (index, packet) in packets.enumerated() {
                // AF_INET only in v1 — matches the IPv4-only settings above.
                if index < protocols.count, protocols[index].int32Value == AF_INET {
                    try? tunnel.writePacket(packet)
                }
            }
            self.startPacketPump()
        }
    }

    // MARK: Memory pressure

    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                             queue: workQueue)
        source.setEventHandler { [weak self] in
            self?.logBuffer.append("memory pressure: releasing Go heap to the OS")
            MobileFreeOSMemory()
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: Stop

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        workQueue.async {
            self.logBuffer.append("stopTunnel: reason \(reason.rawValue)")
            self.teardownLocked()
            completionHandler()
        }
    }

    /// Must run on workQueue. Order matters: close the tun2socks device first
    /// (releases the lwIP per-process singleton and ends the pump), then stop
    /// the Go runtime (blocks up to stopTimeoutMs for the WebRTC teardown).
    // boc #469: the provider had no liveness loop and never called
    // `cancelTunnelWithError`. When the carrier session ended (liveness
    // failures, room closed, the server container restarted) the run goroutine
    // exited and the loopback SOCKS listener closed — but NEVPNStatus stayed
    // `.connected`, the hero stayed green, and every app on the device was
    // black-holed until the user noticed. The runtime already knows it is dead;
    // ask it, and hand the verdict to the system so the status becomes true.
    private var livenessTimer: DispatchSourceTimer?

    private func startLivenessWatch() {
        livenessTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, let rt = self.runtime else { return }
            if !rt.isRunning() {
                self.logBuffer.append("core stopped (\(rt.state())) — cancelling the tunnel so the system knows")
                self.livenessTimer?.cancel()
                self.livenessTimer = nil
                self.cancelTunnelWithError(NEVPNError(.connectionFailed))
            }
        }
        timer.resume()
        livenessTimer = timer
    }
    // eoc #469

    private func teardownLocked() {
        livenessTimer?.cancel()          // #469
        livenessTimer = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        try? tunnel?.close()
        tunnel = nil
        try? runtime?.stop(Self.stopTimeoutMs)
        runtime = nil
        startedAt = nil
    }

    // MARK: App messages ("stats" / "logs" from VPNController)

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }
        let message = String(data: messageData, encoding: .utf8) ?? ""
        workQueue.async {
            switch message {
            case "stats":
                completionHandler(self.statsJSON())
            case "logs":
                let text = self.logBuffer.tail().joined(separator: "\n")
                completionHandler(Data(text.utf8))
            default:
                completionHandler(nil)
            }
        }
    }

    /// Runs on workQueue. JSON keys are consumed by VPNController.stats().
    private func statsJSON() -> Data? {
        var stats: [String: Any] = [
            "state":        runtime?.state() ?? "idle",
            "running":      runtime?.isRunning() ?? false,
            "tunnelActive": tunnel != nil,
        ]
        if let tunnel {
            stats["rxBytes"] = tunnel.rxBytes()   // toward the device
            stats["txBytes"] = tunnel.txBytes()   // from the device
        }
        if let startedAt {
            stats["uptimeSeconds"] = Int(Date().timeIntervalSince(startedAt))
        }
        return try? JSONSerialization.data(withJSONObject: stats)
    }
}

// MARK: - FlowWriter (lwIP -> OS)
//
// Go-side TunWriter: tunstack's read pump calls writePacket from a Go
// goroutine for every outbound IP packet. gomobile only guarantees the Data
// view of a Go []byte for the duration of the call, so copy before handing it
// to writePackets (which retains).
private final class FlowWriter: NSObject, TunstackTunWriterProtocol {
    private let flow: NEPacketTunnelFlow
    init(flow: NEPacketTunnelFlow) { self.flow = flow }

    func writePacket(_ p: Data?) {
        guard let p, !p.isEmpty else { return }
        flow.writePackets([Data(p)], withProtocols: [NSNumber(value: AF_INET)])
    }
}

// MARK: - ExtensionLogCapture
//
// Same bridge as TunnelEngine's LogCapture, but for the extension process
// (each process statically links its own Go runtime, so MobileSetLogWriter
// here only affects this process). Feeds the ring buffer, not LogStore.
private final class ExtensionLogCapture: NSObject, MobileLogWriterProtocol {
    var onLog: ((String) -> Void)?
    func writeLog(_ msg: String?) {
        guard let msg = msg?.trimmingCharacters(in: .whitespacesAndNewlines),
              !msg.isEmpty else { return }
        onLog?(msg)
    }
}

// MARK: - LogRingBuffer
//
// Fixed-capacity, thread-safe line buffer: the Go log writer appends from
// arbitrary goroutine threads, handleAppMessage reads on workQueue.
final class LogRingBuffer {
    private let capacity: Int
    private var lines: [String] = []
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    func tail(_ maxLines: Int = Int.max) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(lines.suffix(maxLines))
    }
}
