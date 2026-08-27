import Foundation

// MARK: - SpeedTest
//
// Measures three values against a selectable speed-test provider:
//   - ping — #461 was: "TTFB, averaged across N samples, warmup discarded", by a
//     method of its own. It is `LatencyProbe.measure(via:)` now, the app's ONE
//     definition of latency, shared with the Connect tab's live readout.
//   - download throughput
//   - upload throughput
//
// Mode-aware (.direct or .tunnel) — see SOCKSSession for the session factory.
//
// #285: the tunnel is a narrow, high-latency pipe (vp8channel ≈ <1 Mbps), so the
// test degrades gracefully there — serial (not parallel) measurements, scaled-down
// payloads, longer timeouts, and ping failure tolerated (reported "n/a", not an
// error). The provider is user-selectable (Settings) since Cloudflare can be slow
// or blocked. A datachannel hint is surfaced when a slow video-transport tunnel is
// the bottleneck.

/// A selectable speed-test backend. Cloudflare is parametric (any byte count +
/// upload + trace ping); fixed-file providers (e.g. OVH) serve set sizes, have no
/// upload endpoint, and are pinged with a HEAD on the small file.
struct SpeedTestProvider: Identifiable, Equatable {
    let id: String
    let label: String           // shown in Settings + the log header
    let host: String
    let parametric: Bool        // Cloudflare-style `/__down?bytes=N` + `/__up`
    let supportsUpload: Bool
    let fixedSmallURL: String?  // tunnel payload (fixed-file providers)
    let fixedLargeURL: String?  // direct payload (fixed-file providers)

    /// Download URL for the given mode — tunnel gets the small payload.
    func downloadURL(mode: RouteMode) -> String {
        if parametric {
            let n = mode == .tunnel ? AppConstants.SpeedTest.downloadBytesTunnel
                                    : AppConstants.SpeedTest.downloadBytesDirect
            return "https://\(host)/__down?bytes=\(n)"
        }
        return (mode == .tunnel ? fixedSmallURL : fixedLargeURL) ?? ""
    }

    /// Upload endpoint, or nil when the provider has none (upload → n/a).
    var uploadURLString: String? { supportsUpload ? "https://\(host)/__up" : nil }

    /// A cheap HEAD target for the ping samples.
    func pingURL() -> String {
        parametric ? "https://\(host)/cdn-cgi/trace" : (fixedSmallURL ?? "https://\(host)/")
    }
}

/// Snapshot of one speed-test run: ping, download, and upload figures from a single provider.
struct SpeedResult {
    let service     : String       // provider that served the test
    let mode        : RouteMode
    let pingMs      : Double?
    let downloadMbps: Double?
    let uploadMbps  : Double?
    let error       : String?
}

/// Measures ping, download, and upload throughput against the selected provider,
/// optionally routing via the SOCKS5 tunnel to compare direct vs. tunnelled
/// performance. Publishes a single `lastResult`.
@MainActor
final class SpeedTest: ObservableObject {

    @Published var lastResult: SpeedResult?
    @Published var isTesting  = false

    // #461 was: `private let pingSamples` — read by `measurePing`, which is gone.

