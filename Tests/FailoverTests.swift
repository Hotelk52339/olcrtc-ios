import XCTest
@testable import olcrtc_ios

// #453: unit tests for the auto-failover pure helpers on TunnelManager
// (nextFailoverCandidate / failoverRank) and the store-backed candidate
// resolver (computeFailoverCandidates).
//
// The async reconnect loop that consumes these helpers (requestReconnect's
// failover hop) is integration-only — it launches a real engine task and can't
// be driven deterministically in the test host — so it is intentionally NOT
// covered here; only the pure decision surface is.
//
// computeFailoverCandidates reads the two @MainActor stores, whose didSet
// persists to UserDefaults, so this suite snapshots + restores
// `olcrtc_records_v2` and `olcrtc_server_hosts`. All records use empty secrets,
// so ConnectionStore.save() never writes the Keychain (it only upserts
// non-empty ones).
@MainActor
final class FailoverTests: XCTestCase {

    private let recordsKey = "olcrtc_records_v2"
    private let hostsKey    = "olcrtc_server_hosts"
    private var recordsSnapshot: Data?
    private var hostsSnapshot: Data?

    override func setUp() {
        super.setUp()
        recordsSnapshot = UserDefaults.standard.data(forKey: recordsKey)
        hostsSnapshot   = UserDefaults.standard.data(forKey: hostsKey)
    }

    override func tearDown() {
        if let d = recordsSnapshot { UserDefaults.standard.set(d, forKey: recordsKey) }
        else { UserDefaults.standard.removeObject(forKey: recordsKey) }
        if let d = hostsSnapshot { UserDefaults.standard.set(d, forKey: hostsKey) }
        else { UserDefaults.standard.removeObject(forKey: hostsKey) }
        super.tearDown()
    }

    // MARK: helpers

    private func record(_ name: String, carrier: String = "jitsi",
                        transport: String = "datachannel") -> ConnectionRecord {
        let conn = OlcrtcConnection(carrier: carrier, transport: transport,
                                    roomID: "room-\(name)", key: "", clientID: "default")
        return ConnectionRecord(name: name, details: .olcrtc(conn))
    }

    // MARK: nextFailoverCandidate

    func testNextFailoverSkipsCurrentAndTried() {
        let a = record("a"), b = record("b"), c = record("c")
        // current is `a`; `a` and `b` already tried → next is `c`.
        let next = TunnelManager.nextFailoverCandidate(
            current: a, candidates: [a, b, c], tried: [a.id, b.id])
        XCTAssertEqual(next?.id, c.id)
    }

    func testNextFailoverPreservesOrder() {
        let a = record("a"), b = record("b"), c = record("c")
        // nothing tried but the seed (current); first non-current wins.
        let next = TunnelManager.nextFailoverCandidate(
            current: a, candidates: [a, b, c], tried: [a.id])
        XCTAssertEqual(next?.id, b.id)
    }

    func testNextFailoverNilWhenExhausted() {
        let a = record("a"), b = record("b")
        let next = TunnelManager.nextFailoverCandidate(
            current: a, candidates: [a, b], tried: [a.id, b.id])
        XCTAssertNil(next)
    }

    func testNextFailoverNilWhenNoCandidates() {
        let a = record("a")
        XCTAssertNil(TunnelManager.nextFailoverCandidate(
            current: a, candidates: [], tried: [a.id]))
    }

    // MARK: failoverRank

    func testFailoverRankOrdersBestFirst() {
        // jitsi/datachannel is the recommended combo (rank 0); telemost/vp8channel
        // is ok (rank 1); wbstream/datachannel is unstable (rank 2). Exact ranks
        // track CarrierTransportMatrix, so assert the ORDERING, not the integers.
        let rec = TunnelManager.failoverRank(carrier: "jitsi", transport: "datachannel")
        let ok  = TunnelManager.failoverRank(carrier: "telemost", transport: "vp8channel")
        let bad = TunnelManager.failoverRank(carrier: "wbstream", transport: "datachannel")
        XCTAssertLessThan(rec, ok)
        XCTAssertLessThan(ok, bad)
        XCTAssertGreaterThanOrEqual(rec, 0)
        XCTAssertLessThanOrEqual(bad, 3)
    }

    func testFailoverRankFailCombosAreWorst() {
        // telemost/datachannel is a broken combo (matrix .fail → rank 3).
        XCTAssertEqual(TunnelManager.failoverRank(carrier: "telemost", transport: "datachannel"), 3)
    }

    // MARK: computeFailoverCandidates

    func testComputeCandidatesMatchesHostViaPrimaryAndExtras() {
        let store = ConnectionStore()
        let serverStore = ServerHostStore()

        let primary = record("primary", carrier: "wbstream", transport: "vp8channel")
        let extra1  = record("extra1",  carrier: "jitsi",    transport: "datachannel")
        let extra2  = record("extra2",  carrier: "telemost", transport: "vp8channel")
        let unrelated = record("unrelated")
        store.connections = [primary, extra1, extra2, unrelated]

        var host = ServerHost(label: "H", host: "1.2.3.4")
        host.lastConnectionID  = primary.id
        host.extraConnectionIDs = [extra1.id, extra2.id]
        serverStore.hosts = [host]

        // From `primary`: the two extras, best-first by matrix rank
        // (jitsi/datachannel recommended < telemost/vp8channel ok). `unrelated`
        // (not on the host) and `primary` itself are excluded.
        let cands = TunnelManager.computeFailoverCandidates(primary, store: store, serverStore: serverStore)
        XCTAssertEqual(cands.map(\.id), [extra1.id, extra2.id])
    }

    func testComputeCandidatesFromAnExtraExcludesItself() {
        let store = ConnectionStore()
        let serverStore = ServerHostStore()
        let primary = record("primary", carrier: "jitsi",    transport: "datachannel")
        let extra   = record("extra",   carrier: "telemost", transport: "vp8channel")
        store.connections = [primary, extra]
        var host = ServerHost(label: "H", host: "1.2.3.4")
        host.lastConnectionID = primary.id
        host.extraConnectionIDs = [extra.id]
        serverStore.hosts = [host]

        // Matching the host via an EXTRA id, `extra` is excluded, `primary` remains.
        let cands = TunnelManager.computeFailoverCandidates(extra, store: store, serverStore: serverStore)
        XCTAssertEqual(cands.map(\.id), [primary.id])
    }

    func testComputeCandidatesEmptyWhenNoHostMatches() {
        let store = ConnectionStore()
        let serverStore = ServerHostStore()
        let lonely = record("lonely")
        store.connections = [lonely]
        serverStore.hosts = []   // no host links this record
        XCTAssertTrue(TunnelManager.computeFailoverCandidates(lonely, store: store, serverStore: serverStore).isEmpty)
    }

    func testComputeCandidatesEmptyWhenStoresNil() {
        let lonely = record("lonely")
        XCTAssertTrue(TunnelManager.computeFailoverCandidates(lonely, store: nil, serverStore: nil).isEmpty)
    }
}
