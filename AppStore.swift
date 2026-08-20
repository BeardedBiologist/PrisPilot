import Foundation
import Observation

@Observable
class AppStore {
    // Settings
    var settings: AppSettings = .defaultSettings

    // Stores
    var chains: [SupermarketChain] = []
    var branches: [StoreBranch] = []

    // Products
    var products: [Product] = []

    // Prices
    var priceObservations: [PriceObservation] = []

    // Shopping
    var shoppingLists: [ShoppingList] = []

    // Recipes
    var recipes: [Recipe] = []

    // AI Memory
    var memories: [AIMemory] = []

    // Chat
    var chatSessions: [ChatSession] = []
    var selectedChatSessionID: UUID?

    static let shared = AppStore()

    init() {
        seedInitialData()
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
    func createChatSession(title: String = "New Chat", messages: [ChatMessage] = [AppStore.welcomeChatMessage()]) -> UUID {
        let session = ChatSession(title: title, messages: messages)
        chatSessions.insert(session, at: 0)
        selectedChatSessionID = session.id
        return session.id
    }

    func startAIOnboardingChat() {
        createChatSession(title: "AI Setup", messages: [Self.aiOnboardingMessage()])
    }

    func selectChatSession(_ id: UUID) {
        guard chatSessions.contains(where: { $0.id == id }) else { return }
        selectedChatSessionID = id
    }

    func messages(for sessionID: UUID) -> [ChatMessage] {
        chatSessions.first(where: { $0.id == sessionID })?.messages ?? []
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
            chatSessions.remove(at: offset)
        }
        if let selectedChatSessionID,
           !chatSessions.contains(where: { $0.id == selectedChatSessionID }) {
            self.selectedChatSessionID = chatSessions.first?.id
        }
    }

    private func refreshChatSessionMetadata(at index: Int) {
        chatSessions[index].updatedAt = Date()
        if let firstUserMessage = chatSessions[index].messages.first(where: { $0.role == .user }),
           case .text(let text) = firstUserMessage.content {
            chatSessions[index].title = Self.chatTitle(from: text)
        }
    }

    private static func chatTitle(from text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(42))
    }

    private static func welcomeChatMessage() -> ChatMessage {
        let text = "Hi! I'm your PrisPilot assistant. I can help you:\n\n• Track grocery prices across stores\n• Manage shopping lists\n• Plan meals and estimate costs\n• Find the cheapest shopping options\n\nTry: \"I paid kr 39.90 for 400 g minced beef at Kiwi\""
        return ChatMessage(role: .assistant, content: .text(text))
    }

    private static func aiOnboardingMessage() -> ChatMessage {
        let text = "Let's set up PrisPilot together. Answer these questions in one message, or one at a time:\n\n1. Which grocery stores or branches do you usually shop at?\n2. How many stores are you willing to visit for one shopping trip?\n3. Do you want the absolute cheapest basket, or the best practical trip?\n4. Are there products, brands, diets, or budgets I should remember?"
        return ChatMessage(role: .assistant, content: .text(text))
    }

    // MARK: - Action Execution

    @discardableResult
    func execute(_ action: ProposedAction) throws -> [UUID] {
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

        case .changeAppSetting:
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
        if let existing = branches.first(where: {
            $0.displayName.lowercased() == name.lowercased() || $0.name.lowercased() == name.lowercased()
        }) {
            return existing
        }
        // Find a chain match if branch name includes a chain name
        let matchingChain = chains.first { chain in name.lowercased().contains(chain.name.lowercased()) }
        let branch = StoreBranch(
            chainID: matchingChain?.id ?? UUID(),
            chainName: matchingChain?.name ?? "Unknown",
            name: name
        )
        branches.append(branch)
        return branch
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

        branches = [
            StoreBranch(chainID: kiwi.id, chainName: "Kiwi", name: "Majorstuen"),
            StoreBranch(chainID: kiwi.id, chainName: "Kiwi", name: "Grünerløkka"),
            StoreBranch(chainID: kiwi.id, chainName: "Kiwi", name: "Torshov"),
            StoreBranch(chainID: rema.id, chainName: "Rema 1000", name: "Bislett"),
            StoreBranch(chainID: rema.id, chainName: "Rema 1000", name: "Frogner"),
            StoreBranch(chainID: meny.id, chainName: "Meny", name: "Aker Brygge"),
            StoreBranch(chainID: meny.id, chainName: "Meny", name: "Bogstadveien"),
            StoreBranch(chainID: spar.id, chainName: "Spar", name: "Nydalen"),
            StoreBranch(chainID: coop.id, chainName: "Coop Extra", name: "Lørenskog"),
        ]

        shoppingLists = [
            ShoppingList(name: "Weekly Shop")
        ]
    }
}
