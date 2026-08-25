import SwiftUI
import CoreLocation
import MapKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var authStore
    @State private var showSignIn = false
    @State private var showOnboarding = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    accountRow
                } footer: {
                    if !authStore.state.isSignedIn {
                        Text("Sign in to sync across devices and share with your household.")
                    }
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
                    NavigationLink {
                        ShoppingOptimisationSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Strategy", value: store.settings.cheapestDefinition.rawValue)
                            Text("Max \(store.settings.maxSupermarketCount) stores · min. kr \(NSDecimalNumber(decimal: store.settings.minimumAdditionalStoreSavings).stringValue) extra saving")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("AI") {
                    NavigationLink("AI Memory") {
                        MemoryListView()
                    }
                    NavigationLink("AI Permissions") {
                        AIPermissionsView()
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

                Section("Community Pricing") {
                    NavigationLink {
                        CommunityPricingSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(
                                "Participation",
                                value: store.settings.participatesInCommunityPricing ? "Opted in" : "Off"
                            )
                            Text("\(store.communityContributions.count) local contribution\(store.communityContributions.count == 1 ? "" : "s") queued")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Data") {
                    Button {
                        store.resetOnboarding()
                        showOnboarding = true
                    } label: {
                        Label("Restart onboarding", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        prepareExport()
                    } label: {
                        Label("Prepare data export", systemImage: "doc.badge.arrow.up")
                    }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share exported JSON", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                }
            }
            .reservesFloatingTabBarSpace()
            .navigationTitle("Profile & Settings")
            .sheet(isPresented: $showSignIn) {
                SignInView()
                    .environment(authStore)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
                    .environment(store)
            }
            .alert("Delete all local data?", isPresented: $showDeleteAllConfirmation) {
                Button("Delete", role: .destructive) {
                    store.deleteAllLocalData()
                    exportURL = nil
                    exportError = nil
                    showOnboarding = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes local prices, lists, recipes, memories, household data, chat history, community queue, and settings from this device.")
            }
        }
    }

    private func prepareExport() {
        do {
            exportURL = try store.writeExportFile()
            exportError = nil
        } catch {
            exportURL = nil
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var accountRow: some View {
        switch authStore.state {
        case .unknown:
            HStack {
                Label("Checking account…", systemImage: "person.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        case .signedOut:
            Button { showSignIn = true } label: {
                Label("Sign in with Apple", systemImage: "applelogo")
            }
        case .signedIn(let user):
            NavigationLink {
                AccountManagementView()
                    .environment(authStore)
            } label: {
                HStack(spacing: 12) {
                    Text(user.initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.blue, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? "Apple Account")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct CommunityPricingSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section {
                Toggle("Share anonymous prices", isOn: Binding(
                    get: { store.settings.participatesInCommunityPricing },
                    set: { store.settings.participatesInCommunityPricing = $0 }
                ))
            } footer: {
                Text("When enabled, new local price observations are queued as anonymous structured contributions. Receipt images, account identity, and personal notes are never included.")
            }

            Section("Local Queue") {
                LabeledContent("Queued contributions", value: "\(store.communityContributions.count)")
                LabeledContent("Flagged reports", value: "\(store.communityContributions.filter(\.isFlagged).count)")
                LabeledContent("Anonymous ID", value: shortAnonymousID)
            }

            Section("Backend Status") {
                Label("Shared backend not connected yet", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
                Text("Contributions stay on device until a CloudKit, Supabase, or Firebase backend is selected and connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .reservesFloatingTabBarSpace()
        .navigationTitle("Community Pricing")
        .navigationBarTitleDisplayMode(.large)
    }

    private var shortAnonymousID: String {
        String(store.settings.anonymousCommunityContributorID.prefix(8))
    }
}

struct ShoppingOptimisationSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section("Strategy") {
                Picker("Shopping strategy", selection: settingsBinding(\.cheapestDefinition)) {
                    ForEach(CheapestDefinition.allCases, id: \.self) { definition in
                        Text(definition.rawValue).tag(definition)
                    }
                }
            }

            Section {
                Stepper("Max stores: \(store.settings.maxSupermarketCount)", value: settingsBinding(\.maxSupermarketCount), in: 1...5)

                Stepper(value: minimumSavingsBinding, in: 0...500, step: 5) {
                    LabeledContent("Min. extra saving", value: "kr \(formatDecimal(store.settings.minimumAdditionalStoreSavings))")
                }
            } header: {
                Text("Store splitting")
            } footer: {
                Text("PrisPilot starts with the best one-store option, then only adds another store when the expected saving clears this threshold.")
            }

            Section {
                Stepper(value: travelCostPerKilometerBinding, in: 0...50, step: 1) {
                    LabeledContent("Cost per km", value: "kr \(formatDecimal(store.settings.travelCostPerKilometer))")
                }

                Stepper(value: fixedStoreVisitCostBinding, in: 0...200, step: 5) {
                    LabeledContent("Cost per store stop", value: "kr \(formatDecimal(store.settings.fixedStoreVisitCost))")
                }
            } header: {
                Text("Travel cost")
            } footer: {
                Text("Distance is entered manually per store for now. Set both values to zero to ignore travel cost.")
            }
        }
        .reservesFloatingTabBarSpace()
        .navigationTitle("Shopping Optimisation")
        .navigationBarTitleDisplayMode(.large)
    }

    private var minimumSavingsBinding: Binding<Double> {
        Binding(
            get: { NSDecimalNumber(decimal: store.settings.minimumAdditionalStoreSavings).doubleValue },
            set: { store.settings.minimumAdditionalStoreSavings = Decimal($0) }
        )
    }

    private var travelCostPerKilometerBinding: Binding<Double> {
        Binding(
            get: { NSDecimalNumber(decimal: store.settings.travelCostPerKilometer).doubleValue },
            set: { store.settings.travelCostPerKilometer = Decimal($0) }
        )
    }

    private var fixedStoreVisitCostBinding: Binding<Double> {
        Binding(
            get: { NSDecimalNumber(decimal: store.settings.fixedStoreVisitCost).doubleValue },
            set: { store.settings.fixedStoreVisitCost = Decimal($0) }
        )
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { store.settings[keyPath: keyPath] = $0 }
        )
    }

    private func formatDecimal(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}

struct AIPermissionsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            ForEach(AIPermissionArea.allCases) { area in
                Section(area.rawValue) {
                    ForEach(AIPermissionOperation.allCases) { operation in
                        Picker(operation.rawValue, selection: permissionBinding(area: area, operation: operation)) {
                            ForEach(AIPermissionMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }
                }
            }
        }
        .reservesFloatingTabBarSpace()
        .navigationTitle("AI Permissions")
        .navigationBarTitleDisplayMode(.large)
    }

    private func permissionBinding(area: AIPermissionArea, operation: AIPermissionOperation) -> Binding<AIPermissionMode> {
        Binding(
            get: { store.permissionMode(for: area, operation: operation) },
            set: { store.setPermissionMode($0, for: area, operation: operation) }
        )
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
        .reservesFloatingTabBarSpace()
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
                if let distance = branch.distanceFromHomeKm {
                    Text("\(distance.formatted()) km from home")
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
    @State private var distanceText = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var isEnabled = true
    @State private var isEstimatingDistance = false
    @State private var distanceError: String?
    @State private var distanceEstimator = StoreDistanceEstimator()

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
                    TextField("Distance from home in km", text: $distanceText)
                        .keyboardType(.decimalPad)
                    Button {
                        estimateDistance()
                    } label: {
                        if isEstimatingDistance {
                            Label("Estimating distance…", systemImage: "location")
                        } else {
                            Label("Estimate from current location", systemImage: "location.fill")
                        }
                    }
                    .disabled(isEstimatingDistance || geocodeQuery.isEmpty)
                    if let distanceError {
                        Text(distanceError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
        distanceText = branch.distanceFromHomeKm.map { String($0) } ?? ""
        latitude = branch.latitude
        longitude = branch.longitude
        isEnabled = branch.isEnabled
    }

    private func save() {
        let trimmedChain = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let distance = Double(distanceText.replacingOccurrences(of: ",", with: "."))

        switch mode {
        case .add:
            store.createStoreBranch(
                chainName: trimmedChain,
                branchName: trimmedBranch,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                distanceFromHomeKm: distance,
                latitude: latitude,
                longitude: longitude,
                isEnabled: isEnabled
            )
        case .edit(let branch):
            store.updateStoreBranch(
                matching: branch.displayName,
                chainName: trimmedChain,
                branchName: trimmedBranch,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                distanceFromHomeKm: distance,
                latitude: latitude,
                longitude: longitude,
                isEnabled: isEnabled
            )
        }
    }

    private var geocodeQuery: String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAddress.isEmpty {
            return trimmedAddress
        }
        let trimmedChain = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [trimmedChain, trimmedBranch, "Norway"].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func estimateDistance() {
        isEstimatingDistance = true
        distanceError = nil

        Task {
            do {
                let result = try await distanceEstimator.estimateDistance(to: geocodeQuery)
                await MainActor.run {
                    distanceText = String(format: "%.1f", result.distanceKm)
                    latitude = result.coordinate.latitude
                    longitude = result.coordinate.longitude
                    isEstimatingDistance = false
                }
            } catch {
                await MainActor.run {
                    distanceError = "Could not estimate distance. Check location permission and the store address."
                    isEstimatingDistance = false
                }
            }
        }
    }
}

private final class StoreDistanceEstimator: NSObject, CLLocationManagerDelegate {
    struct Estimate {
        var distanceKm: Double
        var coordinate: CLLocationCoordinate2D
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func estimateDistance(to query: String) async throws -> Estimate {
        let currentLocation = try await currentLocation()
        let destination = try await geocode(query)
        let distanceKm = currentLocation.distance(from: destination) / 1_000
        return Estimate(distanceKm: distanceKm, coordinate: destination.coordinate)
    }

    private func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                finishLocationRequest(.failure(CLError(.denied)))
            @unknown default:
                finishLocationRequest(.failure(CLError(.denied)))
            }
        }
    }

    private func geocode(_ query: String) async throws -> CLLocation {
        guard let request = MKGeocodingRequest(addressString: query) else {
            throw CLError(.geocodeFoundNoResult)
        }
        let mapItems = try await request.mapItems
        guard let location = mapItems.first?.location else {
            throw CLError(.geocodeFoundNoResult)
        }
        return location
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finishLocationRequest(.failure(CLError(.denied)))
        case .notDetermined:
            break
        @unknown default:
            finishLocationRequest(.failure(CLError(.denied)))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishLocationRequest(.failure(CLError(.locationUnknown)))
            return
        }
        finishLocationRequest(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocationRequest(.failure(error))
    }

    private func finishLocationRequest(_ result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }
}
