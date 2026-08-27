import SwiftUI

// #263: The single-source VPS display model + its pure reducer, moved out of
// ServersView (introduced in #258, reducer extracted in #259). The View drives
// these transitions; `HostDisplayTests` covers them. The "no status-jump"
// invariants live here:
//   • a probe result is the ONLY thing that sets the base (terminalBase),
//   • while running the card shows the PREVIOUS base, never the optimistic target,
//   • phases advance forward only (advanced), capped at the last milestone,
//   • a failure carries previousBase so Retry (retryBase) can restore it.

/// What the server IS. Set ONLY from a confirmed probe — never optimistically
/// mid-operation. Maps from `VPSReadinessState`.
enum HostBase: Equatable {
    case unknown, noPodman, noImage, imageReady, stopped, running

    init(_ r: VPSReadinessState) {
        switch r {
        case .noPodman:         self = .noPodman
        case .noImage:          self = .noImage
        case .imageReady:       self = .imageReady
        case .containerStopped: self = .stopped
        case .containerRunning: self = .running
        }
    }

    var hasContainer: Bool { self == .running || self == .stopped }

    var tone: OlcStatusTone {
        switch self {
        case .unknown, .noPodman:   return .unknown
        case .noImage:              return .progress   // amber — Podman ok, image not pulled
        // #456 was: .ok — green is now reserved for an end-to-end VERIFIED result;
        // podman "Up" only proves the process exists (the user's telemost container
        // was Up and green while its own logs read `traffic: in=0 out=0`), and
        // `.imageReady` means "nothing installed yet", which was never a success.
        case .imageReady, .running: return .unknown
        case .stopped:              return .warn
        }
    }
    var title: String {
        switch self {
        case .unknown:    return L10n.vpsTitleUnknown.localized()
        case .noPodman:   return L10n.vpsTitleReady.localized()
        case .noImage:    return L10n.vpsTitlePodmanReady.localized()
        case .imageReady: return L10n.vpsTitleReady.localized()
        case .stopped:    return L10n.vpsTitleStopped.localized()
        case .running:    return L10n.vpsTitleRunning.localized()
        }
    }
    var subtitle: String {
        switch self {
        case .unknown:    return L10n.vpsSubUnknown.localized()
        case .noPodman:   return L10n.vpsSubNoPodman.localized()
        case .noImage:    return L10n.vpsSubNoImage.localized()
        case .imageReady: return L10n.vpsSubImageReady.localized()
        case .stopped:    return L10n.vpsSubStopped.localized()
        case .running:    return L10n.vpsSubRunning.localized()
        }
    }
}

/// What we're DOING. `stepCount` sizes the progress-bar denominator (the live
/// provisioner message is the running subtitle); `target` is the nominal resolved
/// state used only when an op doesn't probe.
enum HostOp: Equatable {
    case check, install, start, stop, reconfigure, update, uninstall, deepUninstall, reboot

    var verb: String {
        switch self {
        case .check:         return L10n.vpsVerbChecking.localized()
        case .install:       return L10n.vpsVerbInstalling.localized()
        case .start:         return L10n.vpsVerbStarting.localized()
        case .stop:          return L10n.vpsVerbStopping.localized()
        case .reconfigure:   return L10n.vpsVerbReconfiguring.localized()
        case .update:        return L10n.vpsVerbUpdating.localized()
        case .uninstall:     return L10n.vpsVerbUninstalling.localized()
        case .deepUninstall: return L10n.vpsVerbDeepUninstalling.localized()
        case .reboot:        return L10n.vpsVerbRebooting.localized()
        }
    }

    /// Number of progress milestones — sizes the bar denominator only. The
    /// displayed running subtitle is the live (localized) provisioner message,
    /// not a fixed phase label, so individual step strings aren't needed.
    var stepCount: Int {
        switch self {
        case .check:  return 2
        case .install: return 5
        case .update: return 4
        case .start, .stop, .reconfigure, .uninstall, .deepUninstall, .reboot: return 3
        }
    }

