import Foundation
import Observation
import SwiftData

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
@Observable
class AppStore {
    // Settings
    var settings: AppSettings = .defaultSettings { didSet { persistIfReady() } }

    // Stores
    var chains: [SupermarketChain] = [] { didSet { persistIfReady() } }
    var branches: [StoreBranch] = [] { didSet { persistIfReady() } }

    // Products
    var products: [Product] = [] { didSet { persistIfReady() } }

    // Prices
    var priceObservations: [PriceObservation] = [] { didSet { persistIfReady() } }
    var communityContributions: [CommunityContribution] = [] { didSet { persistIfReady() } }

    // Shopping
    var shoppingLists: [ShoppingList] = [] { didSet { persistIfReady() } }

    // Recipes
    var recipes: [Recipe] = [] { didSet { persistIfReady() } }

    // AI Memory
    var memories: [AIMemory] = [] { didSet { persistIfReady() } }

    // Household
    var household: Household? { didSet { persistIfReady() } }
    var invitations: [Invitation] = [] { didSet { persistIfReady() } }

    // Chat
    var chatSessions: [ChatSession] = [] { didSet { persistIfReady() } }
    var selectedChatSessionID: UUID? { didSet { persistIfReady() } }

    // Onboarding
    var onboardingAnswers: [OnboardingQuestionID: String] = [:] { didSet { persistIfReady() } }
    var aiOnboardingProgressBySessionID: [UUID: Int] = [:]

    static let shared = AppStore()

    private var persistenceStore: SwiftDataPersistenceStore?
    private var isRestoringSnapshot = false

    init() {
        seedInitialData()
    }

    func configurePersistence(container: ModelContainer) {
        persistenceStore = SwiftDataPersistenceStore(container: container)
        if let snapshot = persistenceStore?.loadSnapshot() {
            restore(from: snapshot)
        } else {
            persistNow()
        }
    }

    // Reads from APIKeys.swift (gitignored). Falls back to mock if key is empty.
    var currentAIService: any AIService {
        let key = APIKeys.geminiAPIKey
        return key.isEmpty ? MockAIService() : GeminiAIService(apiKey: key)
    }

    var isUsingLiveAI: Bool { !APIKeys.geminiAPIKey.isEmpty }

    var enabledBranches: [StoreBranch] {
        branches.filter { $0.isEnabled }
    }

    var activeLists: [ShoppingList] {
        shoppingLists.filter { $0.status == .active }
    }

    var plannedLists: [ShoppingList] {
        shoppingLists.filter { $0.status == .planned }
    }

    var completedLists: [ShoppingList] {
        shoppingLists.filter { $0.status == .completed }
    }

    var archivedLists: [ShoppingList] {
        shoppingLists.filter { $0.status == .archived }
    }

    var activeMemories: [AIMemory] {
        memories.filter { $0.isActive }
    }

    func persistNow() {
        persistenceStore?.saveSnapshot(AppStoreSnapshot(store: self))
    }

