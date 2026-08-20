import Foundation
import Observation
import SwiftData

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

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

    // Shopping
    var shoppingLists: [ShoppingList] = [] { didSet { persistIfReady() } }

    // Recipes
    var recipes: [Recipe] = [] { didSet { persistIfReady() } }

    // AI Memory
    var memories: [AIMemory] = [] { didSet { persistIfReady() } }

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

    var activeMemories: [AIMemory] {
        memories.filter { $0.isActive }
    }

    func persistNow() {
        persistenceStore?.saveSnapshot(AppStoreSnapshot(store: self))
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
        shoppingLists = snapshot.shoppingLists
        recipes = snapshot.recipes
        memories = snapshot.memories
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

    private static func welcomeChatMessage() -> ChatMessage {
        let text = "Hi! I'm your PrisPilot assistant. I can help you:\n\n• Track grocery prices across stores\n• Manage shopping lists\n• Plan meals and estimate costs\n• Find the cheapest shopping options\n\nTry: \"I paid kr 39.90 for 400 g minced beef at Kiwi\""
        return ChatMessage(role: .assistant, content: .text(text))
    }

    private static func aiOnboardingMessage() -> ChatMessage {
        let text = OnboardingFlow.questions.first?.prompt ?? "Let's set up PrisPilot."
        return ChatMessage(role: .assistant, content: .text(text))
    }

    // MARK: - Action Execution

    @discardableResult
    func execute(_ action: ProposedAction) throws -> [UUID] {
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
    func createStoreBranch(chainName: String, branchName: String, address: String? = nil, isEnabled: Bool = true) -> StoreBranch {
        let trimmedChainName = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let chain = findOrCreateChain(name: trimmedChainName.isEmpty ? "Unknown" : trimmedChainName)
        let branch = StoreBranch(
            chainID: chain.id,
            chainName: chain.name,
            name: trimmedBranchName.isEmpty ? chain.name : trimmedBranchName,
            address: address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isEnabled: isEnabled
        )
        branches.append(branch)
        persistNow()
        return branch
    }

    @discardableResult
    func updateStoreBranch(matching name: String, chainName: String?, branchName: String?, address: String?, isEnabled: Bool?) -> StoreBranch? {
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
