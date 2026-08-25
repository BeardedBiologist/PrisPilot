import SwiftUI
import AuthenticationServices

// MARK: - Sign-In View

struct SignInView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "cart.fill.badge.plus")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("PrisPilot")
                        .font(.largeTitle.weight(.bold))
                    Text("Sign in to sync prices and lists across your devices, and share with your household.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let auth):
                            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                            authStore.handleCredential(credential)
                            dismiss()
                        case .failure(let error):
                            authStore.handleSignInError(error)
                        }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)

                    if let errorMessage = authStore.signInError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

#if DEBUG
                    Button("Use Mock Account (Debug)") {
                        authStore.signInWithMockAccount()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
#endif
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("Your data stays private. PrisPilot uses your Apple ID only to protect your account and enable sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Account Management View

struct AccountManagementView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var authStore
    @State private var showSignOutConfirmation = false
    @State private var householdName = ""
    @State private var inviteEmail = ""
    @State private var inviteCode = ""
    @State private var acceptCode = ""
    @State private var inviteError: String?
    @State private var acceptMessage: String?

    private var user: AuthUser? { authStore.state.user }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Text(user?.initials ?? "?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user?.displayName ?? "Apple Account")
                            .font(.headline)
                        if let email = user?.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No email shared")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            householdSection

            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button(role: .destructive) {
                    // TODO: Phase 3 — call server to delete account, then sign out
                } label: {
                    Label("Delete Account", systemImage: "person.badge.minus")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Permanently removes your account and all synced data. Local data on this device is not affected.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) { authStore.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in at any time. Your local data will remain on this device.")
        }
    }

    @ViewBuilder
    private var householdSection: some View {
        if let household = store.household {
            Section {
                LabeledContent("Name", value: household.name)

                ForEach(household.members) { member in
                    HStack {
                        Label(member.displayName ?? member.userID, systemImage: member.role == .owner ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        Spacer()
                        Text(member.role.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Invite email (optional)", text: $inviteEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                Button {
                    createInvitation()
                } label: {
                    Label("Create invite code", systemImage: "envelope.badge")
                }

                if let pending = store.invitations.last(where: { $0.status == .pending && !$0.isExpired }) {
                    LabeledContent("Latest invite code", value: pending.shareCode)
                    Text("Expires \(pending.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let inviteError {
                    Text(inviteError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(role: household.ownerUserID == user?.id ? .destructive : nil) {
                    guard let user else { return }
                    if household.ownerUserID == user.id {
                        store.disbandHousehold()
                    } else {
                        store.leaveHousehold(userID: user.id)
                    }
                } label: {
                    Label(household.ownerUserID == user?.id ? "Disband household" : "Leave household", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                Text("Household")
            } footer: {
                Text("This is a local household scaffold. Real shared sync is still blocked until a cloud backend is connected.")
            }
        } else {
            Section {
                TextField("Household name", text: $householdName)
                    .textInputAutocapitalization(.words)

                Button {
                    createHousehold()
                } label: {
                    Label("Create household", systemImage: "person.3")
                }
                .disabled(user == nil)

                TextField("Invite code", text: $acceptCode)
                    .textInputAutocapitalization(.characters)

                Button {
                    acceptInvitation()
                } label: {
                    Label("Accept invite code", systemImage: "person.badge.plus")
                }
                .disabled(user == nil || acceptCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let acceptMessage {
                    Text(acceptMessage)
                        .font(.caption)
                        .foregroundStyle(acceptMessage.contains("accepted") ? .green : .red)
                }
            } header: {
                Text("Household")
            } footer: {
                Text("Households are local until account sync is connected. Invite codes can be used on this device to exercise the flow.")
            }
        }
    }

    private func createHousehold() {
        guard let user else { return }
        store.createHousehold(name: householdName, owner: user)
        householdName = ""
    }

    private func createInvitation() {
        guard let user else { return }
        if store.createHouseholdInvitation(inviteeEmail: inviteEmail, inviterUserID: user.id) == nil {
            inviteError = "Create a household before inviting members."
        } else {
            inviteError = nil
            inviteEmail = ""
        }
    }

    private func acceptInvitation() {
        guard let user else { return }
        let accepted = store.acceptHouseholdInvitation(shareCode: acceptCode, user: user)
        acceptMessage = accepted ? "Invite accepted." : "Invite code not found or expired."
        if accepted {
            acceptCode = ""
        }
    }
}
