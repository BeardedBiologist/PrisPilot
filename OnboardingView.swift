import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onStartAISetup: () -> Void
    @State private var step: Step = .welcome
    @State private var selectedBranchIDs: Set<UUID> = []

    init(onStartAISetup: @escaping () -> Void = {}) {
        self.onStartAISetup = onStartAISetup
    }

    enum Step { case welcome, selectStores, done }

    var body: some View {
        NavigationStack {
            switch step {
            case .welcome:    welcomeStep
            case .selectStores: storeStep
            case .done:       doneStep
            }
        }
        .interactiveDismissDisabled(step != .welcome)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "cart.fill.badge.plus")
                    .font(.system(size: 88))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, options: .nonRepeating)

                VStack(spacing: 8) {
                    Text("PrisPilot")
                        .font(.largeTitle.weight(.bold))
                    Text("Track grocery prices, manage\nlists, and shop smarter.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    step = .selectStores
                } label: {
                    Label("Set up manually", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    store.startAIOnboardingChat()
                    store.settings.onboardingCompleted = true
                    onStartAISetup()
                    dismiss()
                } label: {
                    Label("Set up with AI in Chat", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Skip for now") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Skip") { dismiss() }.foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Store Selection

    private var storeStep: some View {
        List {
            Section {
                Text("Pick the store branches you shop at. You can change these any time in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(store.chains) { chain in
                let chainBranches = store.branches.filter { $0.chainID == chain.id }
                if !chainBranches.isEmpty {
                    Section(chain.name) {
                        ForEach(chainBranches) { branch in
                            HStack {
                                Text(branch.displayName)
                                Spacer()
                                Image(systemName: selectedBranchIDs.contains(branch.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedBranchIDs.contains(branch.id) ? .blue : Color(.systemGray3))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedBranchIDs.contains(branch.id) {
                                    selectedBranchIDs.remove(branch.id)
                                } else {
                                    selectedBranchIDs.insert(branch.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Your Stores")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Continue") {
                    applyBranchSelection()
                    step = .done
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            // Pre-select all branches by default
            selectedBranchIDs = Set(store.branches.map { $0.id })
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, options: .nonRepeating)

                VStack(spacing: 10) {
                    Text("You're all set!")
                        .font(.largeTitle.weight(.bold))
                    let count = store.enabledBranches.count
                    Text("Tracking \(count) store branch\(count == 1 ? "" : "es").")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    tipRow("bubble.left.and.bubble.right.fill", "Chat with AI to record prices and manage lists")
                    tipRow("cart.fill",  "Browse and manage shopping lists manually")
                    tipRow("tag.fill",   "Compare prices across your enabled stores")
                    tipRow("brain.head.profile", "Your AI learns your preferences over time")
                }
                .padding(18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            }

            Spacer()

            Button("Start Shopping") {
                store.settings.onboardingCompleted = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 48)
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func applyBranchSelection() {
        for i in store.branches.indices {
            store.branches[i].isEnabled = selectedBranchIDs.contains(store.branches[i].id)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppStore.shared)
}