    /// `carrier`/`transport` (when tunnelled) are logged in the header and drive
    /// the datachannel speed hint; the caller passes them from the active record.
    func run(via mode: RouteMode, carrier: String? = nil, transport: String? = nil) async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }

        let provider = AppConstants.SpeedTest.provider(id: SettingsStore.shared.speedTestProviderID)

        LogStore.shared.startSession(.diagnostics)
        // #285: header records the provider + connection type (direct/tunnel, and
        // carrier/transport when tunnelled) so a slow run is interpretable.
        var header = "→ Speed test via \(provider.label) (\(mode.label))"
        if mode == .tunnel, let c = carrier, let t = transport { header += " — \(c)/\(t)" }
        LogStore.shared.log(.diagnostics, header)

        // Suppress keep-alive probes for the duration — extra tunnel connections
        // mid-test add congestion and cause keep-alive false failures.
        if mode == .tunnel { SOCKSSession.noteTunnelActivity(forAtLeast: 180) }

        let p: Double?, d: Double?, u: Double?
        if mode == .tunnel {
            // Serialise on the narrow pipe: parallel connections trigger
            // "remote not ready" on vp8channel. Each step tolerates its own
            // failure and still reports the others (partial results).
            // #461 was: `measurePing(mode:provider:)` — a THIRD definition of
            // latency (mean of cold samples, a fresh session each). One probe now.
            p = await LatencyProbe.measure(via: mode)
            d = await measureDownload(mode: mode, provider: provider)
            u = await measureUpload(mode: mode, provider: provider)
        } else {
            // Direct: parallel for speed.
            async let ping     = LatencyProbe.measure(via: mode)   // #461
            async let download = measureDownload(mode: mode, provider: provider)
            async let upload   = measureUpload(mode: mode, provider: provider)
            (p, d, u) = await (ping, download, upload)
        }

        if mode == .tunnel { SOCKSSession.noteTunnelActivity() }

        // Only an error when *everything* failed; a missing ping or upload is fine.
        let allFailed = p == nil && d == nil && u == nil
        let errorMsg  = allFailed ? L10n.speedAllFailed.localized() : nil
        lastResult = SpeedResult(service: provider.label, mode: mode,
                                 pingMs: p, downloadMbps: d, uploadMbps: u, error: errorMsg)

        // #291 was: ?? (provider.supportsUpload ? "n/a" : "—") — UL is now always
        // attempted (Cloudflare fallback for no-upload providers), so nil means the
        // attempt failed ("n/a"), not "no endpoint" ("—").
        let upStr = u.map { String(format: "%.2fMbps", $0) } ?? "n/a"
        LogStore.shared.log(.diagnostics,
            "  ping=\(p.map { String(format: "%.0fms", $0) } ?? "n/a") " +
            "down=\(d.map { String(format: "%.2fMbps", $0) } ?? "n/a") " +
            "up=\(upStr)")

        // #285: surface the lever — a slow video-transport tunnel is bandwidth-
        // limited by design; datachannel is far faster where the network allows.
        // Only hint on a *measured* slow download (not a total failure, which is
        // a connectivity problem datachannel wouldn't fix).
        let videoTransports = ["vp8channel", "seichannel", "videochannel"]
        if mode == .tunnel, let t = transport, videoTransports.contains(t), let d, d < 5 {
            LogStore.shared.log(.diagnostics, L10n.speedDatachannelHint.localized())
        }
    }

    // #454: the Connect tab's live latency readout. Name, signature and callers
    // are unchanged; it never touches `isTesting`/`lastResult` (a background
    // probe, not a user-run speed test) and returns nil on failure.
    //
    // boc #461
    // #461 was: ONE HEAD request on a BRAND-NEW `URLSession` — fresh SOCKS
    // connect + fresh TLS handshake, no warm-up, no averaging. Most of that
    // number was connection setup, which is why this row read ~947 ms while the
    // per-node chips, measuring a round-trip on an already-open connection, read
    // ~131 ms for the same server. The owner's complaint ("ping is 947 again,
    // while somewhere else it is different") was a real defect, not a
    // misreading: two numbers, one word.
    //
    // It delegates to `LatencyProbe` now — the app's single definition of
    // latency — so this figure and the chips' figure are produced by the same
    // METHOD. `LatencyProbe.measure` keeps the `SOCKSSession.noteTunnelActivity()`
    // side effect this function has always had (keep-alive skips its own probe
    // for one interval after that marker), and sets it on the FIRST successful
    // sample rather than the only one.
    func quickPing(via mode: RouteMode) async -> Double? {
        await LatencyProbe.measure(via: mode)
    }
    // eoc #461

    // MARK: Measurements

    // boc #461
    // #461 was: `measurePing(mode:provider:)` — `pingSamples` samples, a FRESH
    // `URLSession` per sample (so every one paid a cold SOCKS connect and TLS
    // handshake), sample 0 discarded, the MEAN returned. That was a THIRD
    // definition of latency, unnamed anywhere in the UI, feeding
    // `SpeedResult.pingMs`. `run()` calls `LatencyProbe.measure(via:)` now, so
    // the speed test's ping, the Connect tab's live readout and the per-node
    // chips are all the same measurement.
    //
    // The fresh-session-per-sample existed to dodge HTTP/2 error 310 when the
    // tunnel is busy with a concurrent transfer. `LatencyProbe` issues its
    // samples SEQUENTIALLY on one session, which cannot produce that, and
    // `run()` already serialises ping -> download -> upload in `.tunnel` mode.
    // eoc #461

    private func measureDownload(mode: RouteMode, provider: SpeedTestProvider) async -> Double? {
        guard let url = URL(string: provider.downloadURL(mode: mode)) else { return nil }
        let timeout = mode == .tunnel ? AppConstants.SpeedTest.xferTimeoutTunnel
                                      : AppConstants.SpeedTest.xferTimeoutDirect
        // #445 (audit fix 9): invalidate on exit — see LatencyProbe.
        let session = SOCKSSession.make(mode: mode, timeout: timeout)
        defer { session.finishTasksAndInvalidate() }
        do {
            let start = Date()
            let (data, _) = try await session.data(from: url)
            let elapsed = Date().timeIntervalSince(start)
            return Double(data.count) * 8 / elapsed / 1_000_000
        } catch {
            LogStore.shared.log(.diagnostics, "  download: n/a (\(error.localizedDescription))")
            return nil
        }
    }

    // POST a fixed buffer of zeros — content doesn't matter, only byte count.
    private func measureUpload(mode: RouteMode, provider: SpeedTestProvider) async -> Double? {
        // boc #291: OVH (and any fixed-file provider) has no upload sink, so UL used
        // to show nothing. Fall back to Cloudflare's parametric /__up so upload is
        // still measured against a real endpoint.
        let uploadProvider = AppConstants.SpeedTest.uploadProvider(for: provider)
        if uploadProvider.id != provider.id {
            // #311: route through L10n instead of a hardcoded interpolated string.
            LogStore.shared.log(.diagnostics,
                L10n.speedUploadFallback_fmt.formatted(provider.label, uploadProvider.label))
        }
        guard let urlStr = uploadProvider.uploadURLString, let url = URL(string: urlStr) else {
            return nil   // no upload endpoint even after fallback → reported as "—"
        }
        // eoc #291
        let bytes = mode == .tunnel ? AppConstants.SpeedTest.uploadBytesTunnel
                                    : AppConstants.SpeedTest.uploadBytesDirect
        let timeout = mode == .tunnel ? AppConstants.SpeedTest.xferTimeoutTunnel
                                      : AppConstants.SpeedTest.xferTimeoutDirect
        let body = Data(count: bytes)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        // #445 (audit fix 9): invalidate on exit — see LatencyProbe.
        let session = SOCKSSession.make(mode: mode, timeout: timeout)
        defer { session.finishTasksAndInvalidate() }
        do {
            let start = Date()
            _ = try await session.data(for: req)
            let elapsed = Date().timeIntervalSince(start)
            return Double(body.count) * 8 / elapsed / 1_000_000
        } catch {
            LogStore.shared.log(.diagnostics, "  upload: n/a (\(error.localizedDescription))")
            return nil
        }
    }
}

