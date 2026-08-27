import SwiftUI   // for OlcStatusTone (defined in App/UI/DesignSystem.swift)

// MARK: - NodeHealth (#456)
//
// #456: the ONE health vocabulary. Before this file the app had three unrelated
// answers to "is this node OK": podman `Up` (green dot on Manage VPS), a
// view-local `@State` ms-pill on Connections, and the live tunnel's
// `verifyTunnel` verdict — and only the last one was evidence.
//
// The evidence ladder encoded below:
//   • podman "Up"  = the process exists                       → proves NOTHING
//   • checkReady   = WebRTC/smux handshake completed          → amber at best
//   • ping         = HTTP 2xx came back through the node's
//                    OWN SOCKS listener                       → the only green
//
// Every value here is measured, timestamped and persisted; `HealthDisplay` is
// the only thing views render, and it grants green ONLY inside
// `HealthPolicy.freshSeconds`. Ownership + persistence live in
// `HealthCoordinator` (App/Services/HealthCoordinator.swift).

/// #456: what a probe PROVED about one node. Persisted as a raw String (not a
/// Codable enum) so an unrecognised future value decodes to `.unknown` instead
/// of failing the whole map — the repo's decodeIfPresent-only evolution rule.
enum NodeHealthKind: String, Codable, Sendable {
    case working       // end-to-end proof: Ping got HTTP 2xx through this node's SOCKS,
                       // or the LIVE tunnel's verifyTunnel returned 200. The only green.
    case handshake     // checkReady only: transport reached ready, data path UNPROVEN.
    case broken        // a probe ran and failed for a NODE-SPECIFIC reason.
    case inconclusive  // we could NOT check (offline / VPS unreachable / VPN active).
                       // NEVER render this as failure — requirement 2.
    case unknown       // decoded from an unrecognised raw value.
}

/// #456: one persisted verification result. No secrets: rtt, dates, a stable
/// reason CODE and a short redacted engineering detail. The human sentence is
/// derived at display time via L10n (never cached — CLAUDE.md).
struct NodeHealth: Codable, Equatable, Sendable {
    var kind: String            // NodeHealthKind.rawValue
    var checkedAt: Date
    var rttMs: Int?             // set only for .working from a Ping
    var reason: String?         // HealthReason.rawValue (nil for .working)
    var detail: String?         // <=200 chars, LogStore.redactSecrets'd, engineering only
    var source: String?         // "probe" | "live" | "op"

    var resolvedKind: NodeHealthKind { NodeHealthKind(rawValue: kind) ?? .unknown }
    var resolvedReason: HealthReason { HealthReason(rawValue: reason ?? "") ?? .unknown }

    init(kind: NodeHealthKind, checkedAt: Date = Date(), rttMs: Int? = nil,
         reason: HealthReason? = nil, detail: String? = nil, source: String) {
        self.kind = kind.rawValue
        self.checkedAt = checkedAt
        self.rttMs = rttMs
        self.reason = reason?.rawValue
        self.detail = detail.map { String($0.prefix(200)) }
        self.source = source
    }
}

/// #456: staleness + cost policy. ONE place, so no view invents a threshold.
enum HealthPolicy {
    /// A `.working` result is a PRESENT-TENSE claim (green) only inside this window.
    static let freshSeconds:      TimeInterval = 300      // 5 min
    /// Past this, the verdict is history only — rendered as `.stale`.
    static let staleSeconds:      TimeInterval = 1800     // 30 min
    /// Debounce: never re-probe a node checked this recently unless the user forced it.
    static let minRecheckSeconds: TimeInterval = 120      // 2 min
    /// Per-probe budget. NEVER ride SettingsStore.startTimeoutSeconds (60 s default):
    /// a hung carrier would cost a full minute × N nodes, sequentially.
    static let probeTimeoutMs:    Int = 20_000
    /// Cap on ONE automatic (non-user-initiated) sweep.
    static let autoSweepMaxNodes: Int = 6
    /// Entries older than this are dropped on load; the map is also capped.
    static let forgetSeconds:     TimeInterval = 60 * 60 * 24 * 30   // 30 days
    static let maxEntries:        Int = 200
}

