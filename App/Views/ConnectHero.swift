import SwiftUI

// MARK: - ConnectHero (#457)
//
// #457: the SCALE INVERSION fix. The one question this screen exists to answer
// — "is my traffic getting out right now?" — used to render at ~15 pt inside an
// `OlcStatusPill`, wrapped in an `.ultraThinMaterial` card carrying a 26 pt cyan
// glow. The ornament was largeTitle-scale and the answer was caption-scale, so
// blurring the screenshot left the glow standing and the word gone.
//
// The block now reads, top to bottom, in descending order of what the user came
// for:
//   1. THE STATE, as the largest text on the screen.
//   2. WHICH connection it applies to (and, when idle, that it is the last used).
//   3. ONE line of DATED evidence — sourced from `HealthDisplay.subtitle`, the
//      honesty layer's own timestamped sentence, so nothing here is a claim the
//      app has not measured.
//   4. THE SCOPE — proxy port vs whole device. Permanently visible, because
//      `SettingsStore.tunnelMode` changes what the word "Connected" MEANS.
//   5. ONE full-width, labelled action. Never a bare system Toggle.
//
// #457 was: `ConnectionsView.heroCard` — `OlcCard(elevation: .glow, glass: true)`
// + `OlcStatusPill` + a `Toggle` + `heroServerLine` + `heroFooter`. The glass and
// the glow are deleted by the design-system partition (`OlcCard(glass:)` and
// `Theme.Elevation.glow` no longer exist), and depth may not encode status.
//
// THE AURORA IS A VERDICT, NOT A STYLE. The one gradient left on this screen is
// the 2 pt ring below, drawn only while the tunnel is live AND the honesty
// layer's proof is inside `HealthPolicy.freshSeconds`. Connected-but-unverified
// draws no ring — that is the whole point of making it rare.
//
// TYPE NOTE (#457): the state word renders at `Theme.Typography.answer` — the
// design system's top step, which exists for exactly this line and is used
// nowhere else in the app. Never re-declare the font here: a local copy is how
// a scale drifts back into "two sizes plus a lot of weight".

struct ConnectHero: View {

    // MARK: Inputs (value-only — the hero renders, it does not decide)

    let state: ConnectionState
    /// The connection the state applies to: the LIVE node while a session is up,
    /// else the last-used one. Never `store.primary` read directly — a row tap
    /// moves the selection without reconnecting.
    let subject: ConnectionRecord?
    /// The honesty layer's verdict for `subject`, already dated.
    let health: HealthDisplay
    /// Which backend a session runs (or would run) through — the scope line.
    let mode: TunnelMode
    /// The port the live session bound, else the configured one.
    let socksPort: Int
    /// `ConnectionStore.secretsLocked` — the Keychain could not be read yet.
    let secretsLocked: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    /// #457: when the current `.connecting` began, so the evidence line can age
    /// it ("starting… 6 s") instead of printing a bare, undatable "Connecting…".
    @State private var connectingSince: Date?

    var body: some View {
        OlcCard {
            VStack(alignment: .leading, spacing: 10) {
                stateWord
                subjectLine
                // #457: the HUMAN headline first, the machine detail under it —
                // never the other way round (Microsoft's error spec: explain the
                // problem from the user's point of view, not the code's).
                reasonLine
                evidenceLine
                scopeLine
                Divider().overlay(Theme.Palette.separator)
                primaryControl
                elsewhereNote
            }
        }
        .overlay { auroraVerdictRing }
        // #457 was: `.spring(response: 0.42, dampingFraction: 0.82)` — a visible
        // overshoot on the app's single most important surface. One spring, no
        // bounce, under the 300 ms ceiling.
        .animation(.spring(duration: 0.3, bounce: 0), value: state)
        .onChange(of: state, initial: true) { _, new in
            connectingSince = new.isConnecting ? (connectingSince ?? Date()) : nil
        }
    }

    // MARK: 1. The answer

    private var stateWord: some View {
        Text(stateTitle)
            .font(Theme.Typography.answer)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .accessibilityAddTraits(.isHeader)
    }

    private var stateTitle: String {
        switch state {
        case .connected:         return L10n.stateConnected.localized()
        case .connecting:        return L10n.stateConnecting.localized()
        case .waitingForNetwork: return L10n.stateWaitingForNetwork.localized()
        case .failed:            return L10n.stateConnectFailed.localized()
        case .disconnected:      return L10n.stateDisconnected.localized()
        }
    }

    // MARK: 2. The subject

