import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section {
                    Label("Sign In", systemImage: "person.circle")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Sign in to sync across devices and share with your household.")
                }

                // Country & Currency
                Section("Region") {
                    LabeledContent("Country", value: store.settings.country.name)
                    LabeledContent("Currency", value: "\(store.settings.currency.code) (\(store.settings.currency.symbol))")
                    LabeledContent("Language", value: store.settings.language.uppercased())
                }

                // Stores
                Section("Supermarkets") {
                    NavigationLink("Manage stores & branches") {
                        StoreSettingsView()
                    }
                }

                // Shopping
                Section("Shopping") {
                    LabeledContent("Strategy", value: store.settings.cheapestDefinition.rawValue)
                    LabeledContent("Max stores", value: "\(store.settings.maxSupermarketCount)")
                    LabeledContent("Min. extra saving", value: "kr \(NSDecimalNumber(decimal: store.settings.minimumAdditionalStoreSavings).stringValue)")
                }

                // AI
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

                // Data
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

    var body: some View {
        List {
            ForEach(store.chains) { chain in
                Section(chain.name) {
                    let chainBranches = store.branches.filter { $0.chainID == chain.id }
                    if chainBranches.isEmpty {
                        Text("No branches added")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(chainBranches) { branch in
                            HStack {
                                Text(branch.name)
                                Spacer()
                                Image(systemName: branch.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(branch.isEnabled ? .green : Color(.systemGray3))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Stores & Branches")
        .navigationBarTitleDisplayMode(.large)
    }
}
