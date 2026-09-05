import XCTest
@testable import olcrtc_ios

// #477: the system tunnel is this app's OWN packet-tunnel extension, and it can
// come up without `connect()` ever running — the user flips the profile on in
// iOS Settings or Control Centre, or it was left running across a launch.
//
// The bridge used to drop those notifications (`guard activeMode == .vpn`), so
// the in-app proxy kept its own session open and the SAME clientID sat in the
// carrier room twice. The server records the collision plainly —
// `Current peers count: 2, Devices: [default, default]` — and two peers sharing
// one identity break each other: the proxy session went silent
// (`control missed pong` → `reason=liveness`), recovery re-entered a room whose
// identity was taken, spent its budget, and landed in `.failed`. That is the
// "Connection failed" that lasted until the VPN was switched off.
//
// The parts with a synchronous or pure surface are pinned here. Adoption itself
// runs through NEVPNStatus and is integration-only; it is documented at its site
// in App/Core/TunnelManager.swift (`adoptSystemTunnel`).
@MainActor
final class SystemTunnelAdoptionTests: XCTestCase {

    private var savedLanguage = ""
    private var savedTunnelMode: TunnelMode = .proxy
    private let healthKey = "olcrtc_health_v1"
    private var healthSnapshot: Data?

    override func setUp() {
        super.setUp()
        savedLanguage   = SettingsStore.shared.language
        savedTunnelMode = SettingsStore.shared.tunnelMode
        SettingsStore.shared.language = "en"
        healthSnapshot = UserDefaults.standard.data(forKey: healthKey)
    }

    override func tearDown() {
        SettingsStore.shared.tunnelMode = savedTunnelMode
        SettingsStore.shared.language   = savedLanguage
        SettingsStore.flushPendingWrites()
        HealthCoordinator.shared._resetForTesting()
        HealthCoordinator.flushPendingWrites()
        if let d = healthSnapshot { UserDefaults.standard.set(d, forKey: healthKey) }
        else { UserDefaults.standard.removeObject(forKey: healthKey) }
        super.tearDown()
    }

    private func params(transport: String = "vp8channel") -> OlcrtcConnection {
        OlcrtcConnection(carrier: "jitsi", transport: transport,
                         roomID: "room-1", key: String(repeating: "a", count: 64),
                         clientID: "ios-test")
    }

    // MARK: - The verdict table

    // In PROXY mode the app's own state says nothing about a tunnel it did not
    // start, so the observed NEVPNStatus is the only evidence there is.
    func testProxyModeReadsTheObservedVPNStatus() {
        for status: VPNController.Status in [.connected, .connecting, .reasserting] {
            XCTAssertTrue(
                TunnelManager.systemTunnelIsUp(activeMode: .proxy, state: .disconnected,
                                               vpnStatus: status),
                "\(status) carries the device even though this app runs the proxy")
        }
        for status: VPNController.Status in [.invalid, .disconnected, .disconnecting] {
            XCTAssertFalse(
                TunnelManager.systemTunnelIsUp(activeMode: .proxy, state: .connected,
                                               vpnStatus: status),
                "\(status) is not a live tunnel")
        }
    }

    // #472's rule survives: iOS installs the routes when the provider answers
    // `startTunnel`, which is BEFORE the app reaches `.connected`, so only
    // `.disconnected`/`.failed` are provably route-free.
    func testVPNModeStillYieldsOnEveryStateThatMayHoldRoutes() {
        for state: ConnectionState in [.connecting, .connected, .waitingForNetwork] {
            XCTAssertTrue(
                TunnelManager.systemTunnelIsUp(activeMode: .vpn, state: state,
                                               vpnStatus: .invalid),
                "\(state) may already own the routes")
        }
        for state: ConnectionState in [.disconnected, .failed("x")] {
            XCTAssertFalse(
                TunnelManager.systemTunnelIsUp(activeMode: .vpn, state: state,
                                               vpnStatus: .invalid),
                "\(state) is provably route-free")
        }
    }

    // The regression this whole task exists for: proxy mode + a tunnel someone
    // else started must NOT read as "no tunnel", which is what sent probes out
    // through it and let the proxy keep a duplicate identity in the room.
    func testAProxySessionUnderAnExternallyStartedTunnelIsNotTreatedAsUntunnelled() {
        XCTAssertTrue(
            TunnelManager.systemTunnelIsUp(activeMode: .proxy, state: .connected,
                                           vpnStatus: .connected),
            "#477 was: `activeMode == .vpn` only — the app's belief, not the device's routes")
    }

    // MARK: - connect() treats a backend switch as a switch

    // #477 was: `guard let live = lastRecord, live.id != record.id else { return }`
    // compared the record alone, so flipping the mode and reconnecting to the
    // same record silently left the user on the old backend.
    func testSwitchingBackendOnTheSameRecordActuallySwitches() {
        SettingsStore.shared.tunnelMode = .proxy
        let manager = TunnelManager()
        // videochannel is valid for the proxy and refused by the appex, so the
        // VPN branch answers synchronously and no NetworkExtension call happens.
        let record = ConnectionRecord(name: "same", details: .olcrtc(params(transport: "videochannel")))

        manager.connect(record: record)
        XCTAssertEqual(manager.state, .connecting)
        XCTAssertEqual(manager.activeMode, .proxy)

        SettingsStore.shared.tunnelMode = .vpn
        manager.connect(record: record)          // same record, different backend
        XCTAssertEqual(manager.activeMode, .vpn, "the switch must actually happen")
        XCTAssertEqual(manager.state, .failed(L10n.vpnVideochannelUnsupported.localized()),
                       "and the VPN branch must be the one that answered")
        manager.disconnect()
    }

    // The same record on the same backend stays idempotent — a double tap must
    // not tear a live session down.
    func testSameRecordSameBackendIsStillANoOp() {
        SettingsStore.shared.tunnelMode = .proxy
        let manager = TunnelManager()
        let record = ConnectionRecord(name: "same", details: .olcrtc(params()))
        manager.connect(record: record)
        XCTAssertEqual(manager.state, .connecting)
        manager.connect(record: record)
        XCTAssertEqual(manager.state, .connecting, "a repeat tap changes nothing")
        XCTAssertEqual(manager.activeMode, .proxy)
        manager.state = .disconnected
    }

    // An adopted tunnel holds a live state with NO record of its own. Connecting
    // to something while it runs used to hit the same early return and do
    // nothing at all — the user tapped a protocol and the app ignored them.
    func testConnectIsNotSwallowedWhileALiveStateHasNoRecord() {
        SettingsStore.shared.tunnelMode = .proxy
        let manager = TunnelManager()
        manager.state = .connected               // adopted: live, no `lastRecord`
        manager.connect(record: ConnectionRecord(name: "x", details: .olcrtc(params())))
        XCTAssertNotEqual(manager.state, .connected,
                          "#477 was: a live state with no record returned early")
        XCTAssertEqual(manager.state, .disconnected,
                       "torn down; the dial waits for the teardown and is not observable here")
        manager.state = .disconnected
    }
}