    @ViewBuilder
    private var subjectLine: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let subject = subject {
                if !state.isConnected {
                    Text(L10n.heroLastUsedLabel.localized())
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(subject.displayName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(subject.subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            } else {
                Text(L10n.heroSubjectNone.localized())
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    // MARK: 3. One line of dated evidence

    @ViewBuilder
    private var evidenceLine: some View {
        switch state {
        case .connecting:
            ConnectHeroElapsed(since: connectingSince ?? Date())
        case .connected:
            // #457 (audit fix) was: anything that is not `.verified` printed
            // "no data checked through it yet" — which called a REAL measurement
            // taken four minutes ago "never measured". Understating evidence is
            // the same fault as overstating it. `.fading` and `.stale` say what
            // they actually know (in the past tense, which their own subtitle
            // already does); only the two states that genuinely have no
            // end-to-end reading fall back to that line. Green stays reserved
            // for `.verified` — the aurora ring is unaffected.
            evidenceText(heroEvidenceHasReading ? health.subtitle
                                                : L10n.heroEvidenceUnverified.localized(),
                         tone: health.isVerified ? Theme.Palette.green
                                                 : Theme.Palette.textSecondary)
        case .waitingForNetwork:
            evidenceText(L10n.heroEvidenceNoNetwork.localized(), tone: Theme.Palette.textSecondary)
        case .failed(let raw):
            // #457: with a mapped reason the sentence is the WHY; without one the
            // raw message is all we have, so it stands alone and stays red.
            evidenceText(failureReason?.message ?? raw,
                         tone: failureReason == nil ? Theme.Palette.red
                                                    : Theme.Palette.textSecondary,
                         mono: false)
        case .disconnected:
            evidenceText(subject == nil ? " " : health.subtitle, tone: Theme.Palette.textSecondary)
        }
    }

    /// #457 (audit fix): does this verdict carry an actual end-to-end reading to
    /// report? `.never` never measured anything; `.handshakeOnly` reached the room
    /// but no data passed. Everything else — verified, ageing, stale, broken,
    /// couldn't-check — has something true to say and says it in its own subtitle.
    private var heroEvidenceHasReading: Bool {
        switch health {
        case .never, .handshakeOnly: return false
        default:                     return true
        }
    }

    /// `mono` is for measured data (ages, milliseconds, ports); prose — a mapped
    /// failure sentence — reads in the proportional face.
    private func evidenceText(_ text: String, tone: Color, mono: Bool = true) -> some View {
        Text(text)
            .font(mono ? Font.system(.caption, design: .monospaced)
                       : Font.system(.caption, design: .rounded))
            .foregroundStyle(tone)
            // #457: a reason is never truncated (HIG Typography) — it wraps.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 18, alignment: .leading)
    }

    /// #457: the failure's HUMAN headline, from the honesty layer's mapper —
    /// never the raw core line, which the evidence line above already carries in
    /// its engineering voice.
    @ViewBuilder
    private var reasonLine: some View {
        if case .failed = state, let reason = failureReason {
            Text(reason.headline)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.Palette.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var failureReason: HealthReason? {
        switch health {
        case .broken(let r, _), .inconclusive(let r, _): return r
        default: return nil
        }
    }

    // MARK: 4. The scope — always on screen

    private var scopeLine: some View {
        Text(mode == .vpn
             ? L10n.heroScopeVPN.localized()
             : L10n.heroScopeProxy_fmt.formatted(String(socksPort)))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: 5. The one action

    @ViewBuilder
    private var primaryControl: some View {
        switch state {
        case .connecting:
            // Never lock the control mid-connect: a dead carrier combo must not
            // cost the whole start timeout with no way out (#269).
            OlcButton(L10n.cancel.localized(), systemImage: "xmark",
                      role: .secondary, fillWidth: true, action: onDisconnect)
        case .connected, .waitingForNetwork:
            OlcButton(L10n.actionDisconnect.localized(), systemImage: "power",
                      role: .secondary, fillWidth: true, action: onDisconnect)
        case .disconnected, .failed:
            connectControl
        }
    }

    @ViewBuilder
    private var connectControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            OlcButton(connectTitle, systemImage: "power",
                      role: .primary, fillWidth: true, action: onConnect)
                .disabled(!canConnect)
            if let blocked = blockedReason {
                Text(blocked)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectTitle: String {
        if case .failed = state { return L10n.actionRetry.localized() }
        return L10n.actionConnect.localized()
    }

    private var canConnect: Bool { subject != nil && !secretsLocked }

    private var blockedReason: String? {
        if secretsLocked { return L10n.errorSecretsLocked.localized() }
        if subject == nil { return L10n.heroPickAConnection.localized() }
        return nil
    }

    /// #457: the fix for a failure whose action lives on another screen. Naming
    /// the screen is honest; drawing a button that cannot run here is not.
    @ViewBuilder
    private var elsewhereNote: some View {
        if case .failed = state, let action = failureReason?.action,
           let note = ConnectActionSite.elsewhereNote(for: action) {
            Text(note)
                .font(.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The aurora, spent exactly once

    @ViewBuilder
    private var auroraVerdictRing: some View {
        if state.isConnected && health.isVerified {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.Palette.auroraGradient, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - ConnectHeroElapsed (#457)
//
// #457: `.connecting` is the one state with no step count the core can report,
// so the honest signal is elapsed time — a number that visibly moves, not a
// bare word. One ticking view, isolated so the hero's own body never re-runs
// the whole card's type-check for it.

private struct ConnectHeroElapsed: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            Text(L10n.heroEvidenceStarting_fmt
                    .formatted(Int(max(0, ctx.date.timeIntervalSince(since)))))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(minHeight: 18, alignment: .leading)
        }
    }
}

// MARK: - ConnectActionSite (#457)
//
// #457: `HealthDisplay.suggestedAction` names an offer; this decides WHERE that
// offer can actually be honoured. Only re-checking runs on the Connect screen —
// recovering a key, changing a room and starting a container all need SSH, and
// the port lives in Settings. Rather than draw a dead button (or, worse, hide
// the fix in an overflow menu), the row and the hero name the screen.

enum ConnectActionSite {
    case here, servers, settings

    static func site(for action: HealthAction) -> ConnectActionSite {
        switch action {
        case .verify, .retry:                                    return .here
        case .recoverConnection, .checkRoom, .startContainer:    return .servers
        case .openPortSettings:                                  return .settings
        }
    }

    /// The sentence to print when the fix is not on this screen; nil when it is.
    static func elsewhereNote(for action: HealthAction) -> String? {
        switch site(for: action) {
        case .here:     return nil
        case .servers:  return L10n.healthActionOnServersTab_fmt.formatted(action.title)
        case .settings: return L10n.healthActionInSettings_fmt.formatted(action.title)
        }
    }
}