// MARK: - LatencyProbe (#461)
//
// #461: THE app's definition of latency, in one place.
//
// PARTITION NOTE: the design calls for this in its own file,
// `App/Services/LatencyProbe.swift`. This change may not create files, so it
// lives here, beside its only two callers. Move it out on the next
// `xcodegen generate` pass (`sources: - path: App` is a directory glob, so no
// project.yml edit is involved) — nothing about it is coupled to `SpeedTest`.
//
// THE PROBLEM IT SOLVES. Three functions used to measure "latency" and the two
// that reached the screen disagreed by ~8x under one word:
//   • `SpeedTest.quickPing` — one HEAD on a brand-new session every 8 s. Fresh
//     SOCKS connect, fresh TLS handshake, no warm-up, no averaging. ~947 ms.
//   • `NodeHealth.rttMs`, from the Go core's `Runtime.Ping` — a warm-up GET,
//     then three GETs over ONE kept-alive connection, BEST returned. ~131 ms.
//   • `SpeedTest.measurePing` — mean of cold samples, fresh session each. A
//     third method, never named in the UI, feeding `SpeedResult.pingMs`.
//
// This is method (2), reproduced over URLSession: one warm-up request that pays
// the SOCKS connect and the TLS handshake, then N samples over the SAME
// kept-alive session, and the BEST of them. Connection setup is EXCLUDED — the
// way every other round-trip figure in this app already excludes it — so the
// two numbers are comparable by construction rather than by explanation.
//
// WHAT IS LOST, stated plainly: setup cost is no longer displayed anywhere. It
// is paid once per connection, is already visible as the `.connecting` elapsed
// counter in the hero, and was never comparable to anything else printed here.
//
// A nonisolated `enum` of statics — the repo's stateless-service shape
// (`SOCKSSession`, `NetPing`, `PortAvailability`) — so it can run off the main
// actor and be called from the speed test and from the Connect tab's loop
// alike. It logs nothing: it runs every 8 s while the Connect tab is open, and
// a log line per sample would be the noisiest writer in the app.

enum LatencyProbe {

    /// One latency reading through `mode`, in milliseconds. nil = every sample
    /// failed (one bad sample is skipped, not fatal — #285's tolerance).
    static func measure(via mode: RouteMode) async -> Double? {
        let provider = AppConstants.SpeedTest.provider(id: SettingsStore.shared.speedTestProviderID)
        guard let url = URL(string: provider.pingURL()) else { return nil }
        let timeout = mode == .tunnel ? AppConstants.SpeedTest.pingTimeoutTunnel
                                      : AppConstants.SpeedTest.pingTimeoutDirect
        // ONE session for every sample — that is what makes samples 1…n
        // keep-alive, and it is the whole difference from what this replaced.
        let session = SOCKSSession.make(mode: mode, timeout: timeout)
        defer { session.finishTasksAndInvalidate() }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        var best: Double?
        // `pingSamples` is already 4 and already documents "first sample is
        // discarded as warmup" — warm-up + 3 timed samples. No constant changes.
        for i in 0..<AppConstants.SpeedTest.pingSamples {
            let start = Date()
            do {
                _ = try await session.data(for: req)
                // #461: THE SIDE EFFECT THAT MUST SURVIVE. Keep-alive skips its
                // own HTTP probe for one interval after this marker, and the old
                // `quickPing` set it on its single request. Set on the FIRST
                // success — including the warm-up, which is a real transfer
                // through the tunnel — not only at the end.
                if mode == .tunnel { SOCKSSession.noteTunnelActivity() }
                guard i > 0 else { continue }          // the warm-up is not a sample
                let ms = Date().timeIntervalSince(start) * 1000
                best = min(best ?? ms, ms)
            } catch {
                continue
            }
        }
        return best
    }
}