/// #456: the ONE thing views render. Derived, never stored.
enum HealthDisplay: Equatable, Sendable {
    case never                                            // no probe on record
    case checking                                         // a probe is in flight NOW
    case verified(ms: Int?, age: TimeInterval)            // .working, age < freshSeconds  → GREEN
    case fading(ms: Int?, age: TimeInterval)              // .working, fresh…stale         → neutral, past tense
    case handshakeOnly(age: TimeInterval)                 // .handshake                    → amber
    case broken(HealthReason, age: TimeInterval)          // .broken                       → red
    case inconclusive(HealthReason, age: TimeInterval)    // .inconclusive                 → GREY, not red
    case stale(age: TimeInterval)                         // anything older than staleSeconds

    /// The ONLY place green is granted in the whole app.
    var isVerified: Bool { if case .verified = self { return true }; return false }
    var isChecking: Bool { self == .checking }

    var tone: OlcStatusTone {
        switch self {
        case .verified:                       return .ok        // green — earned
        case .checking:                       return .progress
        case .handshakeOnly:                  return .warn
        case .broken:                         return .error
        case .never, .fading, .inconclusive, .stale:
                                              return .unknown   // grey = we do not know
        }
    }

    /// Localised at the point of use (never cached).
    var title: String {
        switch self {
        case .never:            return L10n.healthNeverChecked.localized()
        case .checking:         return L10n.healthChecking.localized()
        case .verified:         return L10n.healthVerified.localized()
        case .fading:           return L10n.healthFading.localized()
        case .handshakeOnly:    return L10n.healthHandshake.localized()
        case .broken(let r, _): return r.headline
        case .inconclusive:     return L10n.healthInconclusive.localized()
        case .stale:            return L10n.healthStale.localized()
        }
    }

    var subtitle: String {
        switch self {
        case .never:      return L10n.healthNeverCheckedHint.localized()
        case .checking:   return L10n.healthCheckingHint.localized()
        case .verified(let ms, let age), .fading(let ms, let age):
            let a = HealthAge.label(age)
            if let ms { return L10n.healthVerifiedHint_fmt.formatted(a, ms) }
            return L10n.healthVerifiedNoRTTHint_fmt.formatted(a)
        case .handshakeOnly(let age):
            return L10n.healthHandshakeHint_fmt.formatted(HealthAge.label(age))
        case .broken(let r, let age), .inconclusive(let r, let age):
            return "\(r.message) · \(L10n.healthCheckedAgo_fmt.formatted(HealthAge.label(age)))"
        case .stale(let age):
            return L10n.healthStaleHint_fmt.formatted(HealthAge.label(age))
        }
    }

    /// Short text for `OlcHealthChip` — "48 ms · 2m", "not checked", "failed 5m ago".
    var chipLabel: String {
        switch self {
        case .never:        return L10n.healthChipNever.localized()
        case .checking:     return ""                                   // chip shows a spinner
        case .verified(let ms, let age), .fading(let ms, let age):
            let a = HealthAge.label(age)
            return ms.map { "\($0) ms · \(a)" } ?? a
        case .handshakeOnly(let age): return L10n.healthChipHandshake_fmt.formatted(HealthAge.label(age))
        case .broken(_, let age):     return L10n.healthChipFailed_fmt.formatted(HealthAge.label(age))
        case .inconclusive:           return L10n.healthChipUnchecked.localized()
        case .stale(let age):         return L10n.healthChipStale_fmt.formatted(HealthAge.label(age))
        }
    }

    /// What the user should DO next; nil when there is nothing to offer.
    var suggestedAction: HealthAction? {
        switch self {
        case .broken(let r, _), .inconclusive(let r, _): return r.action
        case .never, .stale:                             return .verify
        default:                                         return nil
        }
    }
}

/// #456: compact relative age. Pure → unit-tested.
enum HealthAge {
    static func label(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60          { return L10n.ageJustNow.localized() }
        if s < 3600        { return L10n.ageMinutes_fmt.formatted(Int(s / 60)) }
        if s < 86_400      { return L10n.ageHours_fmt.formatted(Int(s / 3600)) }
        return L10n.ageDays_fmt.formatted(Int(s / 86_400))
    }
}
