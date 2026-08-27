import XCTest
import SwiftUI
@testable import olcrtc_ios

// #299 was: testConsoleIsSharperAndDenserThanRefined — pinned the Refined vs
// Console "design direction" metric tokens. The direction is gone; Theme is now
// real colour schemes. These tests pin the current contract: the appearance
// modes, their colorScheme mapping, and the single (Refined) metric values.
// #456 was: the same file with Gray as a fourth scheme (testAppearanceModesIncludeGray,
// testGrayUsesDarkColorScheme, testGrayChangesGroundTokens). Gray is removed —
// System / Light / Dark only — so the first two shrank and the ground-token test
// went with the feature. In its place, testStoredGrayStillDecodesToSomethingValid
// pins the SAFE migration: a user whose UserDefaults still says "gray" must land
// on a valid mode rather than an invalid one, and that happens for free through
// SettingsStore.init's `?? .dark` (no migration code, deliberately).

@MainActor
final class ThemeDirectionTests: XCTestCase {

    /// The appearance modes are exactly System / Light / Dark, in picker order.
    func testAppearanceModes() {
        XCTAssertEqual(AppearanceMode.allCases,
                       [.system, .light, .dark])   // #456 was: + .gray
        // Each mode has a non-empty, distinct title (drives the Settings picker).
        let titles = AppearanceMode.allCases.map { $0.title }
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
    }

    /// System follows the OS (nil); Light/Dark force their own scheme. With Gray
    /// gone, every switch between modes flips `colorScheme` — which is what lets
    /// App.swift drop the `.id(settings.appearanceMode)` full-TabView rebuild
    /// (#456): SwiftUI re-resolves the dynamic Theme tokens on the trait change.
    func testColorSchemeMapping() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme,  .dark)   // #456 was: + .gray → .dark
    }

    /// #456: an existing user's persisted `"gray"` must not strand the app on an
    /// invalid appearance. The raw value no longer matches a case, so
    /// `AppearanceMode(rawValue:)` returns nil and SettingsStore.init's `?? .dark`
    /// resolves it to Dark — the scheme Gray was closest to. This is the whole
    /// migration; if this test ever fails, the removal stopped being safe.
    func testStoredGrayStillDecodesToSomethingValid() {
        XCTAssertNil(AppearanceMode(rawValue: "gray"))
        XCTAssertEqual(AppearanceMode(rawValue: "gray") ?? .dark, .dark)
    }

    /// The "design direction" tokens collapsed to single Refined values:
    /// no card border, soft radii, roomy padding.
    func testMetricsAreSingleRefinedValues() {
        XCTAssertEqual(Theme.Metrics.cardBorderWidth, 0)
        XCTAssertEqual(Theme.Metrics.cardRadius, 20)
        XCTAssertEqual(Theme.Metrics.controlRadius, 13)
        XCTAssertEqual(Theme.Metrics.cardPadding, 16)
    }
}