    var target: HostBase? {
        switch self {
        case .check, .reboot:                          return nil      // keep previous base
        case .install, .start, .reconfigure, .update:  return .running
        case .stop:                                    return .stopped
        case .uninstall:                               return .imageReady
        case .deepUninstall:                           return .noPodman
        }
    }
}

/// The ONE display state. The card computes everything (status pill, progress bar,
/// primary button, menu) from this. `previousBase` rides along so Retry / a
/// no-probe success can restore without a second source.
enum HostDisplay: Equatable {
    case base(HostBase)
    case running(op: HostOp, phase: Int, note: String, previousBase: HostBase)
    case failed(op: HostOp, phase: String, message: String, previousBase: HostBase)
}

// MARK: - Reducer (pure — unit-tested in HostDisplayTests)

extension HostBase {
    /// Pre-probe seed for a never-probed host: a known container → `.stopped`
    /// (offer Start, never a mistaken reinstall); otherwise `.unknown` ("tap
    /// Check"). Never asserts `.running` without a probe.
    static func seed(lastContainerName: String?) -> HostBase {
        lastContainerName != nil ? .stopped : .unknown
    }
}

extension HostDisplay {
    /// The confirmed base under whatever is shown. Running / failed keep the base
    /// they started from — so the card never shows an optimistic state mid-op.
    var base: HostBase {
        switch self {
        case .base(let b):                return b
        case .running(_, _, _, let prev): return prev
        case .failed(_, _, _, let prev):  return prev
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// Begin an operation from a confirmed base: phase 0, first milestone note.
    static func start(_ op: HostOp, from base: HostBase) -> HostDisplay {
        .running(op: op, phase: 0, note: L10n.vpsConnecting.localized(), previousBase: base)
    }

    /// Advance a running operation: phase forward only (capped at the last
    /// milestone) + the live note. Non-running states pass through unchanged.
    func advanced(note: String) -> HostDisplay {
        guard case .running(let op, let phase, _, let prev) = self else { return self }
        let next = min(phase + 1, max(op.stepCount - 1, 0))
        return .running(op: op, phase: next, note: note, previousBase: prev)
    }

    /// The ONE terminal base on success: the probe result wins; else the op's
    /// nominal target; else the base we started from. Only a real probe should
    /// pass a non-nil `probed`.
    static func terminalBase(op: HostOp, probed: HostBase?, previous: HostBase) -> HostBase {
        probed ?? op.target ?? previous
    }

    /// Terminal failure: keep the op + the note where it failed, carry the
    /// previous base for Retry. Non-running → unchanged.
    func failed(message: String) -> HostDisplay {
        guard case .running(let op, _, let note, let prev) = self else { return self }
        return .failed(op: op, phase: note, message: message, previousBase: prev)
    }

    /// What Retry restores before re-dispatching the op: the base under a failure.
    func retryBase() -> HostDisplay? {
        guard case .failed(_, _, _, let prev) = self else { return nil }
        return .base(prev)
    }
}

// MARK: - HostHeadline (#456)

/// #456: the ONE headline for a VPS card. Combines what SSH proved about the
/// HOST with what end-to-end probes proved about its PROTOCOLS. Pure → tested.
///
/// This replaces "the podman pill is the card's verdict". Podman status is
/// demoted to a caption line with its own age; the headline answers the only
/// question the user actually has: *what is true right now, and what do I do?*
enum HostHeadline: Equatable {
    /// An operation is running. Carries the op's VERB for the title AND the live
    /// provisioner note + step for the subtitle.
    /// #456 (audit fix) was: `case busy(String)` holding only the verb, so the
    /// pill rendered "Installing…" as its title and "Installing" as its subtitle
    /// — the same word twice — and the running commentary the user relies on to
    /// see progress (which the provisioner publishes continuously) was dropped.
    case busy(verb: String, note: String, step: Int, of: Int)
    /// The last operation failed: WHICH op, and its message.
    /// #456 (audit fix) was: `case opFailed(String)` (message only), so the title
    /// became a generic "Last action failed" and the user could no longer tell
    /// whether the install, the reconfigure or the uninstall was the thing that
    /// broke.
    case opFailed(verb: String, message: String)
    /// SSH / TCP said no. This is "couldn't check" — requirement 2 — and is NEVER
    /// rendered as stopped or failed, however old the last container reading is.
    case unreachable(age: TimeInterval?)
    /// Nothing has probed this host yet this launch — an honest blank, not a
    /// present-tense claim recycled from a persisted value.
    case notChecked
    case containerStopped
    case noContainer(HostBase)
    /// Nothing is in the way: the card shows the PROTOCOLS' measured verdict.
    case health(HealthDisplay)

    /// Precedence, strictly in this order:
    /// 1 running op · 2 failed op · 3 SSH/TCP said no ("couldn't check", NEVER
    /// "stopped") · 4 never probed this launch · 5 container stopped ·
    /// 6 nothing installed · 7 the protocols' measured verdict.
    static func reduce(display: HostDisplay,
                       reachable: Bool?,
                       lastProbeAge: TimeInterval?,
                       health: HealthDisplay) -> HostHeadline {
        if case .running(let op, let phase, let note, _) = display {
            return .busy(verb: op.verb, note: note, step: phase, of: op.stepCount)   // #456
        }
        if case .failed(let op, _, let message, _) = display {
            return .opFailed(verb: op.verb, message: message)   // #456
        }
        // Before ANY container reading: an unreachable VPS tells us nothing about
        // the container, so a stale "stopped" must never surface as fact here.
        if reachable == false { return .unreachable(age: lastProbeAge) }
        if lastProbeAge == nil { return .notChecked }
        if display.base == .stopped { return .containerStopped }
        if !display.base.hasContainer { return .noContainer(display.base) }
        return .health(health)
    }

    var tone: OlcStatusTone {
        switch self {
        case .busy:             return .progress
        case .opFailed:         return .error
        // Grey, not red: "we could not check" is not a verdict about the server.
        case .unreachable:      return .unknown
        case .notChecked:       return .unknown
        case .containerStopped: return .warn
        case .noContainer(let b): return b.tone
        case .health(let h):    return h.tone
        }
    }

    var title: String {
        switch self {
        case .busy(let verb, _, _, _): return "\(verb)…"
        // #456 (audit fix): name the operation that failed, not a generic sentence.
        case .opFailed(let verb, _):  return L10n.vpsOpFailed_fmt.formatted(verb)
        case .unreachable:        return L10n.vpsHeadlineUnreachable.localized()
        case .notChecked:         return L10n.vpsHeadlineNotChecked.localized()
        case .containerStopped:   return L10n.vpsHeadlineStopped.localized()
        case .noContainer(let b): return b.title
        case .health(let h):      return h.title
        }
    }

    var subtitle: String {
        switch self {
        // #456 (audit fix): the live note plus "step n/total" — what the card
        // showed before the headline reducer existed.
        case .busy(_, let note, let step, let total):
            return note.isEmpty ? "\(step)/\(total)" : "\(note) · \(step)/\(total)"
        case .opFailed(_, let m): return m
        // boc #459 was: HealthAge.label($0) inside "SSH didn't answer (%@ ago)",
        // which rendered "SSH didn't answer (just now ago)". `phrase` carries its
        // own preposition, so the string is now "SSH didn't answer (%@)".
        case .unreachable(let age):
            return age.map { L10n.vpsHeadlineUnreachableHint_fmt.formatted(HealthAge.phrase($0)) }
                ?? L10n.vpsHeadlineUnreachableHintNever.localized()
        // eoc #459
        case .notChecked:         return L10n.vpsHeadlineNotCheckedHint.localized()
        case .containerStopped:   return L10n.vpsHeadlineStoppedHint.localized()
        case .noContainer(let b): return b.subtitle
        case .health(let h):      return h.subtitle
        }
    }
}
