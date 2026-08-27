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
// #459: THE HERO'S SUBJECT IS NOT IN THE LIST BELOW IT. `ConnectionsView` skips
// the row for whichever record this card is about, so the connection's name is
// printed exactly once per screen — and "which one is selected?" is answered by
// POSITION (the big card at the top, the one with the button in it) rather than
// by a badge nobody can find. Two consequences land here:
//   • the mono `olcrtc · telemost · vp8channel` line is GONE. `olcrtc` is on
//     every connection and carries no bits; the carrier/transport is stated
//     once, in Diagnostics → "This session" → Protocol.
//   • the card grew an OVERFLOW MENU, because the subject no longer has a row
//     to carry Share / Copy URI / QR / Edit / Remove.
// #459: the connected evidence line names the EXIT (flag + city, CC) — the one
// connected-state fact the owner asked about and the only one that is not a
// number. Every number now lives in Diagnostics, so no figure is printed twice.
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
    /// #459: the tunnel exit's flag glyph (`CountryFlag.emoji(iso2:)`), nil when
    /// the lookup gave no usable country. Computed by `ConnectionsView`, which
    /// already owns the `IPChecker.refreshExitGeo` call.
    let exitFlag: String?
    /// #459: the tunnel exit as "Amsterdam, NL"; nil when the lookup returned
    /// nothing, in which case the evidence line falls back to the verdict.
    let exitPlace: String?
    /// Which backend a session runs (or would run) through — the scope line.
    let mode: TunnelMode
    /// The port the live session bound, else the configured one.
    let socksPort: Int
    /// `ConnectionStore.secretsLocked` — the Keychain could not be read yet.
    let secretsLocked: Bool
    /// #459: the subject's action set — the SAME builder the rows use, because
    /// the subject has no row of its own any more. Empty ⇒ no menu is drawn.
    let menuItems: [OlcMenuItem]
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    /// #457: when the current `.connecting` began, so the evidence line can age
    /// it ("starting… 6 s") instead of printing a bare, undatable "Connecting…".
    @State private var connectingSince: Date?

    var body: some View {
        OlcCard {
            // #459 was: spacing 10. The card lost two lines, so the rhythm it
            // keeps is the design system's own row step.
            VStack(alignment: .leading, spacing: Theme.Metrics.s3) {
                headlineRow
                subjectLine
                // #457: the HUMAN headline first, the machine detail under it —
                // never the other way round (Microsoft's error spec: explain the
                // problem from the user's point of view, not the code's).
                reasonLine
                evidenceLine
                scopeLine
                // #459: 4 pt on top of the 12 pt rhythm, so the break before the
                // one action reads as a break and every other gap stays equal.
                Divider().overlay(Theme.Palette.separator).padding(.top, 4)
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

    /// #459: the answer, and — pinned opposite it — the subject's action set.
    /// The menu is top-aligned with the state word so it never floats beside
    /// nothing when the word wraps down a Dynamic Type step.
    private var headlineRow: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.s2) {
            stateWord
            Spacer(minLength: 8)
            heroMenu
        }
    }

    /// #459: drawn only when there is a subject to act on — an empty menu is a
    /// control that does nothing.
    @ViewBuilder
    private var heroMenu: some View {
        if subject != nil, !menuItems.isEmpty {
            OlcOverflowMenu(items: menuItems)
        }
    }

    private var stateWord: some View {
        Text(stateTitle)
            .font(Theme.Typography.answer)
            .foregroundStyle(Theme.Palette.textPrimary)
            // #459 (audit) was: .lineLimit(1) + .minimumScaleFactor(0.55). The
            // answer is the one line here that may never be shrunk or clipped,
            // and both happened: "Waiting for network…" is 20 characters at the
            // largeTitle step with the overflow menu beside it, so it already
            // rendered smaller than `Typography.answer` on a phone, and past the
            // 0.55 floor (reached a couple of Dynamic Type steps up) it clipped.
            // It wraps now — `headlineRow` is top-aligned for exactly that.
            .fixedSize(horizontal: false, vertical: true)
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

    // boc #459
    // #459 was: a three-line `VStack` — "Last used" on its own row, the name,
    // then `subject.subtitle` ("olcrtc · telemost · vp8channel"). Three lines to
    // say one thing, and the third repeated what every row in the list below
    // also said. The label now shares the name's baseline, and the mono line is
    // deleted: the carrier/transport is stated once, in Diagnostics.
    @ViewBuilder
    private var subjectLine: some View {
        if let subject = subject {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !state.isConnected {
                    Text(L10n.heroLastUsedLabel.localized().uppercased())
                        .font(Theme.Typography.caption)
                        .tracking(0.4)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(subject.displayName)
                    .font(Theme.Typography.answerSupport)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
        } else {
            Text(L10n.heroSubjectNone.localized())
                .font(Theme.Typography.answerSupport)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
    // eoc #459

    // MARK: 3. One line of dated evidence

    @ViewBuilder
    private var evidenceLine: some View {
        switch state {
        case .connecting:
            ConnectHeroElapsed(since: connectingSince ?? Date())
        case .connected:
            connectedEvidence
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

    /// #459: while a session is up, the WHERE outranks the verdict sentence —
    /// it is the one connected-state fact the numbers in Diagnostics cannot
    /// state, and printing it here means no figure appears on this screen twice.
    /// Green still needs `.verified`: the place is where traffic came out, not
    /// proof that it did.
    ///
    /// #457 (audit fix) was, and still is, the fallback: anything that is not
    /// `.verified` used to print "no data checked through it yet" — which called
    /// a REAL measurement taken four minutes ago "never measured". `.fading` and
    /// `.stale` say what they actually know (in the past tense, which their own
    /// subtitle already does); only the two states that genuinely have no
    /// end-to-end reading fall back to that line.
    ///
    /// #460 (findings 3 / 22): the owner asked, in as many words, where the
    /// country and the IP even come from. A place name printed with no
    /// provenance is exactly as unaccountable as a number printed with no date,
    /// and this is the most prominent place the app prints one — so the method
    /// is named directly under it. The detail (which service, and that the city
    /// comes from the same answer) belongs one card down, in Diagnostics → Exit;
    /// here it is one caption line saying that this is a lookup of the tunnel's
    /// own exit address, made through the tunnel.
    @ViewBuilder
    private var connectedEvidence: some View {
        if let place = exitPlace {
            VStack(alignment: .leading, spacing: 2) {
                evidenceText(exitFlag.map { "\($0) \(place)" } ?? place,
                             tone: health.isVerified ? Theme.Palette.green
                                                     : Theme.Palette.textSecondary)
                Text(L10n.heroExitSourceNote.localized())
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            evidenceText(heroEvidenceHasReading ? health.subtitle
                                                : L10n.heroEvidenceUnverified.localized(),
                         tone: health.isVerified ? Theme.Palette.green
                                                 : Theme.Palette.textSecondary)
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
            // #459 (audit) was: .lineLimit(1) + .minimumScaleFactor(0.8) on a
            // whole SENTENCE — 58 characters in Russian («Прокси · только
            // приложения, которые смотрят на 127.0.0.1:8808»). One caption line
            // barely holds it on a phone at 80% (i.e. already shrunk), and one
            // Dynamic Type step up it hits the floor and truncates. The line
            // that says what the word "Connected" MEANS may not be cut, so it
            // wraps instead.
            .fixedSize(horizontal: false, vertical: true)
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
