import SwiftUI

// MARK: - ReconfigureOptionsView
//
// Sheet shown when the user taps "Change Room / Transport" in the server menu.
// Identical layout to InstallOptionsView but with a different title and
// confirm-button label — no apt-get / go build, just rewrite server.yaml and
// restart the existing container.
//
// #258: carrier / transport use OlcChipPicker; the confirm action is a single
// full-width OlcButton(.primary) footer, with one close (✕) control.
//
// #451: gained the jitsi base-URL field and the wbstream token field so a
// reconfigure can produce the same valid config an install does:
//   • jitsi — srv.sh prefixes a short room name with the base URL at install
//     time, but reconfigureScript seds `id:` verbatim, and master's jitsi
//     provider rejects a bare room name (ErrInvalidRoomURL). The prefixing
//     therefore happens CLIENT-side in submit() (reconfigureScript ignores
//     OLCRTC_JITSI_URL).
//   • wbstream — the token now flows into `auth.token` via reconfigureScript's
//     token sed (previously only the full install could set/clear it).

struct ReconfigureOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var carrier   = "telemost"
    @State private var transport = CarrierTransportMatrix.defaultTransport(for: "telemost")
    @State private var roomID    = ""
    // #451: jitsi rendezvous base URL — mirrors InstallOptionsView (#256);
    // used only to normalise a short jitsi room name in submit().
    @State private var jitsiBaseURL = AppConstants.defaultJitsiBaseURL
    // #451: wbstream account token (auth.token) — mirrors InstallOptionsView
    // (#436); visible only for wbstream. Empty = anonymous guest (any stored
    // token line is removed from the server config).
    @State private var wbToken = ""

    let onConfirm: (InstallOptions) -> Void

    private var requiresRoomID: Bool { CarrierTransportMatrix.requiresRoomID(carrier: carrier) }

    private var canSubmit: Bool {
        // (audit) `!= .fail` is belt-and-braces: the ✗ chips are disabled and the
        // carrier onChange resets transport to the default, but a submit of a
        // combo the matrix marks broken must never reconfigure to a dead server.
        (!requiresRoomID || !roomID.trimmingCharacters(in: .whitespaces).isEmpty)
            && CarrierTransportMatrix.compat(carrier: carrier, transport: transport) != .fail
    }

    /// (audit) transport chips with the ✗ combos for the current carrier
    /// disabled (OlcOption.disabled) and the reason surfaced to VoiceOver.
    private var transportOptions: [OlcOption<String>] {
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
                infoSection
            }
            .navigationTitle(L10n.reconfigureTitle.localized())
            .navigationBarTitleDisplayMode(.inline)
            // #262: shared sheet chrome (✕ close + full-width primary footer).
            .olcSheet(confirm: L10n.actionChangeRoomTransport.localized(),
                      icon: "slider.horizontal.3", disabled: !canSubmit) { submit() }
        }
    }

    // MARK: Sections

    private var carrierSection: some View {
        Section(L10n.sectionCarrier.localized()) {
            OlcChipPicker(selection: $carrier,
                          options: CarrierTransportMatrix.carriers.map { ($0, CarrierTransportMatrix.carrierLabel($0)) })
                .onChange(of: carrier) { _, c in
                    transport = CarrierTransportMatrix.defaultTransport(for: c)
                }
        }
    }

    private var transportSection: some View {
        Section {
            // (audit) options carry disabled+reason for the ✗ combos.
            OlcChipPicker(selection: $transport, options: transportOptions)
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

    // #451: mirrors InstallOptionsView.jitsiSection (#256) — the base a short
    // room name is prefixed with (client-side here, see submit()).
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

    // #451: mirrors InstallOptionsView.wbTokenSection (#436).
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

    private var infoSection: some View {
        Section {
            // #451: second line — reconfigure rewrites only provider/id/
            // transport (+ auth.token); it does NOT write vp8:/sei: tuning
            // blocks, so after a transport switch the server runs its engine
            // defaults (master overlays only keys present in the YAML).
            Text(L10n.reconfigureInfoFooter.localized() + "\n" +
                 L10n.reconfigureTransportTuningFooter.localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Logic

    private func submit() {
        // Telemost shows room IDs with spaces ("3528 5410 1234") for readability;
        // the API form has no spaces. Strip them so users can paste either form.
        var cleanedRoom = roomID
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        // #451: normalise a short jitsi room name into the full URL the server
        // requires — the same rule srv.sh applies at install (base + "/" + name;
        // full http(s) URLs and host/room forms pass through verbatim).
        // reconfigureScript writes `id:` verbatim, so this must happen here.
        if carrier == "jitsi", !cleanedRoom.isEmpty,
           !cleanedRoom.contains("://"), !cleanedRoom.contains("/") {
            let trimmedBase = jitsiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            var base = trimmedBase.isEmpty ? AppConstants.defaultJitsiBaseURL : trimmedBase
            while base.hasSuffix("/") { base.removeLast() }   // srv.sh: ${JITSI_BASE%/}
            cleanedRoom = base + "/" + cleanedRoom
        }
        let cleanedJitsi = jitsiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        onConfirm(InstallOptions(
            carrier:      carrier,
            transport:    transport,
            roomID:       requiresRoomID ? cleanedRoom : "",
            jitsiBaseURL: cleanedJitsi.isEmpty ? AppConstants.defaultJitsiBaseURL : cleanedJitsi,
            wbToken:      carrier == "wbstream" ? wbToken.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        ))
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
        if transport == "seichannel" || transport == "videochannel" {
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
}
