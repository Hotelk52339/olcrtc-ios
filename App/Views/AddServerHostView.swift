import SwiftUI

// MARK: - AddServerHostView
//
// Sheet for creating/editing a ServerHost. Credentials are loaded from
// Keychain on open (edit mode) and saved there on submit. We pre-fill port 22
// and username root since that's the Timeweb default.
//
// #451: SSH auth is either a password (the default, unchanged) or an OpenSSH
// private key. The segmented picker swaps the password SecureField for a
// monospaced paste field + paste-from-clipboard button; the pasted key is
// validated immediately (SSHKeyAnalyzer) — ed25519/RSA accepted, ECDSA and
// non-OpenSSH formats rejected with guidance, and an encrypted key reveals
// the passphrase field. onSave now hands back an SSHSecret instead of a
// password string.

struct AddServerHostView: View {
    var existing: ServerHost? = nil
    var existingPassword: String? = nil          // pre-fill on edit; nil for add-new flow
    // #451: key-mode prefill on edit — the stored key text + passphrase.
    var existingKey: String? = nil
    var existingPassphrase: String? = nil
    // #295: every other host's label, for uniqueness validation. The label
    // (sanitised via `ServerHost.logFilePrefix`) prefixes the per-server
    // container-log file, so two hosts must not collapse to the same prefix.
    var otherLabels: [String] = []
    // #451 was: (ServerHost, String) — password only.
    var onSave: (ServerHost, SSHSecret) -> Void   // (host, credential)

    @Environment(\.dismiss) private var dismiss

    @State private var label    = ""
    @State private var host     = ""
    @State private var port     = "22"
    @State private var username = "root"
    @State private var password = ""
    // #451: key-auth state.
    @State private var authMethod: SSHAuthMethod = .password
    @State private var privateKey = ""
    @State private var keyPassphrase = ""
    @State private var keyDetection: SSHKeyAnalyzer.Detection? = nil

    @FocusState private var portFocused: Bool

    @State private var isTesting: Bool = false
    @State private var testResult: String? = nil
    @State private var testTask: Task<Void, Never>? = nil

