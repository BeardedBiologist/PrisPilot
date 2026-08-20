import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Sign In", systemImage: "person.circle")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Sign in to sync across devices and share with your household.")
                }

                Section("Region") {
                    LabeledContent("Country", value: store.settings.country.name)
                    LabeledContent("Currency", value: "\(store.settings.currency.code) (\(store.settings.currency.symbol))")
                    LabeledContent("Language", value: store.settings.language.uppercased())
                }

                Section("Supermarkets") {
                    NavigationLink {
                        StoreSettingsView()
                    } label: {
                        LabeledContent("Manage stores", value: "\(store.branches.count) branches")
                    }
                }

                Section("Shopping") {
                    LabeledContent("Strategy", value: store.settings.cheapestDefinition.rawValue)
                    LabeledContent("Max stores", value: "\(store.settings.maxSupermarketCount)")
                    LabeledContent("Min. extra saving", value: "kr \(NSDecimalNumber(decimal: store.settings.minimumAdditionalStoreSavings).stringValue)")
                }

                Section("AI") {
                    NavigationLink("AI Memory") {
                        MemoryListView()
                    }
                    LabeledContent("Provider", value: store.currentAIService.providerName)
                    HStack(spacing: 8) {
                        Image(systemName: store.isUsingLiveAI ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(store.isUsingLiveAI ? .green : Color(.systemGray3))
                        Text(store.isUsingLiveAI ? "Live AI active" : "Mock AI (no key set)")
                            .foregroundStyle(store.isUsingLiveAI ? .primary : .secondary)
                            .font(.subheadline)
                    }
                }

                Section("Data") {
                    Label("Export data", systemImage: "square.and.arrow.up")
                    Label("Delete all data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Profile & Settings")
        }
    }
}

struct StoreSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var sheetMode: StoreEditorSheet.Mode?

    var body: some View {
        List {
            if store.branches.isEmpty {
                ContentUnavailableView(
                    "No Stores Yet",
                    systemImage: "storefront",
                    description: Text("Add the supermarket branches you use, or ask the AI to create stores for your area.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(store.chains) { chain in
                Section {
                    let chainBranches = store.branches.filter { $0.chainID == chain.id }
                    if chainBranches.isEmpty {
                        HStack {
                            Text("No branches")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                store.deleteChain(chain.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(chain.name)")
                        }
                    } else {
                        ForEach(chainBranches) { branch in
                            Button {
                                sheetMode = .edit(branch)
                            } label: {
                                StoreBranchRow(branch: branch) { enabled in
                                    store.setStoreBranchEnabled(matching: branch.displayName, isEnabled: enabled)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteStoreBranch(matching: branch.displayName)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text(chain.name)
                }
            }
        }
        .navigationTitle("Stores")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetMode = .add
                } label: {
                    Label("Add store", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheetMode) { mode in
            StoreEditorSheet(mode: mode)
                .environment(store)
        }
    }
}

struct StoreBranchRow: View {
    let branch: StoreBranch
    let onEnabledChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "storefront.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(branch.isEnabled ? .blue : .secondary)
                .frame(width: 34, height: 34)
                .background((branch.isEnabled ? Color.blue : Color.gray).opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(branch.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let address = branch.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("Enabled", isOn: Binding(
                get: { branch.isEnabled },
                set: onEnabledChange
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct StoreEditorSheet: View, Identifiable {
    enum Mode: Identifiable {
        case add
        case edit(StoreBranch)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let branch): return branch.id.uuidString
            }
        }
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var chainName = ""
    @State private var branchName = ""
    @State private var address = ""
    @State private var isEnabled = true

    var id: String { mode.id }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chain") {
                    TextField("e.g. Rema 1000, Meny, Kiwi", text: $chainName)
                        .textInputAutocapitalization(.words)
                    if !store.chains.isEmpty {
                        Picker("Existing chain", selection: $chainName) {
                            Text("Custom").tag(chainName)
                            ForEach(store.chains) { chain in
                                Text(chain.name).tag(chain.name)
                            }
                        }
                    }
                }

                Section("Branch") {
                    TextField("e.g. Pindsle", text: $branchName)
                        .textInputAutocapitalization(.words)
                    TextField("Address or area", text: $address)
                        .textInputAutocapitalization(.words)
                    Toggle("Enabled for shopping plans", isOn: $isEnabled)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear(perform: loadInitialValues)
        }
    }

    private var title: String {
        switch mode {
        case .add: return "Add Store"
        case .edit: return "Edit Store"
        }
    }

    private var saveTitle: String {
        switch mode {
        case .add: return "Add"
        case .edit: return "Save"
        }
    }

    private var isValid: Bool {
        !chainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadInitialValues() {
        guard case .edit(let branch) = mode else { return }
        chainName = branch.chainName
        branchName = branch.name
        address = branch.address ?? ""
        isEnabled = branch.isEnabled
    }

    private func save() {
        let trimmedChain = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .add:
            store.createStoreBranch(
                chainName: trimmedChain,
                branchName: trimmedBranch,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                isEnabled: isEnabled
            )
        case .edit(let branch):
            store.updateStoreBranch(
                matching: branch.displayName,
                chainName: trimmedChain,
                branchName: trimmedBranch,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                isEnabled: isEnabled
            )
        }
    }
}
