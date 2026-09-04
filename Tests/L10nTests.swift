import XCTest
@testable import olcrtc_ios

// Verifies completeness of every per-language dictionary in L10nTable.
// Adding a new L10n case without translations fails one of these tests with
// a list of the missing keys — no silent fallbacks.

final class L10nTests: XCTestCase {

    func testEveryKeyHasAllLanguages() {
        var problems: [String] = []
        for key in L10n.allCases {
            for locale in AppLocale.allCases {
                let value: String?
                switch locale {
                case .english: value = L10nTable.english[key]
                case .russian: value = L10nTable.russian[key]
                }
                if value == nil {
                    problems.append("[\(locale.rawValue)] missing: \(key.rawValue)")
                } else if value!.isEmpty {
                    problems.append("[\(locale.rawValue)] empty: \(key.rawValue)")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }

    /// Catches stale dictionary entries. Each language dictionary's size must
    /// equal the number of L10n cases — otherwise the dict either has orphans
    /// (impossible with typed `[L10n: String]` today, but defensive against a
    /// future refactor to String keys) or duplicates (Swift would deduplicate
    /// literals, but the test verifies the deduplicated total matches).
    func testNoExtraKeysInDictionaries() {
        let expected = L10n.allCases.count
        XCTAssertEqual(L10nTable.english.count, expected,
            "English dictionary has \(L10nTable.english.count) entries, expected \(expected)")
        XCTAssertEqual(L10nTable.russian.count, expected,
            "Russian dictionary has \(L10nTable.russian.count) entries, expected \(expected)")
        // Every dict key must correspond to an existing L10n case.
        let all = Set(L10n.allCases)
        for k in L10nTable.english.keys {
            XCTAssertTrue(all.contains(k), "English dict has orphan key: \(k.rawValue)")
        }
        for k in L10nTable.russian.keys {
            XCTAssertTrue(all.contains(k), "Russian dict has orphan key: \(k.rawValue)")
        }
    }

    // Format-string consistency: cases whose names end with `_fmt` must contain
    // at least one placeholder in EVERY language. Catches translators who drop
    // the %@/%d/%lld marker accidentally.
    // #470: and the SAME specifiers in the SAME order in every language.
    // `L10n.formatted` is `String(format:arguments:)`, so a Russian string that
    // swaps "%@ … %d" to "%d … %@", or adds a third "%@", passed the old
    // "contains at least one" check and would read an Int as an object pointer
    // (or off the end of the argument list) at runtime — e.g. the expiry alert
    // crashing at the moment the room is about to die. Positional forms
    // (`%1$@`) are not used in the tables; if one is ever introduced, this
    // order comparison has to sort by position instead.
    func testFormatCasesContainPlaceholders() {
        // A String enum's rawValue equals the case name verbatim, and every
        // format case is named with a literal `_fmt` suffix (installResultSuccess_fmt,
        // …). The check was `hasSuffix("Fmt")`, which matched ZERO cases — the
        // loop was vacuous and never validated anything.
        for key in L10n.allCases where key.rawValue.hasSuffix("_fmt") {
            let en = L10nTable.english[key] ?? ""
            let ru = L10nTable.russian[key] ?? ""
            let enSpecs = Self.specifiers(in: en)
            let ruSpecs = Self.specifiers(in: ru)
            XCTAssertFalse(enSpecs.isEmpty,
                "[en] \(key.rawValue) is a *_fmt case but has no %@/%d/etc placeholder: \(en.debugDescription)")
            XCTAssertFalse(ruSpecs.isEmpty,
                "[ru] \(key.rawValue) is a *_fmt case but has no %@/%d/etc placeholder: \(ru.debugDescription)")
            XCTAssertEqual(enSpecs, ruSpecs,
                "\(key.rawValue): en \(enSpecs) vs ru \(ruSpecs) — String(format:) needs the same specifiers in the same order")
        }
    }
    // #470 was: assertHasPlaceholder(_:key:lang:) — "contains at least one of
    // %@ %d %lld %f %.0f %.1f %.2f", per language, with no cross-language check.

    // boc #470
    /// The inverse rule: a value carrying a `%` specifier that is NOT a `_fmt`
    /// case escapes the check above entirely — `removeHostConfirmTitle`
    /// ("Remove %@?", consumed with `.formatted(…)` in ServersView) is exactly
    /// that today. It is listed here rather than renamed, because the rename
    /// touches L10n.swift, both tables and ServersView. The set is compared for
    /// EQUALITY: the rename, or a new offender, fails this test and updates it.
    func testEveryPlaceholderBelongsToAFormatCase() {
        let knownExceptions: Set<String> = []   // #470: removeHostConfirmTitle is _fmt now
        var offenders: Set<String> = []
        for key in L10n.allCases where !key.rawValue.hasSuffix("_fmt") {
            for value in [L10nTable.english[key], L10nTable.russian[key]].compactMap({ $0 })
            where !Self.specifiers(in: value).isEmpty {
                offenders.insert(key.rawValue)
            }
        }
        XCTAssertEqual(offenders, knownExceptions,
            "a value with a % specifier must live in a *_fmt case (or be listed above, with its reason)")
    }

    /// The `%` conversion specifiers of a `String(format:)` string, in order:
    /// %[positional$][flags][width][.precision][length]conversion. The space
    /// flag is deliberately not accepted, so prose like "50% done" never reads
    /// as `% d`; an escaped `%%` is not in the tables either.
    private static func specifiers(in value: String) -> [String] {
        let pattern = #"%(\d+\$)?[-+0#]*\d*(\.\d+)?(ll|l|h)?[@dfsxXuioceEgGp]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let whole = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: whole).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }
    // eoc #470

    // MARK: AppLocale

    func testAppLocaleCurrentRespectsSettings() {
        let original = SettingsStore.shared.language
        SettingsStore.shared.language = "en"
        XCTAssertEqual(AppLocale.current, .english)
        SettingsStore.shared.language = "ru"
        XCTAssertEqual(AppLocale.current, .russian)
        SettingsStore.shared.language = "xx-unknown"
        XCTAssertEqual(AppLocale.current, .english, "Unknown codes must fall back to English")
        SettingsStore.shared.language = original
    }

    func testEveryAppLocaleHasDisplayName() {
        for locale in AppLocale.allCases {
            XCTAssertFalse(locale.displayName.isEmpty,
                "AppLocale.\(locale.rawValue) has empty displayName")
        }
    }

    // MARK: Smoke test for L10n.localized / .formatted

    func testLocalizedReturnsCurrentLanguageValue() {
        let original = SettingsStore.shared.language
        SettingsStore.shared.language = "en"
        XCTAssertEqual(L10n.actionConnect.localized(), "Connect")
        SettingsStore.shared.language = "ru"
        XCTAssertEqual(L10n.actionConnect.localized(), "Подключить")
        SettingsStore.shared.language = original
    }

    func testFormattedSubstitutesArgs() {
        let original = SettingsStore.shared.language
        SettingsStore.shared.language = "en"
        let result = L10n.installResultSuccess_fmt.formatted("telemost", "vp8channel")
        XCTAssertEqual(result, "olcrtc server installed (telemost/vp8channel)")
        SettingsStore.shared.language = original
    }
}
