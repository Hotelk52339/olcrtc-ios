import SwiftUI

// MARK: - InstallOptionsView
//
// Sheet shown before "Install" runs SSH. The user picks carrier,
// transport and a room ID. Compatibility reference is
// in the Servers tab (always visible), not here.
//
// #258: carrier / transport use OlcChipPicker; the confirm action is a single
// full-width OlcButton(.primary) footer, with one close (✕) control.
//
// #452: multi-carrier install. The existing form is the PRIMARY protocol; a new
// "Additional protocols" section lets the user co-install the other carriers on
// the same server (sibling containers sharing one key — see scripts/add-carrier.sh).
// The sheet is also reused by the host card's "Add protocol" flow via
// `singleOnly` + `limitToCarriers` (extras hidden, carriers restricted to the
// ones not yet on the server).

struct InstallOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var carrier   : String
    @State private var transport : String
    @State private var roomID    = ""
    // #256: Jitsi rendezvous base URL — editable, pre-filled with the shared
    // default so users can point at their own instance. Only sent for jitsi.
    @State private var jitsiBaseURL = AppConstants.defaultJitsiBaseURL

    // SEI channel params — visible only when transport == "seichannel"
    @State private var seiFPS  : Int = 30
    @State private var seiBatch: Int = 10
    @State private var seiFrag : Int = 1200
    @State private var seiACK  : Int = 1

    // #436: wbstream account token (auth.token) — visible only for wbstream.
    @State private var wbToken = ""

    // boc #452: additional-protocol drafts, keyed by carrier id. Presence with
    // `enabled` drives the inline sub-form. Extras deliberately reuse the
    // server-side SEI defaults (30/10/1200/1 == OlcrtcConnection's own) instead
    // of adding four steppers per extra carrier — the sheet stays scannable and
    // the tuning remains editable per-connection afterwards.
    private struct ExtraDraft {
        var enabled = false
        var transport: String
        var roomID = ""
        var jitsiBaseURL = AppConstants.defaultJitsiBaseURL
        var wbToken = ""
    }
    @State private var extras: [String: ExtraDraft] = [:]

    /// Reuse mode (host card "Add protocol"): restrict the carrier chips to the
    /// providers not yet installed on the server. nil = the full matrix list.
    private let limitToCarriers: [String]?
    /// Reuse mode: hide the extras section — the sheet returns exactly ONE
    /// InstallOptions (extras array is empty).
    private let singleOnly: Bool
    // eoc #452

    // #452 was: `let onConfirm: (InstallOptions) -> Void` — now also returns the
    // additional-protocol options (empty for a single-protocol confirm).
    let onConfirm: (_ primary: InstallOptions, _ extras: [InstallOptions]) -> Void

    // boc #452: explicit init (the private stored properties above kill the
    // memberwise one). Seeds the carrier from the restricted list when present.
    init(limitToCarriers: [String]? = nil,
         singleOnly: Bool = false,
         onConfirm: @escaping (_ primary: InstallOptions, _ extras: [InstallOptions]) -> Void) {
        self.limitToCarriers = limitToCarriers
        self.singleOnly = singleOnly
        self.onConfirm = onConfirm
        let first = limitToCarriers?.first ?? "telemost"
        _carrier   = State(initialValue: first)
        _transport = State(initialValue: CarrierTransportMatrix.defaultTransport(for: first))
    }

    /// Carriers offered by the primary chips (restricted in reuse mode).
    private var availableCarriers: [String] {
        limitToCarriers ?? CarrierTransportMatrix.carriers
    }

    /// Carriers offered as extras: everything except the current primary,
    /// in matrix order. Hidden entirely in singleOnly mode.
    private var extraCarriers: [String] {
        CarrierTransportMatrix.carriers.filter { $0 != carrier }
    }

    private var enabledExtraCarriers: [String] {
        extraCarriers.filter { extras[$0]?.enabled == true }
    }

    private func draft(_ c: String) -> ExtraDraft {
        extras[c] ?? ExtraDraft(transport: CarrierTransportMatrix.defaultTransport(for: c))
    }

    private func draftBinding(_ c: String) -> Binding<ExtraDraft> {
        Binding(get: { draft(c) }, set: { extras[c] = $0 })
    }

    private func extraIsValid(_ c: String) -> Bool {
        let d = draft(c)
        guard CarrierTransportMatrix.compat(carrier: c, transport: d.transport) != .fail else { return false }
        if CarrierTransportMatrix.requiresRoomID(carrier: c) {
            return !d.roomID.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }
    // eoc #452

    private var requiresRoomID: Bool { CarrierTransportMatrix.requiresRoomID(carrier: carrier) }

    private var canSubmit: Bool {
        // (audit) `!= .fail` is belt-and-braces: the ✗ chips are disabled and the
        // carrier onChange resets transport to the default, but a submit of a
        // combo the matrix marks broken must never install a dead server.
        (!requiresRoomID || !roomID.trimmingCharacters(in: .whitespaces).isEmpty)
            && CarrierTransportMatrix.compat(carrier: carrier, transport: transport) != .fail
            // #452: every enabled extra must be valid too.
            && enabledExtraCarriers.allSatisfy { extraIsValid($0) }
    }

    /// (audit) transport chips with the ✗ combos for the current carrier
    /// disabled (OlcOption.disabled) and the reason surfaced to VoiceOver.
    /// #452: parametrised by carrier so the extras sub-forms reuse it.
    private func transportOptions(for carrier: String) -> [OlcOption<String>] {
        CarrierTransportMatrix.transports.map { t -> OlcOption<String> in
            let fails = CarrierTransportMatrix.compat(carrier: carrier, transport: t) == .fail
            return OlcOption(
                value: t,
                label: CarrierTransportMatrix.transportLabel(t),
                disabled: fails,
                disabledReason: fails
                    ? L10n.matrixFail_fmt.formatted(CarrierTransportMatrix.carrierLabel(carrier))
                    : nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                carrierSection
                transportSection
                roomIDSection
                jitsiSection
                wbTokenSection
                seiSection
                extrasSection   // #452
                defaultsInfoSection
            }
            // #452: reuse mode gets its own title + confirm label.
            .navigationTitle((singleOnly ? L10n.addProtocolTitle : L10n.installTitle).localized())
            .navigationBarTitleDisplayMode(.inline)
            // #262: shared sheet chrome (✕ close + full-width primary footer).
            .olcSheet(confirm: (singleOnly ? L10n.addProtocolAction : L10n.actionInstall).localized(),
                      icon: singleOnly ? "plus.circle" : "arrow.down.app",
                      disabled: !canSubmit) { submit() }
        }
    }

    // MARK: Sections

    private var carrierSection: some View {
        // #455 (editorial): the carrier section used to be the ONE form section
        // with a title but no footer, while transport/room/jitsi/wb/sei all
        // explain themselves — so the app's FIRST and most important choice got
        // the least guidance. It now has a header + a footer that says which
        // carrier to pick for what (the `carrierChoiceFooter` string).
        Section {
            // #452 was: options from CarrierTransportMatrix.carriers — now the
            // (possibly restricted) availableCarriers.
            OlcChipPicker(selection: $carrier,
                          options: availableCarriers.map { ($0, CarrierTransportMatrix.carrierLabel($0)) })
                .onChange(of: carrier) { _, c in
                    transport = CarrierTransportMatrix.defaultTransport(for: c)
                    // #452: the new primary can't also be an extra.
                    extras[c] = nil
                }
        } header: {
            Text(L10n.sectionCarrier.localized())
        } footer: {
            Text(L10n.carrierChoiceFooter.localized()).font(.caption2)
        }
    }

    private var transportSection: some View {
        Section {
            // (audit) options carry disabled+reason for the ✗ combos.
            OlcChipPicker(selection: $transport, options: transportOptions(for: carrier))
                .onChange(of: transport) { _, newTransport in
                    if newTransport != "seichannel" {
                        seiFPS = 30; seiBatch = 10; seiFrag = 1200; seiACK = 1
                    }
                }
        } header: {
            Text(L10n.transportSectionHeader.localized())
        } footer: {
            Text(transportFooter).font(.caption2)
        }
    }

    @ViewBuilder
    private var roomIDSection: some View {
        if requiresRoomID {
            Section {
                TextField(L10n.fieldRoomID.localized(), text: $roomID)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text(L10n.roomIDSectionHeader.localized())
            } footer: {
                Text(roomFooter).font(.caption2)
            }
        } else {
            Section {
                Label(L10n.roomIDAutoGenHint.localized(),
                      systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // #256: only Jitsi has a user-pickable rendezvous instance (Telemost/WBStream
    // use fixed backends). Shown for jitsi so users aren't silently funnelled onto
    // the shared public default.
    @ViewBuilder
    private var jitsiSection: some View {
        if carrier == "jitsi" {
            Section {
                TextField(L10n.fieldJitsiURL.localized(), text: $jitsiBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            } header: {
                Text(L10n.jitsiServerHeader.localized())
            } footer: {
                Text(L10n.jitsiServerFooter.localized()).font(.caption2)
            }
        }
    }

    // #436: wbstream account token → server `auth.token`. Optional (empty = an
    // anonymous guest); needed for datachannel, which requires publish rights.
    // Masked, like other secret entry — the value goes to the server config and
    // the connection's Keychain, never to logs.
    @ViewBuilder
    private var wbTokenSection: some View {
        if carrier == "wbstream" {
            Section {
                SecureField(L10n.wbTokenFieldLabel.localized(), text: $wbToken)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text(L10n.wbTokenHeader.localized())
            } footer: {
                Text(L10n.wbTokenFooter.localized()).font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var seiSection: some View {
        if transport == "seichannel" {
            // (audit) was: literal "FPS:/Batch:/Frag:/ACK:" — RU users saw mixed
            // languages; the sei* keys already exist (used by AddConnectionView).
            Section {
                Stepper("\(L10n.seiFpsLabel.localized()): \(seiFPS)", value: $seiFPS, in: 1...120)
                Stepper("\(L10n.seiBatchLabel.localized()): \(seiBatch)", value: $seiBatch, in: 1...256)
                Stepper("\(L10n.seiFragLabel.localized()): \(seiFrag)", value: $seiFrag, in: 100...65535, step: 100)
                Stepper("\(L10n.seiAckLabel.localized()): \(seiACK)", value: $seiACK, in: 0...10)
            } header: {
                Text(L10n.seiSettingsHeader.localized())
            } footer: {
                Text(L10n.seiSettingsFooter.localized()).font(.caption2)
            }
        }
    }

    // boc #452: additional-protocol toggles with inline sub-forms. Each enabled
    // extra mirrors the primary's fields (transport chips gated by the matrix,
    // room field / auto-generate hint, jitsi base, wb token) — but not the SEI
    // steppers (server defaults; see the ExtraDraft comment).
    @ViewBuilder
    private var extrasSection: some View {
        if !singleOnly {
            Section {
                ForEach(extraCarriers, id: \.self) { c in
                    extraRows(c)
                }
            } header: {
                Text(L10n.installExtrasHeader.localized())
            } footer: {
                Text(L10n.installExtrasFooter.localized()).font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func extraRows(_ c: String) -> some View {
        let binding = draftBinding(c)
        Toggle(L10n.installExtraToggle_fmt.formatted(CarrierTransportMatrix.carrierLabel(c)),
               isOn: binding.enabled)
        if draft(c).enabled {
            OlcChipPicker(selection: binding.transport, options: transportOptions(for: c))
            // #455 (editorial): the extras used to offer a transport picker with
            // NO compatibility hint, while the primary transport section shows
            // one — the same "hint at the top but not at the bottom" gap. Mirror
            // the primary's compat caption here so every protocol choice is
            // explained the same way.
            Text(extraCompat(c))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if CarrierTransportMatrix.requiresRoomID(carrier: c) {
                TextField(L10n.fieldRoomID.localized(), text: binding.roomID)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                Label(L10n.roomIDAutoGenHint.localized(), systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if c == "jitsi" {
                TextField(L10n.fieldJitsiURL.localized(), text: binding.jitsiBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            if c == "wbstream" {
                SecureField(L10n.wbTokenFieldLabel.localized(), text: binding.wbToken)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }
    // eoc #452

    private var defaultsInfoSection: some View {
        Section {
            Text(L10n.carrierFooter.localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Logic

    private func submit() {
        // Telemost shows room IDs with spaces ("3528 5410 1234") for readability;
        // the API form has no spaces. Strip them so users can paste either form.
        let cleanedRoom = roomID
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        // Never send an empty OLCRTC_JITSI_URL (srv.sh's `:-` default only fills
        // an *unset* var, not an empty one) — fall back to the shared default.
        let cleanedJitsi = jitsiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = InstallOptions(
            carrier:      carrier,
            transport:    transport,
            roomID:       requiresRoomID ? cleanedRoom : "",
            jitsiBaseURL: cleanedJitsi.isEmpty ? AppConstants.defaultJitsiBaseURL : cleanedJitsi,
            seiFPS:       seiFPS,
            seiBatch:     seiBatch,
            seiFrag:      seiFrag,
            seiACK:       seiACK,
            wbToken:      carrier == "wbstream" ? wbToken.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        )
        // boc #452: extras — same cleaning rules as the primary; SEI stays on
        // defaults (see ExtraDraft). Order follows the matrix's carriers list.
        let extraOptions: [InstallOptions] = singleOnly ? [] : enabledExtraCarriers.map { c in
            let d = draft(c)
            let room = d.roomID.components(separatedBy: .whitespacesAndNewlines).joined()
            let jitsi = d.jitsiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return InstallOptions(
                carrier:      c,
                transport:    d.transport,
                roomID:       CarrierTransportMatrix.requiresRoomID(carrier: c) ? room : "",
                jitsiBaseURL: jitsi.isEmpty ? AppConstants.defaultJitsiBaseURL : jitsi,
                wbToken:      c == "wbstream" ? d.wbToken.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            )
        }
        onConfirm(primary, extraOptions)
        // eoc #452
        dismiss()
    }

    // MARK: Footer helpers

    private var transportFooter: String {
        let compat: String
        switch CarrierTransportMatrix.compat(carrier: carrier, transport: transport) {
        case .recommended: compat = L10n.matrixRecommended_fmt.formatted(carrier)
        case .ok:          compat = L10n.matrixWorks_fmt.formatted(carrier)
        case .question:    compat = L10n.matrixQuestion_fmt.formatted(carrier)
        case .fail:        compat = L10n.matrixFail_fmt.formatted(carrier)
        case .unknown:     compat = L10n.matrixUnknown_fmt.formatted(carrier)
        }
        // #097 was: the warning also covered seichannel — stale since the install
        // sheet gained the SEI steppers (seiSection → installEnv → OLCRTC_SEI_*).
        // `vp8channel` tunes via the Settings sliders, `seichannel` via the
        // steppers above; only `videochannel` still installs with the server-side
        // defaults from scripts/srv.sh (OLCRTC_VIDEO_* deliberately has no UI —
        // #097 decision: ten niche knobs aren't worth the sheet sprawl).
        if transport == "videochannel" {
            return compat + "\n" + L10n.transportUsesServerDefaults_fmt.formatted(transport)
        }
        return compat
    }

    private var roomFooter: String {
        switch carrier {
        case "telemost": return L10n.roomIDTelemostHint.localized()
        case "wbstream": return L10n.roomIDWbstreamHint.localized()
        default:         return ""
        }
    }

    /// #455 (editorial): the compatibility caption for an EXTRA protocol's
    /// current carrier+transport — the extras' parity with the primary
    /// transport footer. Reuses the same matrix* strings.
    private func extraCompat(_ c: String) -> String {
        switch CarrierTransportMatrix.compat(carrier: c, transport: draft(c).transport) {
        case .recommended: return L10n.matrixRecommended_fmt.formatted(c)
        case .ok:          return L10n.matrixWorks_fmt.formatted(c)
        case .question:    return L10n.matrixQuestion_fmt.formatted(c)
        case .fail:        return L10n.matrixFail_fmt.formatted(c)
        case .unknown:     return L10n.matrixUnknown_fmt.formatted(c)
        }
    }
}