    // #295: case-insensitive duplicate check on the raw label AND on the
    // sanitised log-file prefix — two visually distinct labels (e.g. "TW
    // Moscow #1" vs "TW Moscow-1") could still collapse to the same prefix.
    private var isDuplicateLabel: Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        let prefix = ServerHost.sanitizeLogFilePrefix(trimmed).lowercased()
        return otherLabels.contains { other in
            other.lowercased() == lowered
                || ServerHost.sanitizeLogFilePrefix(other).lowercased() == prefix
        }
    }

    /// #451: the pasted key is usable — a supported type, and if encrypted the
    /// passphrase has been entered (an encrypted key without one would only
    /// fail later at connect time).
    private var keyOK: Bool {
        guard let d = keyDetection, d.isSupported else { return false }
        return !d.isEncrypted || !keyPassphrase.isEmpty
    }

    private var credentialOK: Bool {
        authMethod == .privateKey ? keyOK : !password.isEmpty
    }

    private var isValid: Bool {
        !label.isEmpty && !host.isEmpty && Int(port) != nil
            && !username.isEmpty && credentialOK && !isDuplicateLabel
    }

    private var canTest: Bool {
        !host.isEmpty && Int(port) != nil && !username.isEmpty && credentialOK
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.sectionDescription.localized()) {
                    FormField(label: L10n.nameField.localized(), placeholder: "TW Moscow", text: $label)
                    // #295: server names must be unique — they prefix the
                    // per-server container-log file (`<name>_container.log`).
                    if isDuplicateLabel {
                        Text(L10n.duplicateServerNameError.localized())
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.red) // #317 was: .foregroundStyle(.red) — status colors via Theme.Palette (#258 invariant)
                    }
                }
                sshSection
                if canTest {
                    Section {
                        VStack(spacing: 6) {
                            Button {
                                testResult = nil
                                isTesting = true
                                testTask = Task { await testSSH() }
                            } label: {
                                HStack {
                                    if isTesting {
                                        ProgressView()
                                            .padding(.trailing, 4)
                                    }
                                    Text(L10n.testSSHAction.localized())
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isTesting)
                            if let result = testResult {
                                Text(result)
                                    .font(.caption)
                                    // #317 was: result.hasPrefix("✓") ? .green : .red
                                    .foregroundStyle(result.hasPrefix("✓") ? Theme.Palette.green : Theme.Palette.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil
                             ? L10n.newServerTitle.localized()
                             : L10n.editServerTitle.localized())
            .navigationBarTitleDisplayMode(.inline)
            // #262: keep the numeric-field keyboard toolbar; ✕ close + footer
            // come from the shared `.olcSheet` chrome below.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.actionDone.localized()) { portFocused = false }
                }
            }
            .olcSheet(confirm: L10n.save.localized(), disabled: !isValid) { save() }
            .onAppear { prefill() }
            .onDisappear {
                testTask?.cancel()
                testTask = nil
            }
        }
    }

    // MARK: SSH access section (#451: password OR private key)

    private var sshSection: some View {
        Section {
            FormField(label: L10n.hostField.localized(),  placeholder: "1.2.3.4", text: $host)
            FormField(label: L10n.portField.localized(),  placeholder: "22",      text: $port, keyboard: .numberPad, focusBinding: $portFocused)
            FormField(label: L10n.loginField.localized(), placeholder: "root",    text: $username)
            Picker(L10n.authMethodPickerLabel.localized(), selection: $authMethod) {
                Text(L10n.authMethodPassword.localized()).tag(SSHAuthMethod.password)
                Text(L10n.authMethodKey.localized()).tag(SSHAuthMethod.privateKey)
            }
            .pickerStyle(.segmented)
            if authMethod == .password {
                FormField(label: L10n.passwordField.localized(), placeholder: "•••", text: $password, secure: true)
            } else {
                keyEditor
            }
        } header: {
            Text(L10n.sshAccessHeader.localized())
        } footer: {
            if authMethod == .privateKey {
                Text(L10n.sshKeyFooter.localized()).font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var keyEditor: some View {
        // Paste target for the OpenSSH key file contents. TextEditor (not
        // SecureField): the armor is multi-line, and seeing the BEGIN/END
        // lines is exactly how users verify they pasted the right thing.
        TextEditor(text: $privateKey)
            .font(.system(.footnote, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .frame(minHeight: 110)
            .accessibilityLabel(L10n.authMethodKey.localized())
            .onChange(of: privateKey) { _, newValue in
                revalidateKey(newValue)
            }
        Button {
            if let s = UIPasteboard.general.string {
                privateKey = s   // onChange revalidates
            }
        } label: {
            Label(L10n.sshKeyPasteButton.localized(), systemImage: "doc.on.clipboard")
        }
        if let status = keyStatus {
            Text(status.text)
                .font(.caption)
                .foregroundStyle(status.ok ? Theme.Palette.green : Theme.Palette.red)
        }
        // Passphrase — revealed only when the pasted key is encrypted.
        if keyDetection?.isEncrypted == true {
            FormField(label: L10n.sshKeyPassphraseField.localized(), placeholder: "•••",
                      text: $keyPassphrase, secure: true)
        }
    }

    /// #451: immediate validation feedback under the key editor.
    private var keyStatus: (text: String, ok: Bool)? {
        guard let d = keyDetection else { return nil }
        switch d {
        case .ed25519(let enc):
            return (enc ? L10n.sshKeyDetectedEncrypted_fmt.formatted("ed25519")
                        : L10n.sshKeyDetected_fmt.formatted("ed25519"), true)
        case .rsa(let enc):
            return (enc ? L10n.sshKeyDetectedEncrypted_fmt.formatted("RSA")
                        : L10n.sshKeyDetected_fmt.formatted("RSA"), true)
        case .ecdsa:             return (L10n.sshKeyErrorECDSA.localized(), false)
        case .unsupportedFormat: return (L10n.sshKeyErrorUnsupportedFormat.localized(), false)
        case .notAKey:           return (L10n.sshKeyErrorNotAKey.localized(), false)
        }
    }

    private func revalidateKey(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        keyDetection = trimmed.isEmpty ? nil : SSHKeyAnalyzer.detect(text)
    }

    @MainActor
    private func testSSH() async {
        guard !Task.isCancelled else { return }
        guard let portInt = Int(port), portInt > 0, portInt <= 65535 else {
            testResult = "✗ Invalid port"
            isTesting = false
            return
        }
        let result = await NetPing.tcp(host: host, port: UInt16(portInt))
        if result.success, let ms = result.ms {
            testResult = String(format: "✓ Reachable (%.0f ms)", ms)
        } else {
            testResult = "✗ Unreachable"
        }
        isTesting = false
    }

    private func save() {
        var h = existing ?? ServerHost(label: "", host: "")
        h.label    = label
        h.host     = host
        h.port     = Int(port) ?? 22
        h.username = username
        h.authMethod = authMethod   // #451: nil only for pre-#451 stored hosts
        let secret: SSHSecret = authMethod == .privateKey
            ? .privateKey(text: privateKey,
                          passphrase: keyPassphrase.isEmpty ? nil : keyPassphrase)
            : .password(password)
        onSave(h, secret)
        dismiss()
    }

    private func prefill() {
        guard let h = existing else { return }
        label    = h.label
        host     = h.host
        port     = String(h.port)
        username = h.username
        authMethod = h.authMethod ?? .password
        // Credentials are fetched from Keychain by the caller and passed in;
        // leave the fields empty if they weren't available.
        if let pw = existingPassword { password = pw }
        if let key = existingKey {
            privateKey = key
            revalidateKey(key)
        }
        if let pp = existingPassphrase { keyPassphrase = pp }
    }
}
