import SwiftUI

// MARK: - ServerAdvancedView (#459)
//
// #459: "Manage server" — the pushed destination behind the one low-emphasis row
// at the foot of a VPS card. It exists because the card's ⋯ menu had grown to
// THIRTEEN items, six of them destructive, and the owner had to open it for
// almost everything: "to do anything I have to go into those tiny three dots
// where SO MUCH is shown".
//
// The split is by frequency, not by danger alone:
//   • constantly       → visible buttons on the card (Check server, Container logs)
//   • the next step    → the card's ONE primary button (Start / Stop / Install…)
//   • occasionally     → the card's ⋯ menu, now 5 safe items
//   • rarely / destructive → here
//
// A `Form` is the whole point of pushing rather than menu-ing. A `Menu` cannot
// render a footer, which is why "Wipe all olcrtc data from server" used to sit
// in a scrolling list with nothing but its own name to warn you. Every
// destructive row here carries a sentence saying what it destroys, and each one
// still ends in the SAME `.confirmationDialog` it always did (owned by
// ServersView.hostConfirmations) — so a destructive verb is now behind two
// deliberate steps, a push and a confirm, instead of one menu tap.
//
// Plain values and closures only — no stores, no `@ObservedObject` — the same
// rule `ServerCardView` and `ProtocolRowView` follow, so this screen costs the
// type-checker nothing. (ServersView has hit its expression budget three times.)

struct ServerAdvancedView: View {
    /// Server label, for the title.
    let hostLabel: String
    /// #451: key-auth hosts cannot produce a full-access link (it would have to
    /// embed the private key). The row stays visible and explains on tap.
    let isKeyAuth: Bool
    /// A container is installed but no ConnectionRecord links to it (#303).
    let hasRecoverOption: Bool
    /// This host owns a ConnectionRecord — without one there is nothing to share.
    let hasLinkedConnection: Bool
    /// A probe found a container: Update / Remove container have a subject.
    let hasContainer: Bool
    /// Podman is present, so there is something a deep wipe could remove.
    let canDeepUninstall: Bool
    /// An SSH op holds the lane; every row here would collide with it.
    let actionsDisabled: Bool
    let onRecover: () -> Void
    let onShareFullAccess: () -> Void
    let onUpdate: () -> Void
    let onReboot: () -> Void
    let onUninstall: () -> Void
    let onDeepUninstall: () -> Void
    let onRemoveHost: () -> Void

    var body: some View {
        Form {
            connectionSection
            maintenanceSection
            removeSection
        }
        .navigationTitle(L10n.vpsAdvancedTitle_fmt.formatted(hostLabel))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(actionsDisabled)
    }

    // MARK: Connection

    @ViewBuilder
    private var connectionSection: some View {
        if hasRecoverOption || hasLinkedConnection {
            Section {
                if hasRecoverOption {
                    plainRow(L10n.actionRecoverConnection.localized(),
                             systemImage: "arrow.counterclockwise.circle",
                             action: onRecover)
                }
                if hasLinkedConnection { shareFullAccessRow }
            } header: {
                Text(L10n.vpsAdvancedConnectionHeader.localized())
            }
        }
    }

    /// #135/#451: destructive for password hosts (the link carries the SSH
    /// credentials); for key hosts the tap is the explanation instead, so the
    /// row must not wear the destructive role it will never perform.
    private var shareFullAccessRow: some View {
        Button(role: shareRole, action: onShareFullAccess) {
            Label(L10n.shareFullAccessTitle.localized(), systemImage: "key.horizontal")
        }
    }

    private var shareRole: ButtonRole? { isKeyAuth ? nil : .destructive }

    // MARK: Maintenance

    @ViewBuilder
    private var maintenanceSection: some View {
        Section {
            if hasContainer {
                // #459: the full label finally fits — in a menu row it competed
                // with twelve siblings for one line.
                plainRow(L10n.actionUpdate.localized(),
                         systemImage: "arrow.triangle.2.circlepath",
                         action: onUpdate)
            }
            destructiveRow(L10n.actionReboot.localized(),
                           systemImage: "arrow.clockwise",
                           note: L10n.vpsAdvancedRebootFooter.localized(),
                           action: onReboot)
        } header: {
            Text(L10n.vpsAdvancedMaintenanceHeader.localized())
        }
    }

    // MARK: Remove

    @ViewBuilder
    private var removeSection: some View {
        Section {
            if hasContainer {
                destructiveRow(L10n.actionUninstall.localized(),
                               systemImage: "trash",
                               note: L10n.vpsAdvancedUninstallFooter.localized(),
                               action: onUninstall)
            }
            if canDeepUninstall {
                destructiveRow(L10n.actionDeepUninstall.localized(),
                               systemImage: "flame",
                               note: L10n.vpsAdvancedDeepUninstallFooter.localized(),
                               action: onDeepUninstall)
            }
            destructiveRow(L10n.actionRemoveFromList.localized(),
                           systemImage: "minus.circle",
                           note: L10n.vpsAdvancedRemoveHostFooter.localized(),
                           action: onRemoveHost)
        } header: {
            Text(L10n.vpsAdvancedRemoveHeader.localized())
        }
    }

    // MARK: Rows

    private func plainRow(_ title: String, systemImage: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }

    /// #459: the sentence under the verb is the reason this screen exists.
    /// The note keeps its own secondary colour so the destructive tint stays on
    /// the NAME of the action and never washes out its explanation.
    private func destructiveRow(_ title: String, systemImage: String,
                                note: String,
                                action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: systemImage)
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
