import SwiftUI

// MARK: - AddConnectionView
//
// Editor sheet for ConnectionRecord. Two visible modes:
//
//  CREATE mode (existing == nil)
//    – URI paste field at the top so the user can paste any supported
//      proxy link (currently `olcrtc://...`; more protocols are coming).
//      Hitting "Parse" autofills the parameter fields below.
//    – Manual fields are always visible so the user can verify what was
//      parsed or build a record from scratch.
//
//  EDIT mode (existing != nil)
//    – URI field is hidden. Editing means tweaking existing parameters,
//      and a stale URI from the original server is confusing here.
//
// Today the form only knows how to render an olcrtc-shaped configuration
// (carrier + transport pickers, room/key/clientID fields). When other
// protocols (vless / xray / reality / rprx-vision / awg 2.0 / xhttp) come
// online, this view branches on the user-chosen ProtocolType and swaps to
// the appropriate protocol-specific editor. The URI parser is shared and
// already protocol-agnostic at the call site.
//
// Implementation note: SwiftUI's TextEditor doesn't support a native
// placeholder, so we overlay a Text view that disappears as the user
// starts typing.

struct AddConnectionView: View {
    var existing: ConnectionRecord? = nil
    /// Group names already used by other connections. The editor surfaces
    /// them in a quick-pick menu next to the freeform Group field.
    var existingGroups: [String] = []
    /// #361: invoked when a pasted blob resolves to a subscription (an https URL
    /// to fetch, or raw sub.md text) rather than a single connection. The host
    /// routes it through the confirm-then-import + dedup flow. A single olcrtc://
    /// link is handled in-place (fills the fields below), so it never calls this.
    var onImport: ((OlcrtcSubscription.ImportInput) -> Void)? = nil
    var onSave: (ConnectionRecord) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var uriText      = ""
    @State private var parseError   = ""
    @State private var showQRScan   = false

    @State private var name      = ""
    @State private var groupName = L10n.groupDefault.localized()
    @State private var carrier   = "wbstream"
    // #284: default to the carrier's recommended transport (wbstream+datachannel
    // is now `.question`); keeps the initial pick consistent with the matrix and
    // with InstallOptions / ReconfigureOptions.
    @State private var transport = CarrierTransportMatrix.defaultTransport(for: "wbstream")
    @State private var roomID    = ""
    @State private var key       = ""
    @State private var clientID  = "default"
    @State private var socksUser = ""
    @State private var socksPass = ""
    @State private var vp8FPS      : Int? = nil
    @State private var vp8BatchSize: Int? = nil
    // #355: sei params carried through paste/parse so a seichannel URI round-trips
    // its tuning (no sei UI yet — these hold the parsed/edited values silently).
    @State private var seiFPS  : Int = 30
    @State private var seiBatch: Int = 10
    @State private var seiFrag : Int = 1200
    @State private var seiACK  : Int = 1

    private var isCreate: Bool { existing == nil }

    private var isVP8: Bool { transport == "vp8channel" }

    // #365: sei params get a dedicated editor only for the seichannel transport.
    private var isSEI: Bool { transport == "seichannel" }

    // (audit) deliberately NOT gated on the compat matrix: an existing record or
    // an imported olcrtc:// URI may hold a combo the local matrix marks ✗ (a
    // remote server can be ahead of our table) — those stay savable, with the
    // red chip outline + footer as the warning. Only NEW picks are prevented,
    // via the disabled chips below.
    private var isValid: Bool {
        !name.isEmpty && !groupName.isEmpty && !carrier.isEmpty && !transport.isEmpty
            && !roomID.isEmpty && !key.isEmpty && !clientID.isEmpty
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

    private var currentCompatFails: Bool {
        CarrierTransportMatrix.compat(carrier: carrier, transport: transport) == .fail
    }

    /// (audit) compat footer under the transport picker — this editor had none
    /// (ported from InstallOptionsView.transportFooter, minus the server-side
    /// tuning note, which doesn't apply to a client-side record).
    private var transportFooter: String {
        let label = CarrierTransportMatrix.carrierLabel(carrier)
        switch CarrierTransportMatrix.compat(carrier: carrier, transport: transport) {
        case .recommended: return L10n.matrixRecommended_fmt.formatted(label)
        case .ok:          return L10n.matrixWorks_fmt.formatted(label)
        case .question:    return L10n.matrixQuestion_fmt.formatted(label)
        case .fail:        return L10n.matrixFail_fmt.formatted(label)
        case .unknown:     return L10n.matrixUnknown_fmt.formatted(label)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCreate {
                    uriSection
                }
                manualFields
            }
            .navigationTitle(isCreate
                             ? L10n.newConnectionTitle.localized()
                             : L10n.editConnectionTitle.localized())
            .navigationBarTitleDisplayMode(.inline)
            // #262: shared sheet chrome (✕ close + full-width primary footer).
            .olcSheet(confirm: L10n.save.localized(), disabled: !isValid) { save() }
        }
        .onAppear { prefill() }
        .sheet(isPresented: $showQRScan) {
            QRScannerSheet { scanned in
                uriText = scanned
                parseURI()
            }
        }
    }