    func exportSnapshotData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(AppStoreSnapshot(store: self))
    }

    func writeExportFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "PrisPilot-Export-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try exportSnapshotData().write(to: url, options: [.atomic])
        return url
    }

    func deleteAllLocalData() {
        isRestoringSnapshot = true
        settings = .defaultSettings
        chains = []
        branches = []
        products = []
        priceObservations = []
        communityContributions = []
        shoppingLists = []
        recipes = []
        memories = []
        household = nil
        invitations = []
        chatSessions = [
            ChatSession(title: "New Chat", messages: [Self.welcomeChatMessage()])
        ]
        selectedChatSessionID = chatSessions.first?.id
        onboardingAnswers = [:]
        aiOnboardingProgressBySessionID = [:]
        seedInitialData()
        if selectedChatSessionID == nil {
            selectedChatSessionID = chatSessions.first?.id
        }
        isRestoringSnapshot = false
        persistNow()
    }

    func canUndoActivityTag(_ tag: ActivityTag) -> Bool {
        guard !tag.affectedRecordIDs.isEmpty else { return false }
        switch tag.actionType {
        case .createPriceObservation, .addShoppingListItem, .createShoppingList,
             .createStore, .createMemory, .createProduct, .createRecipe,
             .addRecipeToShoppingList:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func undoActivityTag(_ tag: ActivityTag) -> Bool {
        guard canUndoActivityTag(tag) else { return false }
        let ids = Set(tag.affectedRecordIDs)
        var didUndo = false

        switch tag.actionType {
        case .createPriceObservation:
            let before = priceObservations.count
            priceObservations.removeAll { ids.contains($0.id) }
            communityContributions.removeAll { ids.contains($0.sourceObservationID) }
            didUndo = priceObservations.count != before

        case .addShoppingListItem, .addRecipeToShoppingList:
            for listIndex in shoppingLists.indices {
                let before = shoppingLists[listIndex].items.count
                shoppingLists[listIndex].items.removeAll { ids.contains($0.id) }
                didUndo = didUndo || shoppingLists[listIndex].items.count != before
            }

        case .createShoppingList:
            let before = shoppingLists.count
            shoppingLists.removeAll { ids.contains($0.id) }
            didUndo = shoppingLists.count != before

        case .createStore:
            let removableBranchIDs = ids.filter { branchID in
                !priceObservations.contains { $0.storeBranchID == branchID }
            }
            let before = branches.count
            branches.removeAll { removableBranchIDs.contains($0.id) }
            didUndo = branches.count != before

        case .createMemory:
            let before = memories.count
            memories.removeAll { ids.contains($0.id) }
            didUndo = memories.count != before

        case .createProduct:
            let removableProductIDs = ids.filter { productID in
                !priceObservations.contains { $0.productID == productID }
            }
            let before = products.count
            products.removeAll { removableProductIDs.contains($0.id) }
            didUndo = products.count != before

        case .createRecipe:
            let before = recipes.count
            recipes.removeAll { ids.contains($0.id) }
            didUndo = recipes.count != before

        default:
            break
        }

        if didUndo {
            persistNow()
        }
        return didUndo
    }

    private func persistIfReady() {
        guard !isRestoringSnapshot else { return }
        persistNow()
    }

    private func restore(from snapshot: AppStoreSnapshot) {
        isRestoringSnapshot = true
        settings = snapshot.settings
        chains = snapshot.chains
        branches = snapshot.branches
        products = snapshot.products
        priceObservations = snapshot.priceObservations
        communityContributions = snapshot.communityContributions
        shoppingLists = snapshot.shoppingLists
        recipes = snapshot.recipes
        memories = snapshot.memories
        household = snapshot.household
        invitations = snapshot.invitations
        chatSessions = snapshot.chatSessions.map(\.chatSession)
        selectedChatSessionID = snapshot.selectedChatSessionID
        onboardingAnswers = snapshot.onboardingAnswers
        aiOnboardingProgressBySessionID = [:]
        if let sessionID = existingIncompleteAIOnboardingSessionID {
            aiOnboardingProgressBySessionID[sessionID] = inferredAIOnboardingProgress()
        }
        isRestoringSnapshot = false
    }

    var selectedChatSession: ChatSession? {
        guard let selectedChatSessionID else { return nil }
        return chatSessions.first { $0.id == selectedChatSessionID }
    }

    // MARK: - Chat

    @discardableResult
    func ensureDefaultChatSession() -> UUID {
        if let selectedChatSessionID,
           chatSessions.contains(where: { $0.id == selectedChatSessionID }) {
            return selectedChatSessionID
        }

        if let first = chatSessions.first {
            selectedChatSessionID = first.id
            return first.id
        }

        return createChatSession(messages: [Self.welcomeChatMessage()])
    }

    @discardableResult
    func createChatSession(
        title: String = "New Chat",
        messages: [ChatMessage] = [AppStore.welcomeChatMessage()],
        purpose: ChatSessionPurpose = .general
    ) -> UUID {
        let session = ChatSession(title: title, messages: messages, purpose: purpose)
        chatSessions.insert(session, at: 0)
        selectedChatSessionID = session.id
        return session.id
    }

    @discardableResult
    func resumeAIOnboardingChatIfAvailable() -> Bool {
        guard let sessionID = existingIncompleteAIOnboardingSessionID else { return false }
        selectedChatSessionID = sessionID
        if aiOnboardingProgressBySessionID[sessionID] == nil {
            aiOnboardingProgressBySessionID[sessionID] = inferredAIOnboardingProgress()
        }
        return true
    }

    @discardableResult
    func startOrResumeAIOnboardingChat() -> UUID {
        if resumeAIOnboardingChatIfAvailable(), let selectedChatSessionID {
            return selectedChatSessionID
        }

        onboardingAnswers = [:]
        let sessionID = createChatSession(title: "AI Setup", messages: [Self.aiOnboardingMessage()], purpose: .aiOnboarding)
        aiOnboardingProgressBySessionID[sessionID] = 0
        return sessionID
    }

    func selectChatSession(_ id: UUID) {
        guard chatSessions.contains(where: { $0.id == id }) else { return }
        selectedChatSessionID = id
    }

    func messages(for sessionID: UUID) -> [ChatMessage] {
        chatSessions.first(where: { $0.id == sessionID })?.messages ?? []
    }

    func purpose(for sessionID: UUID) -> ChatSessionPurpose {
        chatSessions.first(where: { $0.id == sessionID })?.purpose ?? .general
    }

    func isAIOnboardingActive(for sessionID: UUID) -> Bool {
        purpose(for: sessionID) == .aiOnboarding && aiOnboardingProgressBySessionID[sessionID] != nil
    }

    func appendMessage(_ message: ChatMessage, to sessionID: UUID) {
        guard let index = chatSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        chatSessions[index].messages.append(message)
        refreshChatSessionMetadata(at: index)
    }

    func replaceMessage(_ messageID: UUID, in sessionID: UUID, with content: ChatMessageContent) {
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = chatSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID })
        else { return }

        chatSessions[sessionIndex].messages[messageIndex].content = content
        refreshChatSessionMetadata(at: sessionIndex)
    }

    func deleteChatSessions(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            aiOnboardingProgressBySessionID[chatSessions[offset].id] = nil
            chatSessions.remove(at: offset)
        }
        if let selectedChatSessionID,
           !chatSessions.contains(where: { $0.id == selectedChatSessionID }) {
            self.selectedChatSessionID = chatSessions.first?.id
        }
    }

    private var existingIncompleteAIOnboardingSessionID: UUID? {
        chatSessions
            .filter { $0.purpose == .aiOnboarding && !isCompletedAIOnboardingSession($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.id
    }

    private func isCompletedAIOnboardingSession(_ session: ChatSession) -> Bool {
        session.messages.contains { message in
            if case .onboardingComplete = message.content {
                return true
            }
            return false
        }
    }

    private func inferredAIOnboardingProgress() -> Int {
        for (index, question) in OnboardingFlow.questions.enumerated() {
            if onboardingAnswers[question.id] == nil {
                return index
            }
        }
        return OnboardingFlow.questions.count
    }

    private func refreshChatSessionMetadata(at index: Int) {
        chatSessions[index].updatedAt = Date()
        guard chatSessions[index].purpose == .general else { return }
        if let firstUserMessage = chatSessions[index].messages.first(where: { $0.role == .user }),
           case .text(let text) = firstUserMessage.content {
            chatSessions[index].title = Self.chatTitle(from: text)
        }
    }

    private static func chatTitle(from text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(42))
    }

    func recordOnboardingAnswer(_ answer: String, for questionID: OnboardingQuestionID) {
        onboardingAnswers[questionID] = answer
        applyOnboardingAnswer(answer, for: questionID)
    }

    func nextAIOnboardingMessage(after answer: String, in sessionID: UUID) -> ChatMessage {
        let answeredIndex = aiOnboardingProgressBySessionID[sessionID] ?? 0
        if let question = OnboardingFlow.question(after: answeredIndex) {
            recordOnboardingAnswer(answer, for: question.id)
        }

        let nextIndex = answeredIndex + 1
        aiOnboardingProgressBySessionID[sessionID] = nextIndex

        if let nextQuestion = OnboardingFlow.question(after: nextIndex) {
            return ChatMessage(role: .assistant, content: .text(nextQuestion.prompt))
        }

        settings.onboardingCompleted = true
        aiOnboardingProgressBySessionID[sessionID] = nil
        return ChatMessage(role: .assistant, content: .onboardingComplete)
    }

    private func applyOnboardingAnswer(_ answer: String, for questionID: OnboardingQuestionID) {
        switch questionID {
        case .cheapestDefinition:
            applySettingChange(key: "cheapestDefinition", value: answer)
        case .maxStoreCount:
            applySettingChange(key: "maxStoreCount", value: answer)
        case .minimumSavings:
            applySettingChange(key: "minimumSavings", value: answer)
        default:
            break
        }
    }

    private func applySettingChange(key: String, value: String) {
        switch key {
        case "cheapestDefinition":
            if let definition = CheapestDefinition(rawValue: value) {
                settings.cheapestDefinition = definition
            }
        case "maxStoreCount":
            if let count = Int(value.filter(\.isNumber)), count > 0 {
                settings.maxSupermarketCount = count
            }
        case "minimumSavings":
            if let amount = Decimal(string: value.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")) {
                settings.minimumAdditionalStoreSavings = amount
            }
        default:
            break
        }
    }

    nonisolated private static func welcomeChatMessage() -> ChatMessage {
        let text = "Hi! I'm your PrisPilot assistant. I can help you:\n\n• Track grocery prices across stores\n• Manage shopping lists\n• Plan meals and estimate costs\n• Find the cheapest shopping options\n\nTry: \"I paid kr 39.90 for 400 g minced beef at Kiwi\""
        return ChatMessage(role: .assistant, content: .text(text))
    }

    nonisolated private static func aiOnboardingMessage() -> ChatMessage {
        let text = OnboardingFlow.questions.first?.prompt ?? "Let's set up PrisPilot."
        return ChatMessage(role: .assistant, content: .text(text))
    }

    // MARK: - AI Permissions

    func permissionMode(for area: AIPermissionArea, operation: AIPermissionOperation) -> AIPermissionMode {
        let key = AppSettings.permissionKey(area: area, operation: operation)
        return settings.aiPermissionModes[key] ?? AppSettings.defaultAIPermissionModes[key] ?? .alwaysAsk
    }

    func setPermissionMode(_ mode: AIPermissionMode, for area: AIPermissionArea, operation: AIPermissionOperation) {
        let key = AppSettings.permissionKey(area: area, operation: operation)
        settings.aiPermissionModes[key] = mode
    }

    func permissionMode(for action: ProposedAction) -> AIPermissionMode {
        let permission = permissionTarget(for: action.type)
        return permissionMode(for: permission.area, operation: permission.operation)
    }

    func resetOnboarding() {
        settings.onboardingCompleted = false
        persistNow()
    }

    func deleteMemory(_ id: UUID) {
        memories.removeAll { $0.id == id }
    }

    func updateMemory(_ id: UUID, summary: String, category: MemoryCategory, strength: ConstraintStrength, sensitivityLevel: SensitivityLevel) {
        guard let idx = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[idx].summary = summary
        memories[idx].category = category
        memories[idx].strength = strength
        memories[idx].sensitivityLevel = sensitivityLevel
    }

    private func isDuplicateMemory(summary: String, category: MemoryCategory) -> Bool {
        let newWords = Set(
            summary.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 2 }
        )
        guard !newWords.isEmpty else { return false }
        return memories.contains { existing in
            guard existing.isActive && existing.category == category else { return false }
            let existingWords = Set(
                existing.summary.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { $0.count > 2 }
            )
            guard !existingWords.isEmpty else { return false }
            let overlap = Double(newWords.intersection(existingWords).count)
            let threshold = Double(min(newWords.count, existingWords.count)) * 0.6
            return overlap >= threshold
        }
    }

    func validate(_ action: ProposedAction) -> ValidationResult {
        let mode = permissionMode(for: action)
        if mode == .notAllowed {
            let permission = permissionTarget(for: action.type)
            return .invalid(reason: "AI is not allowed to \(permission.operation.rawValue.lowercased()) \(permission.area.rawValue.lowercased()).")
        }
        if action.type.isDestructive {
            return .warning(message: "Destructive AI actions require explicit approval.")
        }
        return .valid
    }

    private func permissionTarget(for type: ProposedActionType) -> (area: AIPermissionArea, operation: AIPermissionOperation) {
        switch type {
        case .createProduct:
            return (.products, .create)
        case .updateProduct:
            return (.products, .edit)
        case .deleteProduct:
            return (.products, .delete)
        case .createPriceObservation:
            return (.prices, .create)
        case .updatePriceObservation:
            return (.prices, .edit)
        case .deletePriceObservation:
            return (.prices, .delete)
        case .createShoppingList, .addShoppingListItem, .addRecipeToShoppingList:
            return (.shoppingLists, .create)
        case .updateShoppingList, .updateShoppingListItem, .completeShoppingListItem:
            return (.shoppingLists, .edit)
        case .deleteShoppingList, .removeShoppingListItem:
            return (.shoppingLists, .delete)
        case .createRecipe:
            return (.recipes, .create)
        case .updateRecipe:
            return (.recipes, .edit)
        case .deleteRecipe:
            return (.recipes, .delete)
        case .createStore:
            return (.settings, .create)
        case .updateStore, .enableStore, .disableStore, .updateShoppingPreferences, .changeAppSetting:
            return (.settings, .edit)
        case .deleteStore:
            return (.settings, .delete)
        case .createMemory:
            return (.memory, .create)
        case .updateMemory:
            return (.memory, .edit)
        case .deleteMemory:
            return (.memory, .delete)
        case .createHousehold, .inviteHouseholdMember:
            return (.household, .create)
        case .updateHouseholdMember:
            return (.household, .edit)
        }
    }

    // MARK: - Action Execution

    @discardableResult
    func execute(_ action: ProposedAction) throws -> [UUID] {
        guard validate(action).isValid else { throw AIServiceError.permissionDenied }
        defer { persistNow() }
        switch action.payload {
        case .createPriceObservation(let productName, let storeBranchName, let price, let quantity, let unit, let isPromotion, let date):
            let product = findOrCreateProduct(name: productName)
            let branch = findOrCreateBranch(name: storeBranchName)
            let observation = PriceObservation(
                productID: product.id,
                productName: productName,
                storeBranchID: branch.id,
                storeBranchName: storeBranchName,
                price: price,
                quantity: quantity,
                unit: unit,
                isPromotion: isPromotion,
                observedDate: date,
                source: .chat
            )
            priceObservations.append(observation)
            queueCommunityContributionIfNeeded(for: observation)
            return [observation.id]

        case .addShoppingListItem(let listName, let productName, let quantity, let notes):
            let list = findOrCreateShoppingList(name: listName)
            guard let idx = shoppingLists.firstIndex(where: { $0.id == list.id }) else { return [] }
            var item = ShoppingListItem(listID: list.id, productName: productName, requestedQuantity: quantity)
            item.notes = notes
            shoppingLists[idx].items.append(item)
            return [item.id]

        case .createShoppingList(let name):
            let list = ShoppingList(name: name)
            shoppingLists.append(list)
            return [list.id]

        case .updateShoppingList(let existingListName, let newName, let plannedDate):
            guard let idx = shoppingListIndex(matching: existingListName) else { return [] }
            if let newName, !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shoppingLists[idx].name = newName
            }
            if let plannedDate {
                shoppingLists[idx].plannedDate = plannedDate
            }
            return [shoppingLists[idx].id]

        case .deleteShoppingList(let listName):
            guard let idx = shoppingListIndex(matching: listName) else { return [] }
            let id = shoppingLists[idx].id
            shoppingLists.remove(at: idx)
            return [id]

        case .updateShoppingListItem(let listName, let productName, let newQuantity, let newNotes):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return [] }
            if let newQuantity, !newQuantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shoppingLists[listIdx].items[itemIdx].requestedQuantity = newQuantity
            }
            if let newNotes {
                shoppingLists[listIdx].items[itemIdx].notes = newNotes
            }
            return [shoppingLists[listIdx].items[itemIdx].id]

        case .completeShoppingListItem(let listName, let productName, let isCompleted):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return [] }
            shoppingLists[listIdx].items[itemIdx].isCompleted = isCompleted
            return [shoppingLists[listIdx].items[itemIdx].id]

        case .removeShoppingListItem(let listName, let productName):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return [] }
            let id = shoppingLists[listIdx].items[itemIdx].id
            shoppingLists[listIdx].items.remove(at: itemIdx)
            return [id]

        case .addRecipeToShoppingList(let recipeName, let listName):
            let trimmedRecipeName = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let recipe = recipes.first(where: { $0.title.lowercased() == trimmedRecipeName.lowercased() }) else { return [] }
            let list = findOrCreateShoppingList(name: listName)
            guard let listIdx = shoppingLists.firstIndex(where: { $0.id == list.id }) else { return [] }
            var addedIDs: [UUID] = []
            for ingredient in recipe.ingredients {
                let item = ShoppingListItem(
                    listID: list.id,
                    productName: ingredient.productName,
                    requestedQuantity: "\(ingredient.quantity.formatted()) \(ingredient.unit.rawValue)"
                )
                shoppingLists[listIdx].items.append(item)
                addedIDs.append(item.id)
            }
            return addedIDs

        case .createStore(let chainName, let branchName, let address, let isEnabled):
            let branch = createStoreBranch(chainName: chainName, branchName: branchName, address: address, isEnabled: isEnabled)
            return [branch.id]

        case .updateStore(let existingStoreName, let chainName, let branchName, let address, let isEnabled):
            guard let branch = updateStoreBranch(matching: existingStoreName, chainName: chainName, branchName: branchName, address: address, isEnabled: isEnabled) else { return [] }
            return [branch.id]

        case .deleteStore(let storeName):
            guard let deletedID = deleteStoreBranch(matching: storeName) else { return [] }
            return [deletedID]

        case .setStoreEnabled(let storeName, let isEnabled):
            guard let branch = setStoreBranchEnabled(matching: storeName, isEnabled: isEnabled) else { return [] }
            return [branch.id]

        case .createMemory(let summary, let category, let strength, let sensitivityLevel):
            guard !isDuplicateMemory(summary: summary, category: category) else { return [] }
            let memory = AIMemory(
                summary: summary,
                category: category,
                strength: strength,
                sensitivityLevel: sensitivityLevel
            )
            memories.append(memory)
            return [memory.id]

        case .createProduct(let name, let category, let unit):
            let product = Product(name: name, category: category, defaultUnit: unit)
            products.append(product)
            return [product.id]

        case .createRecipe(let title, let servings):
            let recipe = Recipe(title: title, servings: servings)
            recipes.append(recipe)
            return [recipe.id]

        case .changeAppSetting(let key, let value):
            applySettingChange(key: key, value: value)
            return []

        case .generic:
            return []
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func findOrCreateProduct(name: String) -> Product {
        if let existing = products.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }
        let product = Product(name: name)
        products.append(product)
        return product
    }

    @discardableResult
    private func findOrCreateBranch(name: String) -> StoreBranch {
        if let existing = findStoreBranch(matching: name) {
            return existing
        }

        let matchingChain = chains.first { chain in name.localizedCaseInsensitiveContains(chain.name) }
        let branchName: String
        if let matchingChain {
            branchName = name.replacingOccurrences(of: matchingChain.name, with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            branchName = name
        }

        return createStoreBranch(
            chainName: matchingChain?.name ?? "Unknown",
            branchName: branchName.isEmpty ? name : branchName,
            address: nil,
            isEnabled: true
        )
    }

    @discardableResult
    func createStoreBranch(chainName: String, branchName: String, address: String? = nil, distanceFromHomeKm: Double? = nil, latitude: Double? = nil, longitude: Double? = nil, isEnabled: Bool = true) -> StoreBranch {
        let trimmedChainName = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let chain = findOrCreateChain(name: trimmedChainName.isEmpty ? "Unknown" : trimmedChainName)
        let branch = StoreBranch(
            chainID: chain.id,
            chainName: chain.name,
            name: trimmedBranchName.isEmpty ? chain.name : trimmedBranchName,
            address: address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            distanceFromHomeKm: distanceFromHomeKm,
            latitude: latitude,
            longitude: longitude,
            isEnabled: isEnabled
        )
        branches.append(branch)
        persistNow()
        return branch
    }

    @discardableResult
    func updateStoreBranch(matching name: String, chainName: String?, branchName: String?, address: String?, distanceFromHomeKm: Double? = nil, latitude: Double? = nil, longitude: Double? = nil, isEnabled: Bool?) -> StoreBranch? {
        guard let index = branches.firstIndex(where: { branchMatches($0, name: name) }) else { return nil }
        let current = branches[index]
        let resolvedChain: SupermarketChain
        if let chainName, !chainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedChain = findOrCreateChain(name: chainName)
        } else {
            resolvedChain = findOrCreateChain(name: current.chainName)
        }

        let updated = StoreBranch(
            id: current.id,
            chainID: resolvedChain.id,
            chainName: resolvedChain.name,
            name: branchName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? current.name,
            address: address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? current.address,
            distanceFromHomeKm: distanceFromHomeKm ?? current.distanceFromHomeKm,
            latitude: latitude ?? current.latitude,
            longitude: longitude ?? current.longitude,
            isEnabled: isEnabled ?? current.isEnabled
        )
        branches[index] = updated
        persistNow()
        return updated
    }

    @discardableResult
    func deleteStoreBranch(matching name: String) -> UUID? {
        guard let index = branches.firstIndex(where: { branchMatches($0, name: name) }) else { return nil }
        let id = branches[index].id
        branches.remove(at: index)
        persistNow()
        return id
    }

    @discardableResult
    func setStoreBranchEnabled(matching name: String, isEnabled: Bool) -> StoreBranch? {
        guard let index = branches.firstIndex(where: { branchMatches($0, name: name) }) else { return nil }
        branches[index].isEnabled = isEnabled
        persistNow()
        return branches[index]
    }

    @discardableResult
    func findOrCreateChain(name: String) -> SupermarketChain {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = chains.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let chain = SupermarketChain(name: trimmed.isEmpty ? "Unknown" : trimmed)
        chains.append(chain)
        return chain
    }

    func deleteChain(_ chainID: UUID) {
        chains.removeAll { $0.id == chainID }
        branches.removeAll { $0.chainID == chainID }
        persistNow()
    }

    // MARK: - Needs Prices

    /// A row in the Prices tab's "Needs Prices" queue — one product name
    /// missing a usable price, with every place that's asking for it.
    struct NeedsPriceEntry: Identifiable {
        var id: String { productName.lowercased() }
        var productName: String
        var sources: [String]
    }

    /// Union of (a) pending items on active/planned shopping lists with no
    /// `estimatedPrice`, and (b) recipe ingredients with no usable price
    /// match — merged by product name so a product needed in three places
    /// shows once, with all three sources listed.
    func needsPriceEntries() -> [NeedsPriceEntry] {
        var bySource: [String: (productName: String, sources: Set<String>)] = [:]

        for list in activeLists + plannedLists {
            for item in list.items where !item.isCompleted && item.estimatedPrice == nil {
                let key = item.productName.lowercased()
                bySource[key, default: (item.productName, [])].sources.insert(list.name)
            }
        }

        let usableObservations = priceObservations.filter { !$0.isStale && !$0.isPromoExpired }
        for recipe in recipes {
            for ingredient in recipe.ingredients {
                let hasMatch = usableObservations.contains { $0.productName.looselyMatchesProductName(ingredient.productName) }
                guard !hasMatch else { continue }
                let key = ingredient.productName.lowercased()
                bySource[key, default: (ingredient.productName, [])].sources.insert("\(recipe.title) (recipe)")
            }
        }

        return bySource.values
            .map { NeedsPriceEntry(productName: $0.productName, sources: $0.sources.sorted()) }
            .sorted { $0.productName < $1.productName }
    }

    // MARK: - Community Pricing

    func queueCommunityContributionIfNeeded(for observation: PriceObservation) {
        guard settings.participatesInCommunityPricing,
              observation.source != .community,
              !communityContributions.contains(where: { $0.sourceObservationID == observation.id }) else { return }

        let contribution = CommunityContribution(
            sourceObservation: observation,
            anonymousContributorHash: settings.anonymousCommunityContributorID
        )
        communityContributions.append(contribution)
    }

    func flagCommunityPriceObservation(_ observationID: UUID) {
        guard let observation = priceObservations.first(where: { $0.id == observationID }) else { return }
        if let index = communityContributions.firstIndex(where: { $0.sourceObservationID == observationID }) {
            communityContributions[index].isFlagged = true
        } else {
            let contribution = CommunityContribution(
                sourceObservation: observation,
                anonymousContributorHash: settings.anonymousCommunityContributorID
            )
            communityContributions.append(contribution)
            communityContributions[communityContributions.count - 1].isFlagged = true
        }
        persistNow()
    }

    func communityConfidence(for observation: PriceObservation) -> PriceConfidence {
        let matches = priceObservations.filter {
            $0.source == .community &&
            $0.productID == observation.productID &&
            $0.storeBranchID == observation.storeBranchID &&
            !$0.isStale &&
            !$0.isPromoExpired
        }

        guard !matches.isEmpty else { return .unconfirmed }
        if isOutlier(observation, comparedWith: matches) { return .low }
        if matches.count >= 3 { return .high }
        if matches.count >= 2 { return .medium }
        return .unconfirmed
    }

    func isOutlier(_ observation: PriceObservation, comparedWith observations: [PriceObservation]? = nil) -> Bool {
        let comparisonSet = observations ?? priceObservations.filter {
            $0.productID == observation.productID &&
            $0.storeBranchID == observation.storeBranchID &&
            $0.id != observation.id &&
            !$0.isStale &&
            !$0.isPromoExpired
        }
        guard comparisonSet.count >= 2 else { return false }

        let prices = comparisonSet.map { NSDecimalNumber(decimal: $0.price).doubleValue }.sorted()
        let median = prices[prices.count / 2]
        guard median > 0 else { return false }
        let value = NSDecimalNumber(decimal: observation.price).doubleValue
        return value > median * 1.5 || value < median * 0.5
    }

    // MARK: - Shopping List Status

    /// Moves a planned list into Active — the "Start Shopping" action on a
    /// planned list's context menu.
    func activateList(_ listID: UUID) {
        guard let idx = shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        shoppingLists[idx].status = .active
        persistNow()
    }

    func completeShoppingList(_ listID: UUID) {
        guard let idx = shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        shoppingLists[idx].status = .completed
        shoppingLists[idx].completedAt = Date()
        persistNow()
    }

    func archiveShoppingList(_ listID: UUID) {
        guard let idx = shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        shoppingLists[idx].status = .archived
        shoppingLists[idx].archivedAt = Date()
        persistNow()
    }

    /// Reopens a completed or archived list as active, clearing the
    /// timestamps that marked it done. Used for "reopen as template"-style
    /// flows in the Shopping tab.
    func reopenList(_ listID: UUID) {
        guard let idx = shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        shoppingLists[idx].status = .active
        shoppingLists[idx].completedAt = nil
        shoppingLists[idx].archivedAt = nil
        persistNow()
    }

    // MARK: - Shopping Optimization

    struct OptimizationResult {
        var selectedStores: [String]
        var estimatedTotal: Decimal
        var savings: Decimal
        var explanation: String
        var assignedCount: Int
        var unassignedCount: Int
    }

    /// Runs the trip-plan optimizer for a shopping list and writes store assignments +
    /// estimated prices back to each pending item. Returns a summary of the result.
    @discardableResult
    func optimizeShoppingList(_ listID: UUID, maxStoresOverride: Int? = nil) -> OptimizationResult? {
        guard let idx = shoppingLists.firstIndex(where: { $0.id == listID }) else { return nil }
        let pendingItems = shoppingLists[idx].items.filter { !$0.isCompleted }
        guard !pendingItems.isEmpty, !enabledBranches.isEmpty else { return nil }

        // Step 1: build per-store estimates
        struct StoreEstimate {
            let branch: StoreBranch
            var total: Decimal
            var matched: Int
        }
        var estimates: [StoreEstimate] = enabledBranches.compactMap { branch in
            var total: Decimal = 0
            var matched = 0
            for item in pendingItems {
                if let obs = bestObservation(productName: item.productName, branchID: branch.id) {
                    total += obs.price
                    matched += 1
                }
            }
            return matched > 0 ? StoreEstimate(branch: branch, total: total, matched: matched) : nil
        }

        guard !estimates.isEmpty else { return nil }

        // Step 2: pick baseline (most matched, then cheapest)
        estimates.sort { lhs, rhs in
            lhs.matched != rhs.matched ? lhs.matched > rhs.matched : lhs.total < rhs.total
        }
        let baseline = estimates[0]

        // Step 3: build initial assignments from baseline
        struct ItemAssignment {
            var itemID: UUID
            var productName: String
            var storeName: String
            var price: Decimal
            var observationID: UUID
        }
        var assignments: [ItemAssignment] = pendingItems.compactMap { item in
            guard let obs = bestObservation(productName: item.productName, branchID: baseline.branch.id) else { return nil }
            return ItemAssignment(itemID: item.id, productName: item.productName, storeName: baseline.branch.displayName, price: obs.price, observationID: obs.id)
        }

        var selectedBranches: [StoreBranch] = [baseline.branch]
        var currentTotal = assignments.reduce(Decimal.zero) { $0 + $1.price }

        // Step 4: greedily add stores that clear the savings threshold
        let candidates = enabledBranches
            .filter { $0.id != baseline.branch.id }
            .compactMap { branch -> (branch: StoreBranch, newAssignments: [ItemAssignment], savings: Decimal)? in
                var updated = assignments
                var savings = Decimal.zero
                for i in updated.indices {
                    if let cheaper = bestObservation(productName: updated[i].productName, branchID: branch.id),
                       cheaper.price < updated[i].price {
                        savings += updated[i].price - cheaper.price
                        updated[i] = ItemAssignment(itemID: updated[i].itemID, productName: updated[i].productName, storeName: branch.displayName, price: cheaper.price, observationID: cheaper.id)
                    }
                }
                return savings > 0 ? (branch, updated, savings) : nil
            }
            .sorted { $0.savings > $1.savings }

        let maxStores = maxStoresOverride ?? settings.maxSupermarketCount
        for candidate in candidates {
            guard selectedBranches.count < maxStores else { break }
            if candidate.savings >= settings.minimumAdditionalStoreSavings {
                selectedBranches.append(candidate.branch)
                assignments = candidate.newAssignments
                currentTotal -= candidate.savings
            }
        }

        // Step 5: write assignments back to items
        let assignmentMap = Dictionary(uniqueKeysWithValues: assignments.map { ($0.itemID, $0) })
        for itemIdx in shoppingLists[idx].items.indices {
            let itemID = shoppingLists[idx].items[itemIdx].id
            if shoppingLists[idx].items[itemIdx].isCompleted { continue }
            if let a = assignmentMap[itemID] {
                shoppingLists[idx].items[itemIdx].assignedStoreBranch = a.storeName
                shoppingLists[idx].items[itemIdx].estimatedPrice = a.price
                shoppingLists[idx].items[itemIdx].selectedPriceObservationID = a.observationID
            } else {
                shoppingLists[idx].items[itemIdx].assignedStoreBranch = nil
                shoppingLists[idx].items[itemIdx].estimatedPrice = nil
                shoppingLists[idx].items[itemIdx].selectedPriceObservationID = nil
            }
        }

        let estimatedTotal = assignments.reduce(Decimal.zero) { $0 + $1.price }
        shoppingLists[idx].estimatedTotal = estimatedTotal

        let savings = baseline.total - currentTotal
        let storeNames = selectedBranches.map(\.displayName)
        let unassigned = pendingItems.count - assignments.count

        shoppingLists[idx].optimizationSnapshot = OptimizationSnapshot(
            chosenStores: storeNames,
            estimatedOneStoreTotal: baseline.total,
            optimizedTotal: estimatedTotal,
            savings: savings,
            unpricedItemCount: unassigned,
            optimizationDate: Date()
        )

        persistNow()

        let explanation: String
        if selectedBranches.count == 1 {
            explanation = "Best one-store option. \(unassigned > 0 ? "\(unassigned) item\(unassigned == 1 ? "" : "s") have no price data." : "")"
        } else {
            let saves = NSDecimalNumber(decimal: savings).stringValue
            explanation = "\(storeNames.joined(separator: " + ")) saves kr \(saves) vs \(baseline.branch.displayName) alone.\(unassigned > 0 ? " \(unassigned) item\(unassigned == 1 ? "" : "s") have no price data." : "")"
        }

        return OptimizationResult(
            selectedStores: storeNames,
            estimatedTotal: estimatedTotal,
            savings: savings,
            explanation: explanation,
            assignedCount: assignments.count,
            unassignedCount: unassigned
        )
    }

    // MARK: - Manual Shopping List Item Reassignment

    /// Manually reassigns a pending item to a specific store, overriding
    /// whatever the optimizer chose — looks up the best known price at that
    /// store the same way the optimizer does; if none exists, the item is
    /// still moved to the store, just with no price.
    func moveItem(_ itemID: UUID, in listID: UUID, toBranchID branchID: UUID) {
        guard let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
              let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == itemID }),
              let branch = branches.first(where: { $0.id == branchID }) else { return }

        let productName = shoppingLists[listIdx].items[itemIdx].productName
        if let obs = bestObservation(productName: productName, branchID: branchID) {
            shoppingLists[listIdx].items[itemIdx].estimatedPrice = obs.price
            shoppingLists[listIdx].items[itemIdx].selectedPriceObservationID = obs.id
        } else {
            shoppingLists[listIdx].items[itemIdx].estimatedPrice = nil
            shoppingLists[listIdx].items[itemIdx].selectedPriceObservationID = nil
        }
        shoppingLists[listIdx].items[itemIdx].assignedStoreBranch = branch.displayName
        persistNow()
    }

    /// Assigns an item's price directly from a known `PriceObservation` —
    /// used by the "use this community price" action, where the exact
    /// observation is already known rather than "best at this store".
    func assignPriceObservation(_ observationID: UUID, toItem itemID: UUID, in listID: UUID) {
        guard let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
              let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == itemID }),
              let obs = priceObservations.first(where: { $0.id == observationID }) else { return }

        shoppingLists[listIdx].items[itemIdx].assignedStoreBranch = obs.storeBranchName
        shoppingLists[listIdx].items[itemIdx].estimatedPrice = obs.price
        shoppingLists[listIdx].items[itemIdx].selectedPriceObservationID = obs.id
        persistNow()
    }

    /// Records a substitute idea for an item without swapping to it yet.
    func addSubstituteCandidate(_ itemID: UUID, in listID: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
              let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == itemID }) else { return }

        var candidates = shoppingLists[listIdx].items[itemIdx].substituteCandidateNames ?? []
        guard !candidates.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        candidates.append(trimmed)
        shoppingLists[listIdx].items[itemIdx].substituteCandidateNames = candidates
        persistNow()
    }

    /// Swaps an item's product for one of its recorded substitute
    /// candidates (or any typed replacement). The old name is kept as a
    /// candidate so the swap is reversible. Clears price/store assignment —
    /// the substitute needs its own pricing.
    func useSubstitute(_ itemID: UUID, in listID: UUID, newProductName: String) {
        let trimmed = newProductName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
              let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == itemID }) else { return }

        let oldName = shoppingLists[listIdx].items[itemIdx].productName
        var candidates = shoppingLists[listIdx].items[itemIdx].substituteCandidateNames ?? []
        candidates.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        if !oldName.isEmpty && !candidates.contains(where: { $0.caseInsensitiveCompare(oldName) == .orderedSame }) {
            candidates.append(oldName)
        }

        shoppingLists[listIdx].items[itemIdx].productName = trimmed
        shoppingLists[listIdx].items[itemIdx].productID = nil
        shoppingLists[listIdx].items[itemIdx].substituteCandidateNames = candidates
        shoppingLists[listIdx].items[itemIdx].estimatedPrice = nil
        shoppingLists[listIdx].items[itemIdx].selectedPriceObservationID = nil
        shoppingLists[listIdx].items[itemIdx].assignedStoreBranch = nil
        persistNow()
    }

    /// Reverses `toggle`'s completion path: un-completes an item and clears
    /// the actual price captured for it, for the completed section's
    /// explicit Undo action.
    func undoCompleteItem(_ itemID: UUID, in listID: UUID) {
        guard let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
              let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == itemID }) else { return }
        shoppingLists[listIdx].items[itemIdx].isCompleted = false
        shoppingLists[listIdx].items[itemIdx].actualPrice = nil
        persistNow()
    }

    private func bestObservation(productName: String, branchID: UUID) -> PriceObservation? {
        priceObservations
            .filter {
                $0.storeBranchID == branchID &&
                $0.productName.lowercased() == productName.lowercased() &&
                !$0.isPromoExpired &&
                !($0.source == .community && isOutlier($0))
            }
            .sorted {
                if $0.freshnessAdjustedConfidence.rank != $1.freshnessAdjustedConfidence.rank {
                    return $0.freshnessAdjustedConfidence.rank > $1.freshnessAdjustedConfidence.rank
                }
                return $0.observedDate > $1.observedDate
            }
            .first
    }

    // MARK: - Household

    @discardableResult
    func createHousehold(name: String, owner: AuthUser) -> Household {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = Household(
            name: trimmed.isEmpty ? "My Household" : trimmed,
            ownerUserID: owner.id,
            ownerDisplayName: owner.displayName ?? owner.email
        )
        household = created
        invitations = []
        persistNow()
        return created
    }

    @discardableResult
    func createHouseholdInvitation(inviteeEmail: String?, inviterUserID: String) -> Invitation? {
        guard let household else { return nil }
        let trimmedEmail = inviteeEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let invitation = Invitation(
            householdID: household.id,
            inviterUserID: inviterUserID,
            inviteeEmail: trimmedEmail
        )
        invitations.append(invitation)
        persistNow()
        return invitation
    }

    @discardableResult
    func acceptHouseholdInvitation(shareCode: String, user: AuthUser) -> Bool {
        let normalizedCode = shareCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let index = invitations.firstIndex(where: { $0.shareCode.uppercased() == normalizedCode }) else { return false }

        if invitations[index].isExpired {
            invitations[index].status = .expired
            persistNow()
            return false
        }

        guard var currentHousehold = household,
              currentHousehold.id == invitations[index].householdID else { return false }

        if !currentHousehold.members.contains(where: { $0.userID == user.id }) {
            currentHousehold.members.append(HouseholdMember(userID: user.id, displayName: user.displayName ?? user.email, role: .member))
        }
        household = currentHousehold
        invitations[index].status = .accepted
        persistNow()
        return true
    }

    func leaveHousehold(userID: String) {
        guard var currentHousehold = household else { return }
        if currentHousehold.ownerUserID == userID {
            disbandHousehold()
            return
        }
        currentHousehold.members.removeAll { $0.userID == userID }
        household = currentHousehold
        persistNow()
    }

    func disbandHousehold() {
        household = nil
        invitations = []
        persistNow()
    }

    private func findStoreBranch(matching name: String) -> StoreBranch? {
        branches.first { branchMatches($0, name: name) }
    }

    private func branchMatches(_ branch: StoreBranch, name: String) -> Bool {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return branch.displayName.lowercased() == target ||
            branch.name.lowercased() == target ||
            "\(branch.chainName) \(branch.name)".lowercased().contains(target)
    }

    @discardableResult
    private func findOrCreateShoppingList(name: String) -> ShoppingList {
        if let existing = shoppingLists.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }
        let list = ShoppingList(name: name)
        shoppingLists.append(list)
        return list
    }

    /// Case-insensitive exact-name lookup for AI actions that must target an
    /// *existing* list (update/delete/item edits) — unlike
    /// `findOrCreateShoppingList`, this never creates one, since "update a
    /// list that doesn't exist" should just be a no-op, not a surprise create.
    private func shoppingListIndex(matching name: String) -> Int? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return shoppingLists.firstIndex { $0.name.lowercased() == target }
    }

    private func shoppingListItemIndex(in listIdx: Int, matchingProduct productName: String) -> Int? {
        let target = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return shoppingLists[listIdx].items.firstIndex { $0.productName.lowercased() == target }
    }

    // MARK: - Seed Data

    private func seedInitialData() {
        let kiwi = SupermarketChain(name: "Kiwi")
        let rema = SupermarketChain(name: "Rema 1000")
        let meny = SupermarketChain(name: "Meny")
        let spar = SupermarketChain(name: "Spar")
        let coop = SupermarketChain(name: "Coop Extra")

        chains = [kiwi, rema, meny, spar, coop]

        branches = []

        shoppingLists = [
            ShoppingList(name: "Weekly Shop")
        ]
    }
}
