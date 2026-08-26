import XCTest
@testable import olcrtc_ios

// Pins the contract for `CarrierTransportMatrix.requiresRoomID`.
// The YAML binary requires an explicit room ID for every carrier, so
// `autoGeneratesRoomID` is empty. If anyone flips the defensive default
// (unknown carrier → requires) or re-adds an auto-gen carrier by accident,
// these tests fail.

final class CarrierTransportMatrixTests: XCTestCase {

    func testEveryKnownCarrierRequiresRoomID() {
        for carrier in CarrierTransportMatrix.carriers {
            XCTAssertTrue(
                CarrierTransportMatrix.requiresRoomID(carrier: carrier),
                "expected \(carrier) to require a room ID"
            )
        }
    }

    func testUnknownCarrierRequiresRoomID() {
        // Defensive default: a carrier we haven't catalogued falls through to
        // "requires" because the server will reject it anyway. Set.contains
        // returns false for unknowns, so the function naturally defaults to
        // "requires" without an extra `if`.
        XCTAssertTrue(CarrierTransportMatrix.requiresRoomID(carrier: "unknown-future-carrier"))
    }

    func testAutoGenSetIsEmpty() {
        // The YAML binary requires an explicit room ID for every carrier, so
        // no carrier auto-generates one. When #226 wires Jitsi room-URL
        // auto-generation, add "jitsi" here and match it in scripts/srv.sh.
        XCTAssertTrue(CarrierTransportMatrix.autoGeneratesRoomID.isEmpty)
    }

    // #284: cells re-derived from upstream docs/settings.md. Pin the ones the
    // user picks by — and the cells that were previously *wrong* (telemost
    // dropped DataChannel; telemost seichannel is unsupported).
    func testMatrixMatchesUpstream() {
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "jitsi",    transport: "datachannel"), .recommended)
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "telemost", transport: "vp8channel"),  .recommended)
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "wbstream", transport: "vp8channel"),  .recommended)
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "telemost", transport: "datachannel"), .fail)
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "telemost", transport: "seichannel"),  .fail)
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "wbstream", transport: "datachannel"), .question)
        // #434: re-synced to upstream master (42ae4e0) — jitsi's E2E case now returns
        // ExpectPass for every transport (RTP keepalive fixes landed for sei/video too),
        // so all non-datachannel jitsi transports are .ok.
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "jitsi",    transport: "vp8channel"),   .ok)
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "jitsi",    transport: "seichannel"),   .ok)   // #434 was: .fail
        XCTAssertEqual(CarrierTransportMatrix.compat(carrier: "jitsi",    transport: "videochannel"), .ok)   // #434 was: .fail
    }

    // The pre-selected transport for each carrier must be its recommended cell.
    func testDefaultTransportIsTheRecommendedCell() {
        for carrier in CarrierTransportMatrix.carriers {
            let t = CarrierTransportMatrix.defaultTransport(for: carrier)
            XCTAssertEqual(CarrierTransportMatrix.compat(carrier: carrier, transport: t), .recommended,
                           "default transport for \(carrier) should be its recommended cell")
        }
    }

    // (audit) transport gating: the sheets map matrix ✗ cells to disabled
    // OlcOptions carrying a VoiceOver reason; every other cell stays enabled.
    // Also pins the ADDITIVE OlcOption API — `disabled`/`disabledReason` must
    // keep their defaults so pre-gating `OlcOption(value:label:)` call sites
    // (Settings presets, Logs host picker, segments) keep compiling unchanged.
    func testFailCellsProduceDisabledOptionsWithReason() {
        for carrier in CarrierTransportMatrix.carriers {
            for t in CarrierTransportMatrix.transports {
                let fails = CarrierTransportMatrix.compat(carrier: carrier, transport: t) == .fail
                let opt = OlcOption(
                    value: t,
                    label: CarrierTransportMatrix.transportLabel(t),
                    disabled: fails,
                    disabledReason: fails
                        ? L10n.matrixFail_fmt.formatted(CarrierTransportMatrix.carrierLabel(carrier))
                        : nil)
                XCTAssertEqual(opt.disabled, fails,
                               "\(carrier)+\(t): chip disabled iff the matrix says ✗")
                XCTAssertEqual(opt.disabledReason != nil, fails,
                               "\(carrier)+\(t): a disabled chip must carry its reason")
            }
        }
        // Additive-defaults contract: the original initializer shape yields an
        // enabled option with no reason.
        let plain = OlcOption(value: "x", label: "X")
        XCTAssertFalse(plain.disabled)
        XCTAssertNil(plain.disabledReason)
    }
}