    // MARK: URI paste

    // #258: Scan-QR / Paste-URI shortcuts. Both feed `parseURI()`, which fills the
    // manual fields below (was an inline TextEditor paste box).
    private var uriSection: some View {
        Section {
            HStack(spacing: 8) {
                OlcButton(L10n.scanQRAction.localized(), systemImage: "qrcode.viewfinder",
                          role: .secondary, fillWidth: true) {
                    showQRScan = true
                }
                OlcButton(L10n.pasteURIAction.localized(), systemImage: "doc.on.clipboard",
                          role: .secondary, fillWidth: true) {
                    pasteAndImport(UIPasteboard.general.string ?? "")
                }
            }
            .padding(.vertical, 4)

            // #265: manual entry — type or paste-and-edit a URI here; auto-parses
            // into the fields below (the redesign had left only Scan/Paste).
            TextField("olcrtc://…", text: $uriText, axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1...3)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: uriText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, let cfg = try? OlcrtcURI.parse(trimmed) else { return }
                    applyParsed(cfg)   // #414: shared Parsed→fields mapping
                    parseError = ""
                }

            if !parseError.isEmpty {
                Text(parseError).font(.caption).foregroundStyle(Theme.Palette.red) // #317 was: .foregroundStyle(.red) — status colors via Theme.Palette (#258 invariant)
            }
        } header: {
            Text(L10n.importByURI.localized())
        } footer: {
            Text(L10n.importHint.localized())
                .font(.caption2)
        }
    }

    // MARK: Manual fields

    @ViewBuilder private var manualFields: some View {
        Section(L10n.parametersHeader.localized()) {
            FormField(label: L10n.nameSettingLabel.localized(), placeholder: L10n.namePlaceholder.localized(), text: $name)

            groupField

            // #258: carrier / transport via OlcChipPicker (was Picker). The
            // per-transport compatibility symbols live in the Manage VPS matrix.
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.sectionCarrier.localized())
                    .font(.caption).foregroundStyle(.secondary)
                // (audit) guarded transport reset: only a USER carrier pick runs
                // through this Binding's setter. applyParsed / prefill write the
                // @State directly (carrier + transport together), so an imported
                // olcrtc:// URI or an edited record keeps its exact combo — the
                // reset can never fire on those paths. When the user's new
                // carrier makes the current transport a ✗ combo, transport snaps
                // to the carrier's default (matching Install/Reconfigure).
                OlcChipPicker(selection: Binding(
                    get: { carrier },
                    set: { newCarrier in
                        carrier = newCarrier
                        if CarrierTransportMatrix.compat(carrier: newCarrier,
                                                         transport: transport) == .fail {
                            transport = CarrierTransportMatrix.defaultTransport(for: newCarrier)
                        }
                    }
                ), options: CarrierTransportMatrix.carriers.map { ($0, CarrierTransportMatrix.carrierLabel($0)) })
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.labelTransport.localized())
                    .font(.caption).foregroundStyle(.secondary)
                // (audit) ✗ combos are disabled for NEW picks; an existing /
                // imported record already holding one stays selected + savable
                // (red chip outline + the red footer below carry the warning).
                OlcChipPicker(selection: $transport, options: transportOptions)
                Text(transportFooter)
                    .font(.caption2)
                    .foregroundStyle(currentCompatFails ? Theme.Palette.red
                                                        : Theme.Palette.textSecondary)
            }

            // (audit) was: hardcoded English labels "Room ID" / "Client ID" /
            // "Key (hex)" in an otherwise localized sheet.
            FormField(label: L10n.fieldRoomID.localized(), placeholder: L10n.roomIDLabel.localized(), text: $roomID)
                .onChange(of: roomID) { _, new in
                    let stripped = new.filter { !$0.isWhitespace }
                    if stripped != new { roomID = stripped }
                }
            FormField(label: L10n.clientIDLabel.localized(), placeholder: "default", text: $clientID)
            Text(L10n.clientIDFooter.localized())
                .font(.caption2)
                .foregroundStyle(.secondary)
            FormField(label: L10n.keyHexLabel.localized(), placeholder: L10n.keyPlaceholder.localized(), text: $key, secure: true)
        }

        if isVP8 {
            vp8Section
        }
        // #365: sei tuning, mirroring the vp8 section but shown only for seichannel.
        if isSEI {
            seiSection
        }
        // SOCKS auth (socksUser/socksPass) is configured globally in Settings,
        // not per-connection — removed from here to avoid confusion.
    }

    /// Group: freeform TextField + Menu of existing groups. Tap the menu
    /// icon to fill the field from the existing set (avoids typos like
    /// "Russia" vs "russia" splitting the same logical group), or just
    /// type a new name to create a new group implicitly.
    private var groupField: some View {
        HStack {
            Text(L10n.groupField.localized())
            TextField(L10n.groupDefault.localized(), text: $groupName)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
            if !existingGroups.isEmpty {
                Menu {
                    ForEach(existingGroups, id: \.self) { g in
                        Button(g) { groupName = g }
                    }
                } label: {
                    Image(systemName: "list.bullet.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: VP8 per-connection override

    private var vp8Section: some View {
        Section {
            HStack {
                Text(L10n.vp8FpsLabel.localized())
                Spacer()
                Text(vp8FPS.map(String.init)
                     ?? L10n.globalDefault_fmt.formatted(SettingsStore.shared.vp8FPS))
                    .foregroundStyle(vp8FPS == nil ? .secondary : .primary)
                Stepper("", value: Binding(
                    get: { vp8FPS ?? SettingsStore.shared.vp8FPS },
                    set: { vp8FPS = $0 }
                ), in: 1...120)
                .labelsHidden()
                if vp8FPS != nil {
                    Button { vp8FPS = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text(L10n.vp8BatchLabel.localized())
                Spacer()
                Text(vp8BatchSize.map(String.init)
                     ?? L10n.globalDefault_fmt.formatted(SettingsStore.shared.vp8BatchSize))
                    .foregroundStyle(vp8BatchSize == nil ? .secondary : .primary)
                Stepper("", value: Binding(
                    get: { vp8BatchSize ?? SettingsStore.shared.vp8BatchSize },
                    set: { vp8BatchSize = $0 }
                ), in: 1...64)
                .labelsHidden()
                if vp8BatchSize != nil {
                    Button { vp8BatchSize = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(L10n.vp8ParamsHeader.localized())
        } footer: {
            Text(L10n.overrideHint.localized())
                .font(.caption2)
        }
    }

    // MARK: SEI per-connection params (#365)

    // Mirrors `vp8Section` but sei values are non-optional on OlcrtcConnection
    // (defaults 30/10/1200/1, never "global"), so each row is a plain
    // value + Stepper bound straight to the Int state — no nil/×-reset affordance.
    private var seiSection: some View {
        Section {
            seiRow(L10n.seiFpsLabel.localized(),   value: $seiFPS,   range: 1...120)
            seiRow(L10n.seiBatchLabel.localized(), value: $seiBatch, range: 1...64)
            seiRow(L10n.seiFragLabel.localized(),  value: $seiFrag,  range: 1...8192, step: 100)
            seiRow(L10n.seiAckLabel.localized(),   value: $seiACK,   range: 0...10000, step: 1)
        } header: {
            Text(L10n.seiParamsHeader.localized())
        } footer: {
            Text(L10n.seiParamsHint.localized())
                .font(.caption2)
        }
    }

    private func seiRow(_ label: String, value: Binding<Int>,
                        range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(value.wrappedValue))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    // (audit) was: socksAuthSection — dead since SOCKS auth moved to Settings
    // (never referenced by any body). The $socksUser/$socksPass STATE stays:
    // prefill()/save() round-trip the values stored on existing records.

    // MARK: Logic

    /// #414: the single Parsed→editor-fields mapping, via `OlcrtcConnection.init(from:)`
    /// (which holds the sei/vp8 defaults). Shared by both URI-entry paths — the live
    /// field auto-parse and `parseURI` — so the mapping isn't duplicated (#355's
    /// `applySEI` is folded into `init(from:)`'s `?? default`).
    private func applyParsed(_ cfg: OlcrtcURI.Parsed) {
        let params = OlcrtcConnection(from: cfg)
        carrier      = params.carrier
        transport    = params.transport
        roomID       = params.roomID
        key          = params.key
        clientID     = params.clientID
        vp8FPS       = params.vp8FPS
        vp8BatchSize = params.vp8BatchSize
        seiFPS       = params.seiFPS
        seiBatch     = params.seiBatch
        seiFrag      = params.seiFrag
        seiACK       = params.seiACK
        if name.isEmpty {
            name = cfg.mimo.isEmpty ? "\(cfg.carrier) · \(cfg.transport)" : cfg.mimo
        }
    }

    /// #361: paste-and-import. Detects what the pasted blob is and routes it:
    ///   • a single olcrtc:// link → fill the fields here (the #354 single import);
    ///   • an https:// / olcrtc-sub:// URL, or raw sub.md text → hand to `onImport`,
    ///     which runs the confirm-then-import + dedup flow.
    /// A QR scan reuses `parseURI` directly (a QR encodes one connection URI).
    private func pasteAndImport(_ text: String) {
        let detected = OlcrtcSubscription.detectImport(text)
        switch detected {
        case .connectionURI(let uri):
            uriText = uri
            parseURI()
        case .subscriptionURL, .subscriptionBody:
            if let onImport {
                onImport(detected)
            } else {
                // No import host wired (e.g. edit mode) — fall back to field fill.
                uriText = text
                parseURI()
            }
        case .unrecognized:
            uriText = text
            parseURI()   // surfaces the parse error for an empty/garbage paste
        }
    }

    private func parseURI() {
        parseError = ""
        do {
            let cfg = try OlcrtcURI.parse(uriText)
            applyParsed(cfg)   // #414: shared Parsed→fields mapping (via init(from:))
            LogStore.shared.log(.connection,
                "✓ URI parsed: carrier=\(cfg.carrier) transport=\(cfg.transport) room=\(cfg.roomID.prefix(8))…")
        } catch {
            parseError = error.localizedDescription
            LogStore.shared.log(.connection, "✗ URI parse failed: \(error.localizedDescription)")
        }
    }

    private func save() {
        let params = OlcrtcConnection(
            carrier:      carrier,
            transport:    transport,
            roomID:       roomID,
            key:          key,
            clientID:     clientID,
            vp8FPS:       vp8FPS,
            vp8BatchSize: vp8BatchSize,
            socksUser:    socksUser,
            socksPass:    socksPass,
            seiFPS:       seiFPS,    // #355
            seiBatch:     seiBatch,
            seiFrag:      seiFrag,
            seiACK:       seiACK
        )
        let trimmedGroup = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        // #283: store the canonical default token when the user left the group at
        // the (localised) default or empty, so it localises at display time
        // instead of freezing the language it was created in.
        let resolvedGroup = (trimmedGroup.isEmpty || trimmedGroup == L10n.groupDefault.localized())
            ? ConnectionRecord.defaultGroupName : trimmedGroup
        let record = ConnectionRecord(
            id:        existing?.id ?? UUID(),
            name:      name,
            groupName: resolvedGroup,
            details:   .olcrtc(params)
        )
        onSave(record)
        Haptics.success()   // #455: a saved/edited connection lands with a success tap
        dismiss()
    }

    private func prefill() {
        guard let r = existing else {
            // Create mode: reset all fields to defaults
            name = ""; groupName = L10n.groupDefault.localized()
            carrier = "wbstream"; transport = CarrierTransportMatrix.defaultTransport(for: "wbstream")
            roomID = ""; key = ""; clientID = "default"
            socksUser = ""; socksPass = ""; vp8FPS = nil; vp8BatchSize = nil
            seiFPS = 30; seiBatch = 10; seiFrag = 1200; seiACK = 1   // #355
            uriText = ""; parseError = ""
            return
        }
        name      = r.name
        // #283: show the localised default ("Основная") in the edit field, not the
        // raw "Servers" token; `save()` maps it back to the canonical token.
        groupName = ConnectionRecord.displayGroupName(r.groupName)
        if case .olcrtc(let p) = r.details {
            carrier      = p.carrier
            transport    = p.transport
            roomID       = p.roomID
            key          = p.key
            clientID     = p.clientID
            vp8FPS       = p.vp8FPS
            vp8BatchSize = p.vp8BatchSize
            socksUser    = p.socksUser
            socksPass    = p.socksPass
            seiFPS       = p.seiFPS    // #355
            seiBatch     = p.seiBatch
            seiFrag      = p.seiFrag
            seiACK       = p.seiACK
        }
    }
}
