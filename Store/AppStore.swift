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

    // Meal Planning
    var mealPlans: [MealPlan] = [] { didSet { persistIfReady() } }
    var matkasseBoxes: [MatkasseBox] = [] { didSet { persistIfReady() } }

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
        mealPlans = []
        matkasseBoxes = []
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
        if tag.undoSnapshot != nil { return true }
        guard !tag.affectedRecordIDs.isEmpty else { return false }
        switch tag.actionType {
        case .createPriceObservation, .addShoppingListItem, .createShoppingList,
             .createStore, .createMemory, .createProduct, .createRecipe,
             .addRecipeToShoppingList, .createMatkasseBox, .addMatkasseMeal:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func undoActivityTag(_ tag: ActivityTag) -> Bool {
        guard canUndoActivityTag(tag) else { return false }
        if let snapshot = tag.undoSnapshot {
            return applyUndoSnapshot(snapshot)
        }
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

        case .createMatkasseBox:
            let before = matkasseBoxes.count
            matkasseBoxes.removeAll { ids.contains($0.id) }
            didUndo = matkasseBoxes.count != before

        case .addMatkasseMeal:
            for boxIndex in matkasseBoxes.indices {
                let before = matkasseBoxes[boxIndex].includedMeals.count
                matkasseBoxes[boxIndex].includedMeals.removeAll { ids.contains($0.id) }
                didUndo = didUndo || matkasseBoxes[boxIndex].includedMeals.count != before
            }

        default:
            break
        }

        if didUndo {
            persistNow()
        }
        return didUndo
    }

    // MARK: - Undo Snapshot Application

    @discardableResult
    private func applyUndoSnapshot(_ snapshot: UndoSnapshot) -> Bool {
        switch snapshot {
        case .productFields(let id, let name, let category, let unit):
            guard let idx = products.firstIndex(where: { $0.id == id }) else { return false }
            products[idx].name = name
            products[idx].category = category
            products[idx].defaultUnit = unit

        case .recipeFields(let id, let title, let description, let servings):
            guard let idx = recipes.firstIndex(where: { $0.id == id }) else { return false }
            recipes[idx].title = title
            recipes[idx].description = description
            recipes[idx].servings = servings

        case .shoppingListFields(let id, let name, let plannedDate):
            guard let idx = shoppingLists.firstIndex(where: { $0.id == id }) else { return false }
            shoppingLists[idx].name = name
            shoppingLists[idx].plannedDate = plannedDate

        case .shoppingListStatusFields(let id, let status, let completedAt, let archivedAt):
            guard let idx = shoppingLists.firstIndex(where: { $0.id == id }) else { return false }
            shoppingLists[idx].status = status
            shoppingLists[idx].completedAt = completedAt
            shoppingLists[idx].archivedAt = archivedAt

        case .shoppingListItemFields(let listID, let itemID, let quantity, let notes):
            guard let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
                  let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == itemID }) else { return false }
            shoppingLists[listIdx].items[itemIdx].requestedQuantity = quantity
            shoppingLists[listIdx].items[itemIdx].notes = notes

        case .shoppingListItemState(let listID, let item):
            guard let listIdx = shoppingLists.firstIndex(where: { $0.id == listID }),
                  let itemIdx = shoppingLists[listIdx].items.firstIndex(where: { $0.id == item.id }) else { return false }
            shoppingLists[listIdx].items[itemIdx] = item

        case .priceObservationFields(let id, let price, let quantity, let unit):
            guard let idx = priceObservations.firstIndex(where: { $0.id == id }) else { return false }
            priceObservations[idx].price = price
            priceObservations[idx].quantity = quantity
            priceObservations[idx].unit = unit

        case .productMetadataFields(let id, let aliases, let barcode):
            guard let idx = products.firstIndex(where: { $0.id == id }) else { return false }
            products[idx].aliases = aliases
            products[idx].barcode = barcode

        case .storeBranchFields(let id, let chainName, let branchName, let address, let isEnabled):
            guard let idx = branches.firstIndex(where: { $0.id == id }) else { return false }
            branches[idx].chainName = chainName
            branches[idx].name = branchName
            branches[idx].address = address
            branches[idx].isEnabled = isEnabled

        case .communityContributionFlag(let id, let wasFlagged):
            guard let idx = communityContributions.firstIndex(where: { $0.id == id }) else { return false }
            communityContributions[idx].isFlagged = wasFlagged

        case .matkasseBoxFields(let id, let provider, let deliveryWeekStartDate, let numberOfMeals, let servingsPerMeal, let price, let notes):
            guard let idx = matkasseBoxes.firstIndex(where: { $0.id == id }) else { return false }
            matkasseBoxes[idx].provider = provider
            matkasseBoxes[idx].deliveryWeekStartDate = deliveryWeekStartDate
            matkasseBoxes[idx].numberOfMeals = numberOfMeals
            matkasseBoxes[idx].servingsPerMeal = servingsPerMeal
            matkasseBoxes[idx].price = price
            matkasseBoxes[idx].notes = notes

        case .deletedShoppingList(let list):
            guard !shoppingLists.contains(where: { $0.id == list.id }) else { return false }
            shoppingLists.append(list)

        case .createdShoppingList(let id):
            let before = shoppingLists.count
            shoppingLists.removeAll { $0.id == id }
            guard shoppingLists.count != before else { return false }

        case .deletedShoppingListItem(let listID, let item):
            guard let idx = shoppingLists.firstIndex(where: { $0.id == listID }),
                  !shoppingLists[idx].items.contains(where: { $0.id == item.id }) else { return false }
            shoppingLists[idx].items.append(item)

        case .deletedProduct(let product):
            guard !products.contains(where: { $0.id == product.id }) else { return false }
            products.append(product)

        case .deletedRecipe(let recipe):
            guard !recipes.contains(where: { $0.id == recipe.id }) else { return false }
            recipes.append(recipe)

        case .deletedPriceObservation(let obs):
            guard !priceObservations.contains(where: { $0.id == obs.id }) else { return false }
            priceObservations.append(obs)

        case .createdCommunityContribution(let id):
            let before = communityContributions.count
            communityContributions.removeAll { $0.id == id }
            guard communityContributions.count != before else { return false }

        case .deletedStoreBranch(let branch):
            guard !branches.contains(where: { $0.id == branch.id }) else { return false }
            branches.append(branch)

        case .deletedMatkasseBox(let box):
            guard !matkasseBoxes.contains(where: { $0.id == box.id }) else { return false }
            matkasseBoxes.append(box)

        case .deletedMatkasseMeal(let boxID, let meal):
            guard let idx = matkasseBoxes.firstIndex(where: { $0.id == boxID }),
                  !matkasseBoxes[idx].includedMeals.contains(where: { $0.id == meal.id }) else { return false }
            matkasseBoxes[idx].includedMeals.append(meal)

        case .deletedMemory(let memory):
            guard !memories.contains(where: { $0.id == memory.id }) else { return false }
            memories.append(memory)

        case .householdState(let previousHousehold, let previousInvitations):
            household = previousHousehold
            invitations = previousInvitations

        case .createdInvitation(let id):
            let before = invitations.count
            invitations.removeAll { $0.id == id }
            guard invitations.count != before else { return false }

        case .addedMealPlanSlot(let date, let mealType):
            clearMealPlanSlot(date: date, mealType: mealType)

        case .overwrittenMealPlanSlot(let slot), .clearedMealPlanSlot(let slot):
            setMealPlanSlot(date: slot.date, mealType: slot.mealType, content: slot.content, isLeftover: slot.isLeftover, notes: slot.notes)
        }
        persistNow()
        return true
    }

    // MARK: - Execution Plan

    func executePlan(_ plan: ActionExecutionPlan) -> ActionPlanResult {
        if plan.mode == .allOrNothing {
            for action in plan.actions {
                let validation = validate(action)
                if !validation.isValid {
                    let reason: String
                    switch validation {
                    case .invalid(let r): reason = r
                    case .requiresClarification(let q): reason = q
                    default: reason = "Validation failed"
                    }
                    return ActionPlanResult(outcomes: plan.actions.map { a in
                        ActionPlanResult.ActionOutcome(
                            actionID: a.id,
                            affectedRecordIDs: [],
                            undoSnapshot: nil,
                            failureReason: nil,
                            skippedReason: "Skipped: another action failed validation — \(reason)"
                        )
                    })
                }
            }
        }

        var outcomes: [ActionPlanResult.ActionOutcome] = []
        var appliedTags: [ActivityTag] = []
        for action in plan.actions {
            do {
                let result = try execute(action)
                appliedTags.append(ActivityTag(
                    id: UUID(),
                    actionType: action.type,
                    summary: action.summary,
                    timestamp: Date(),
                    affectedRecordIDs: result.affectedRecordIDs,
                    undoSnapshot: result.undoSnapshot
                ))
                outcomes.append(ActionPlanResult.ActionOutcome(
                    actionID: action.id,
                    affectedRecordIDs: result.affectedRecordIDs,
                    undoSnapshot: result.undoSnapshot,
                    failureReason: nil,
                    skippedReason: nil
                ))
            } catch let error as AIServiceError {
                rollbackIfNeeded(mode: plan.mode, appliedTags: appliedTags)
                outcomes.append(ActionPlanResult.ActionOutcome(
                    actionID: action.id,
                    affectedRecordIDs: [],
                    undoSnapshot: nil,
                    failureReason: error.localizedDescription,
                    skippedReason: nil
                ))
            } catch {
                rollbackIfNeeded(mode: plan.mode, appliedTags: appliedTags)
                outcomes.append(ActionPlanResult.ActionOutcome(
                    actionID: action.id,
                    affectedRecordIDs: [],
                    undoSnapshot: nil,
                    failureReason: error.localizedDescription,
                    skippedReason: nil
                ))
            }
        }
        return ActionPlanResult(outcomes: outcomes)
    }

    private func rollbackIfNeeded(mode: ActionExecutionPlan.DependencyMode, appliedTags: [ActivityTag]) {
        guard mode == .allOrNothing else { return }
        for tag in appliedTags.reversed() {
            _ = undoActivityTag(tag)
        }
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
        mealPlans = snapshot.mealPlans
        matkasseBoxes = snapshot.matkasseBoxes
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
        messages: [ChatMessage]? = nil,
        purpose: ChatSessionPurpose = .general
    ) -> UUID {
        let session = ChatSession(title: title, messages: messages ?? [Self.welcomeChatMessage()], purpose: purpose)
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

    func pendingProposals(for sessionID: UUID) -> [ChatPendingProposal] {
        messages(for: sessionID).compactMap { message in
            guard case .proposedActions(_, let actions, let memoryProposals) = message.content else {
                return nil
            }
            let pendingCount = actions.filter { !$0.status.isTerminal }.count + memoryProposals.count
            let failedCount = actions.filter { $0.status == .failed }.count
            guard pendingCount > 0 || failedCount > 0 else { return nil }
            let firstSummary = actions.first(where: { !$0.status.isTerminal || $0.status == .failed })?.summary
                ?? memoryProposals.first?.memory.summary
                ?? "Pending AI changes"
            return ChatPendingProposal(
                messageID: message.id,
                pendingActionCount: pendingCount,
                failedActionCount: failedCount,
                firstSummary: firstSummary
            )
        }
    }

    func pendingClarification(for sessionID: UUID) -> ChatPendingClarification? {
        chatSessions.first(where: { $0.id == sessionID })?.pendingClarification
    }

    func setPendingClarification(_ clarification: ChatPendingClarification?, for sessionID: UUID) {
        guard let index = chatSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        chatSessions[index].pendingClarification = clarification
        refreshChatSessionMetadata(at: index)
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
        case "travelCostPerKm":
            if let amount = Decimal(string: value.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")) {
                settings.travelCostPerKilometer = amount
            }
        case "fixedStoreVisitCost":
            if let amount = Decimal(string: value.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")) {
                settings.fixedStoreVisitCost = amount
            }
        case "communityPricingEnabled":
            settings.participatesInCommunityPricing = ["true", "1", "yes", "on"].contains(value.lowercased())
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
        if let semanticResult = semanticValidation(for: action) {
            return semanticResult
        }
        if action.type.isDestructive {
            return .warning(message: "Destructive AI actions require explicit approval.")
        }
        return .valid
    }

    private func semanticValidation(for action: ProposedAction) -> ValidationResult? {
        guard actionTypeMatchesPayload(action) else {
            return .invalid(reason: "AI action type does not match its payload.")
        }

        let resolver = AIEntityResolver(appStore: self)
        switch action.payload {
        case .createPriceObservation(let productName, let storeBranchName, let price, let quantity, let unit, _, let date):
            if isBlank(productName) { return .invalid(reason: "Price needs a product name.") }
            if isBlank(storeBranchName) { return .invalid(reason: "Price needs a store branch.") }
            if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: true) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            }
            if case .ambiguous(let candidates) = resolver.storeBranch(named: storeBranchName, allowCreate: true) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            }
            if dateIsTooFarInFuture(date) { return .invalid(reason: "Price date cannot be more than one day in the future.") }
            if price <= 0 { return .invalid(reason: "Price must be greater than zero.") }
            if price > Decimal(100_000) { return .invalid(reason: "Price is outside the expected grocery range.") }
            if let quantity, quantity <= 0 { return .invalid(reason: "Quantity must be greater than zero.") }
            if quantity != nil && unit == nil { return .invalid(reason: "Quantity needs a unit such as g, kg, ml, l, stk, or pk.") }

        case .updatePriceObservation(let productName, let storeBranchName, let newPrice, let newQuantity, _):
            if isBlank(productName) { return .invalid(reason: "Price update needs a product name.") }
            if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            }
            if let storeBranchName, case .ambiguous(let candidates) = resolver.storeBranch(named: storeBranchName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            }
            if newPrice == nil && newQuantity == nil { return .invalid(reason: "Price update needs a new price or quantity.") }
            if let newPrice, newPrice <= 0 { return .invalid(reason: "New price must be greater than zero.") }
            if let newPrice, newPrice > Decimal(100_000) { return .invalid(reason: "New price is outside the expected grocery range.") }
            if let newQuantity, newQuantity <= 0 { return .invalid(reason: "New quantity must be greater than zero.") }
            if mostRecentPersonalObservationIndex(productName: productName, storeBranchName: storeBranchName) == nil {
                return .invalid(reason: "No matching personal price observation was found for \(productName).")
            }

        case .deletePriceObservation(let productName, let storeBranchName),
             .confirmPriceObservation(let productName, let storeBranchName):
            if isBlank(productName) { return .invalid(reason: "Price action needs a product name.") }
            if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            }
            if let storeBranchName, case .ambiguous(let candidates) = resolver.storeBranch(named: storeBranchName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            }
            if mostRecentPersonalObservationIndex(productName: productName, storeBranchName: storeBranchName) == nil {
                return .invalid(reason: "No matching personal price observation was found.")
            }

        case .flagCommunityPrice(let productName, let storeBranchName):
            if isBlank(productName) { return .invalid(reason: "Flagging a price needs a product name.") }
            if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            }
            if let storeBranchName, case .ambiguous(let candidates) = resolver.storeBranch(named: storeBranchName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            }
            guard communityObservationExists(productName: productName, storeBranchName: storeBranchName) else {
                return .invalid(reason: "No matching community price was found.")
            }

        case .addShoppingListItem(let listName, let productName, let quantity, _):
            if isBlank(listName) { return .invalid(reason: "List item needs a shopping list name.") }
            if isBlank(productName) { return .invalid(reason: "List item needs a product name.") }
            if case .ambiguous(let candidates) = resolver.shoppingList(named: listName, allowCreate: true) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            }
            if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: true) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            }
            if isBlank(quantity) { return .invalid(reason: "List item needs a quantity.") }

        case .createShoppingList(let name):
            if isBlank(name) { return .invalid(reason: "Shopping list name cannot be empty.") }
            switch resolver.shoppingList(named: name, allowCreate: true) {
            case .resolved:
                return .warning(message: "A shopping list named \(name) already exists. Approval will use the existing list.")
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                break
            }

        case .updateShoppingList(let existingListName, let newName, _):
            switch resolver.shoppingList(named: existingListName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(existingListName) was found.")
            }
            if let newName, isBlank(newName) { return .invalid(reason: "New list name cannot be empty.") }
            if let newName,
               let existingIndex = shoppingListIndex(matching: newName),
               shoppingLists[existingIndex].name.caseInsensitiveCompare(existingListName) != .orderedSame {
                return .invalid(reason: "A shopping list named \(newName) already exists.")
            }

        case .deleteShoppingList(let listName):
            switch resolver.shoppingList(named: listName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(listName) was found.")
            }

        case .updateShoppingListItem(let listName, let productName, let newQuantity, let newNotes):
            let list: ShoppingList
            switch resolver.shoppingList(named: listName, allowCreate: false) {
            case .resolved(let resolvedList):
                list = resolvedList
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(listName) was found.")
            }
            if case .ambiguous(let candidates) = resolver.shoppingListItem(productName: productName, in: list) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "item", candidates: candidates))
            }
            if case .missing = resolver.shoppingListItem(productName: productName, in: list) { return .invalid(reason: "No item named \(productName) was found on \(listName).") }
            if let newQuantity, isBlank(newQuantity) { return .invalid(reason: "New quantity cannot be empty.") }
            if newQuantity == nil && newNotes == nil { return .invalid(reason: "Item update needs a new quantity or note.") }

        case .completeShoppingListItem(let listName, let productName, _),
             .removeShoppingListItem(let listName, let productName):
            let list: ShoppingList
            switch resolver.shoppingList(named: listName, allowCreate: false) {
            case .resolved(let resolvedList):
                list = resolvedList
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(listName) was found.")
            }
            switch resolver.shoppingListItem(productName: productName, in: list) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "item", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No item named \(productName) was found on \(listName).")
            }

        case .substituteShoppingListItem(let listName, let productName, let newProductName):
            let list: ShoppingList
            switch resolver.shoppingList(named: listName, allowCreate: false) {
            case .resolved(let resolvedList):
                list = resolvedList
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(listName) was found.")
            }
            switch resolver.shoppingListItem(productName: productName, in: list) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "item", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No item named \(productName) was found on \(listName).")
            }
            if isBlank(newProductName) { return .invalid(reason: "Substitute item needs a replacement product name.") }
            if productName.caseInsensitiveCompare(newProductName) == .orderedSame { return .invalid(reason: "Cannot substitute an item with itself.") }
            if case .ambiguous(let candidates) = resolver.product(named: newProductName, allowCreate: true) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "replacement product", candidates: candidates))
            }

        case .setShoppingListStatus(let listName, let status):
            if case .ambiguous(let candidates) = resolver.shoppingList(named: listName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            }
            if case .missing = resolver.shoppingList(named: listName, allowCreate: false) { return .invalid(reason: "No shopping list named \(listName) was found.") }
            if !["active", "completed", "done", "archived"].contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return .invalid(reason: "List status must be active, completed, or archived.")
            }

        case .optimizeShoppingList(let listName):
            let list: ShoppingList
            switch resolver.shoppingList(named: listName, allowCreate: false) {
            case .resolved(let resolvedList):
                list = resolvedList
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(listName) was found.")
            }
            if list.items.allSatisfy(\.isCompleted) { return .invalid(reason: "Shopping list has no pending items to optimize.") }
            if enabledBranches.isEmpty { return .invalid(reason: "Add or enable a store before optimizing a list.") }

        case .moveShoppingListItem(let listName, let productName, let storeBranchName):
            let list: ShoppingList
            switch resolver.shoppingList(named: listName, allowCreate: false) {
            case .resolved(let resolvedList):
                list = resolvedList
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No shopping list named \(listName) was found.")
            }
            switch resolver.shoppingListItem(productName: productName, in: list) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "item", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No item named \(productName) was found on \(listName).")
            }
            switch resolver.storeBranch(named: storeBranchName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No store branch named \(storeBranchName) was found.")
            }

        case .addRecipeToShoppingList(let recipeName, let listName):
            if isBlank(listName) { return .invalid(reason: "Adding recipe ingredients needs a shopping list name.") }
            switch resolver.recipe(named: recipeName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "recipe", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No recipe named \(recipeName) was found.")
            }
            if case .ambiguous(let candidates) = resolver.shoppingList(named: listName, allowCreate: true) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "shopping list", candidates: candidates))
            }

        case .createProduct(let name, _, _):
            if isBlank(name) { return .invalid(reason: "Product name cannot be empty.") }
            switch resolver.product(named: name, allowCreate: true) {
            case .resolved:
                return .invalid(reason: "A product named \(name) already exists.")
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            case .missing, .creatable:
                break
            }

        case .updateProduct(let existingName, let newName, _, _):
            switch resolver.product(named: existingName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No product named \(existingName) was found.")
            }
            if let newName, isBlank(newName) { return .invalid(reason: "New product name cannot be empty.") }
            if let newName,
               let existingIndex = productIndex(matching: newName),
               products[existingIndex].name.caseInsensitiveCompare(existingName) != .orderedSame {
                return .invalid(reason: "A product named \(newName) already exists.")
            }

        case .deleteProduct(let name):
            switch resolver.product(named: name, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No product named \(name) was found.")
            }

        case .mergeProducts(let sourceProductName, let targetProductName):
            if sourceProductName.caseInsensitiveCompare(targetProductName) == .orderedSame { return .invalid(reason: "Cannot merge a product into itself.") }
            switch resolver.product(named: sourceProductName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "source product", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No product named \(sourceProductName) was found.")
            }
            switch resolver.product(named: targetProductName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "target product", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No product named \(targetProductName) was found.")
            }

        case .addProductAlias(let productName, let alias):
            guard let productIndex = productIndex(matching: productName) else {
                if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: false) {
                    return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
                }
                return .invalid(reason: "No product named \(productName) was found.")
            }
            if isBlank(alias) { return .invalid(reason: "Alias cannot be empty.") }
            if products[productIndex].aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                return .invalid(reason: "\(alias) is already an alias for \(productName).")
            }

        case .removeProductAlias(let productName, let alias):
            guard let productIndex = productIndex(matching: productName) else {
                if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: false) {
                    return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
                }
                return .invalid(reason: "No product named \(productName) was found.")
            }
            if !products[productIndex].aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                return .invalid(reason: "\(alias) is not saved as an alias for \(productName).")
            }

        case .setProductBarcode(let productName, let barcode):
            if case .ambiguous(let candidates) = resolver.product(named: productName, allowCreate: false) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "product", candidates: candidates))
            }
            if productIndex(matching: productName) == nil { return .invalid(reason: "No product named \(productName) was found.") }
            if isBlank(barcode) { return .invalid(reason: "Barcode cannot be empty.") }

        case .createRecipe(let title, let servings, let ingredients):
            if isBlank(title) { return .invalid(reason: "Recipe title cannot be empty.") }
            if servings <= 0 { return .invalid(reason: "Recipe servings must be greater than zero.") }
            for ingredient in ingredients {
                if isBlank(ingredient.productName) { return .invalid(reason: "Recipe ingredients need product names.") }
                if ingredient.quantity <= 0 { return .invalid(reason: "Recipe ingredient quantities must be greater than zero.") }
            }
            switch resolver.recipe(named: title, allowCreate: true) {
            case .resolved:
                return .invalid(reason: "A recipe named \(title) already exists.")
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "recipe", candidates: candidates))
            case .missing, .creatable:
                break
            }

        case .updateRecipe(let existingTitle, let newTitle, let description, let servings):
            switch resolver.recipe(named: existingTitle, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "recipe", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No recipe named \(existingTitle) was found.")
            }
            if newTitle == nil && description == nil && servings == nil { return .invalid(reason: "Recipe update needs a new title, description, or servings value.") }
            if let newTitle, isBlank(newTitle) { return .invalid(reason: "New recipe title cannot be empty.") }
            if let newTitle,
               let existingIndex = recipeIndex(matching: newTitle),
               recipes[existingIndex].title.caseInsensitiveCompare(existingTitle) != .orderedSame {
                return .invalid(reason: "A recipe named \(newTitle) already exists.")
            }
            if let servings, servings <= 0 { return .invalid(reason: "Recipe servings must be greater than zero.") }

        case .deleteRecipe(let title):
            switch resolver.recipe(named: title, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "recipe", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No recipe named \(title) was found.")
            }

        case .setMealPlanSlot(let date, let mealType, let recipeTitle, let freeformText, let isEatingOut, _):
            if isBlank(mealType) { return .invalid(reason: "Meal plan slot needs a meal type.") }
            if dateIsTooFarInPast(date) { return .invalid(reason: "Meal plan date is too far in the past.") }
            if let recipeTitle {
                if isBlank(recipeTitle) { return .invalid(reason: "Recipe title cannot be empty.") }
                switch resolver.recipe(named: recipeTitle, allowCreate: false) {
                case .resolved:
                    break
                case .ambiguous(let candidates):
                    return .requiresClarification(question: resolver.clarificationQuestion(for: "recipe", candidates: candidates))
                case .missing, .creatable:
                    return .invalid(reason: "No recipe named \(recipeTitle) was found.")
                }
            }
            if recipeTitle == nil && !isEatingOut && isBlank(freeformText ?? "") { return .invalid(reason: "Meal plan slot needs a recipe, freeform meal, or eating-out marker.") }

        case .removeMealPlanSlot(let date, let mealType):
            if isBlank(mealType) { return .invalid(reason: "Removing a meal plan slot needs a meal type.") }
            if !mealPlanSlotExists(date: date, mealTypeRaw: mealType) { return .invalid(reason: "No planned \(mealType) was found for that date.") }

        case .buildShoppingListFromMealPlan(let requestedWeekStartDate, _):
            let resolvedWeekStart = weekStartDate(for: requestedWeekStartDate ?? Date())
            let days = (0..<7).compactMap { Calendar.mealPlanCalendar.date(byAdding: .day, value: $0, to: resolvedWeekStart) }
            let hasRecipeSlot = mealPlanSlots(on: days).contains { slot in
                if case .recipe = slot.content { return true }
                return false
            }
            if !hasRecipeSlot { return .invalid(reason: "No recipe meals were found for that week.") }

        case .createMatkasseBox(let provider, let deliveryWeek, let numberOfMeals, let servingsPerMeal, let price, _):
            if isBlank(provider) { return .invalid(reason: "Matkasse provider cannot be empty.") }
            if let deliveryWeek, dateIsTooFarInPast(deliveryWeek) { return .invalid(reason: "Matkasse delivery week is too far in the past.") }
            if let numberOfMeals, numberOfMeals <= 0 { return .invalid(reason: "Number of meals must be greater than zero.") }
            if let numberOfMeals, numberOfMeals > 21 { return .invalid(reason: "Number of meals is outside the expected range.") }
            if let servingsPerMeal, servingsPerMeal <= 0 { return .invalid(reason: "Servings per meal must be greater than zero.") }
            if let servingsPerMeal, servingsPerMeal > 12 { return .invalid(reason: "Servings per meal is outside the expected range.") }
            if let price, price <= 0 { return .invalid(reason: "Matkasse price must be greater than zero.") }
            if let price, price > Decimal(50_000) { return .invalid(reason: "Matkasse price is outside the expected range.") }

        case .updateMatkasseBox(let existingProvider, let newProvider, let deliveryWeek, let numberOfMeals, let servingsPerMeal, let price, _):
            switch resolver.matkasseBox(provider: existingProvider, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "matkasse box", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No matkasse box from \(existingProvider) was found.")
            }
            if newProvider == nil && deliveryWeek == nil && numberOfMeals == nil && servingsPerMeal == nil && price == nil { return .invalid(reason: "Matkasse update needs at least one changed value.") }
            if let newProvider, isBlank(newProvider) { return .invalid(reason: "New provider name cannot be empty.") }
            if let newProvider,
               matkasseBox(matchingProvider: newProvider) != nil,
               newProvider.caseInsensitiveCompare(existingProvider) != .orderedSame {
                return .invalid(reason: "A matkasse box from \(newProvider) already exists.")
            }
            if let deliveryWeek, dateIsTooFarInPast(deliveryWeek) { return .invalid(reason: "Matkasse delivery week is too far in the past.") }
            if let numberOfMeals, numberOfMeals <= 0 { return .invalid(reason: "Number of meals must be greater than zero.") }
            if let numberOfMeals, numberOfMeals > 21 { return .invalid(reason: "Number of meals is outside the expected range.") }
            if let servingsPerMeal, servingsPerMeal <= 0 { return .invalid(reason: "Servings per meal must be greater than zero.") }
            if let servingsPerMeal, servingsPerMeal > 12 { return .invalid(reason: "Servings per meal is outside the expected range.") }
            if let price, price <= 0 { return .invalid(reason: "Matkasse price must be greater than zero.") }
            if let price, price > Decimal(50_000) { return .invalid(reason: "Matkasse price is outside the expected range.") }

        case .deleteMatkasseBox(let provider):
            switch resolver.matkasseBox(provider: provider, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "matkasse box", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No matkasse box from \(provider) was found.")
            }

        case .addMatkasseMeal(let boxProvider, let mealTitle):
            let box: MatkasseBox
            switch resolver.matkasseBox(provider: boxProvider, allowCreate: false) {
            case .resolved(let resolvedBox):
                box = resolvedBox
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "matkasse box", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No matkasse box from \(boxProvider) was found.")
            }
            if isBlank(mealTitle) { return .invalid(reason: "Matkasse meal title cannot be empty.") }
            if box.includedMeals.contains(where: { $0.title.caseInsensitiveCompare(mealTitle.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
                return .invalid(reason: "\(mealTitle) is already in \(boxProvider).")
            }

        case .removeMatkasseMeal(let boxProvider, let mealTitle):
            let box: MatkasseBox
            switch resolver.matkasseBox(provider: boxProvider, allowCreate: false) {
            case .resolved(let resolvedBox):
                box = resolvedBox
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "matkasse box", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No matkasse box from \(boxProvider) was found.")
            }
            if !box.includedMeals.contains(where: { $0.title.caseInsensitiveCompare(mealTitle.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
                return .invalid(reason: "No meal named \(mealTitle) was found in \(boxProvider).")
            }

        case .createStore(let chainName, let branchName, _, _):
            if isBlank(chainName) { return .invalid(reason: "Store needs a chain name.") }
            if isBlank(branchName) { return .invalid(reason: "Store needs a branch name.") }
            if branches.contains(where: { $0.chainName.caseInsensitiveCompare(chainName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame && $0.name.caseInsensitiveCompare(branchName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
                return .invalid(reason: "That store branch already exists.")
            }

        case .updateStore(let existingStoreName, let chainName, let branchName, let address, let isEnabled):
            let existingBranch: StoreBranch
            switch resolver.storeBranch(named: existingStoreName, allowCreate: false) {
            case .resolved(let resolvedBranch):
                existingBranch = resolvedBranch
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No store branch named \(existingStoreName) was found.")
            }
            if chainName == nil && branchName == nil && address == nil && isEnabled == nil { return .invalid(reason: "Store update needs at least one changed value.") }
            if let chainName, isBlank(chainName) { return .invalid(reason: "Chain name cannot be empty.") }
            if let branchName, isBlank(branchName) { return .invalid(reason: "Branch name cannot be empty.") }
            let targetChain = chainName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? existingBranch.chainName
            let targetBranch = branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? existingBranch.name
            if branches.contains(where: { branch in
                branch.id != existingBranch.id &&
                branch.chainName.caseInsensitiveCompare(targetChain) == .orderedSame &&
                branch.name.caseInsensitiveCompare(targetBranch) == .orderedSame
            }) {
                return .invalid(reason: "That store branch already exists.")
            }

        case .deleteStore(let storeName):
            switch resolver.storeBranch(named: storeName, allowCreate: false) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No store branch named \(storeName) was found.")
            }

        case .setStoreEnabled(let storeName, let isEnabled):
            switch resolver.storeBranch(named: storeName, allowCreate: false) {
            case .resolved(let branch):
                if branch.isEnabled == isEnabled {
                    return .invalid(reason: "Store branch is already \(isEnabled ? "enabled" : "disabled").")
                }
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "store branch", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No store branch named \(storeName) was found.")
            }

        case .createMemory(let summary, let category, _, let sensitivityLevel):
            if isBlank(summary) { return .invalid(reason: "Memory summary cannot be empty.") }
            if case .ambiguous(let candidates) = resolver.memory(matching: summary) {
                return .requiresClarification(question: resolver.clarificationQuestion(for: "memory", candidates: candidates))
            }
            if isDuplicateMemory(summary: summary, category: category) { return .invalid(reason: "A similar memory is already saved.") }
            if sensitivityLevel != .standard { return .warning(message: "Sensitive memories require careful review before saving.") }

        case .updateMemory(let existingSummary, let newSummary, let category, let strength, let sensitivityLevel):
            let memory: AIMemory
            switch resolver.memory(matching: existingSummary) {
            case .resolved(let resolvedMemory):
                memory = resolvedMemory
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "memory", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No matching memory was found.")
            }
            if let newSummary, isBlank(newSummary) { return .invalid(reason: "Memory summary cannot be empty.") }
            if newSummary == nil && category == nil && strength == nil && sensitivityLevel == nil {
                return .invalid(reason: "Memory update needs at least one changed value.")
            }
            if let newSummary,
               newSummary.caseInsensitiveCompare(memory.summary) != .orderedSame,
               isDuplicateMemory(summary: newSummary, category: category ?? memory.category) {
                return .invalid(reason: "A similar memory is already saved.")
            }
            if let sensitivityLevel, sensitivityLevel != .standard {
                return .warning(message: "Sensitive memories require careful review before saving.")
            }

        case .deleteMemory(let summary):
            switch resolver.memory(matching: summary) {
            case .resolved:
                break
            case .ambiguous(let candidates):
                return .requiresClarification(question: resolver.clarificationQuestion(for: "memory", candidates: candidates))
            case .missing, .creatable:
                return .invalid(reason: "No matching memory was found.")
            }

        case .createHousehold(let name, _):
            if isBlank(name) { return .invalid(reason: "Household name cannot be empty.") }
            if household != nil { return .invalid(reason: "A household already exists.") }

        case .inviteHouseholdMember(let email):
            guard household != nil else { return .invalid(reason: "Create a household before inviting members.") }
            if let email, !isBlank(email), !email.contains("@") {
                return .invalid(reason: "Invite email must be a valid email address.")
            }

        case .updateHouseholdMember(let userID, let displayName, let role):
            guard let household else { return .invalid(reason: "No household exists.") }
            guard household.members.contains(where: { $0.userID == userID }) else {
                return .invalid(reason: "No matching household member was found.")
            }
            if let displayName, isBlank(displayName) { return .invalid(reason: "Member display name cannot be empty.") }
            if displayName == nil && role == nil { return .invalid(reason: "Household member update needs a changed name or role.") }

        case .changeAppSetting(let key, let value):
            return validateSettingChange(key: key, value: value)

        case .generic:
            return .invalid(reason: "Unsupported AI action.")
        }

        return nil
    }

    private func actionTypeMatchesPayload(_ action: ProposedAction) -> Bool {
        switch action.payload {
        case .createProduct:
            return action.type == .createProduct
        case .updateProduct:
            return action.type == .updateProduct
        case .deleteProduct:
            return action.type == .deleteProduct
        case .mergeProducts:
            return action.type == .mergeProducts
        case .createPriceObservation:
            return action.type == .createPriceObservation
        case .updatePriceObservation:
            return action.type == .updatePriceObservation
        case .deletePriceObservation:
            return action.type == .deletePriceObservation
        case .confirmPriceObservation:
            return action.type == .confirmPriceObservation
        case .flagCommunityPrice:
            return action.type == .flagCommunityPrice
        case .addProductAlias:
            return action.type == .addProductAlias
        case .removeProductAlias:
            return action.type == .removeProductAlias
        case .setProductBarcode:
            return action.type == .setProductBarcode
        case .addShoppingListItem:
            return action.type == .addShoppingListItem
        case .createShoppingList:
            return action.type == .createShoppingList
        case .updateShoppingList:
            return action.type == .updateShoppingList
        case .deleteShoppingList:
            return action.type == .deleteShoppingList
        case .updateShoppingListItem:
            return action.type == .updateShoppingListItem
        case .completeShoppingListItem:
            return action.type == .completeShoppingListItem
        case .removeShoppingListItem:
            return action.type == .removeShoppingListItem
        case .setShoppingListStatus:
            return action.type == .setShoppingListStatus
        case .optimizeShoppingList:
            return action.type == .optimizeShoppingList
        case .moveShoppingListItem:
            return action.type == .moveShoppingListItem
        case .substituteShoppingListItem:
            return action.type == .substituteShoppingListItem
        case .addRecipeToShoppingList:
            return action.type == .addRecipeToShoppingList
        case .createStore:
            return action.type == .createStore
        case .updateStore:
            return action.type == .updateStore
        case .deleteStore:
            return action.type == .deleteStore
        case .setStoreEnabled(_, let isEnabled):
            return isEnabled ? action.type == .enableStore : action.type == .disableStore
        case .createMemory:
            return action.type == .createMemory
        case .updateMemory:
            return action.type == .updateMemory
        case .deleteMemory:
            return action.type == .deleteMemory
        case .createHousehold:
            return action.type == .createHousehold
        case .inviteHouseholdMember:
            return action.type == .inviteHouseholdMember
        case .updateHouseholdMember:
            return action.type == .updateHouseholdMember
        case .changeAppSetting:
            return action.type == .changeAppSetting
        case .createRecipe:
            return action.type == .createRecipe
        case .updateRecipe:
            return action.type == .updateRecipe
        case .deleteRecipe:
            return action.type == .deleteRecipe
        case .setMealPlanSlot:
            return action.type == .setMealPlanSlot
        case .removeMealPlanSlot:
            return action.type == .removeMealPlanSlot
        case .buildShoppingListFromMealPlan:
            return action.type == .buildShoppingListFromMealPlan
        case .createMatkasseBox:
            return action.type == .createMatkasseBox
        case .updateMatkasseBox:
            return action.type == .updateMatkasseBox
        case .deleteMatkasseBox:
            return action.type == .deleteMatkasseBox
        case .addMatkasseMeal:
            return action.type == .addMatkasseMeal
        case .removeMatkasseMeal:
            return action.type == .removeMatkasseMeal
        case .generic:
            return true
        }
    }

    private func validateSettingChange(key: String, value: String) -> ValidationResult? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else {
            return .invalid(reason: "Setting changes need a key and value.")
        }

        switch normalizedKey {
        case "cheapestDefinition":
            if CheapestDefinition(rawValue: normalizedValue) == nil {
                return .invalid(reason: "Unknown cheapest strategy: \(normalizedValue).")
            }
        case "maxStoreCount":
            guard let count = Int(normalizedValue), (1...5).contains(count) else {
                return .invalid(reason: "Maximum store count must be a number from 1 to 5.")
            }
        case "minimumSavings", "travelCostPerKm", "fixedStoreVisitCost":
            guard let number = Decimal(string: normalizedValue.replacingOccurrences(of: ",", with: ".")), number >= 0 else {
                return .invalid(reason: "\(normalizedKey) must be a non-negative number.")
            }
        case "communityPricingEnabled":
            if Bool(normalizedValue.lowercased()) == nil {
                return .invalid(reason: "Community pricing must be true or false.")
            }
            return .warning(message: "Community pricing changes affect whether your price observations may be queued for sharing.")
        default:
            return .invalid(reason: "Unknown app setting: \(key).")
        }

        return nil
    }

    private func permissionTarget(for type: ProposedActionType) -> (area: AIPermissionArea, operation: AIPermissionOperation) {
        switch type {
        case .createProduct:
            return (.products, .create)
        case .updateProduct:
            return (.products, .edit)
        case .deleteProduct, .mergeProducts:
            return (.products, .delete)
        case .addProductAlias, .setProductBarcode:
            return (.products, .edit)
        case .removeProductAlias:
            return (.products, .edit)
        case .createPriceObservation:
            return (.prices, .create)
        case .updatePriceObservation, .confirmPriceObservation:
            return (.prices, .edit)
        case .deletePriceObservation:
            return (.prices, .delete)
        case .flagCommunityPrice:
            return (.prices, .edit)
        case .createShoppingList, .addShoppingListItem, .addRecipeToShoppingList:
            return (.shoppingLists, .create)
        case .updateShoppingList, .updateShoppingListItem, .completeShoppingListItem,
             .setShoppingListStatus, .optimizeShoppingList, .moveShoppingListItem, .substituteShoppingListItem:
            return (.shoppingLists, .edit)
        case .deleteShoppingList, .removeShoppingListItem:
            return (.shoppingLists, .delete)
        case .createRecipe:
            return (.recipes, .create)
        case .updateRecipe:
            return (.recipes, .edit)
        case .deleteRecipe:
            return (.recipes, .delete)
        case .setMealPlanSlot, .createMatkasseBox, .addMatkasseMeal, .buildShoppingListFromMealPlan:
            return (.meals, .create)
        case .updateMatkasseBox:
            return (.meals, .edit)
        case .removeMealPlanSlot, .deleteMatkasseBox, .removeMatkasseMeal:
            return (.meals, .delete)
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
    func execute(_ action: ProposedAction) throws -> ActionExecutionResult {
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
            return ActionExecutionResult(ids: [observation.id])

        case .addShoppingListItem(let listName, let productName, let quantity, let notes):
            let list = findOrCreateShoppingList(name: listName)
            guard let idx = shoppingLists.firstIndex(where: { $0.id == list.id }) else { return .empty }
            var item = ShoppingListItem(listID: list.id, productName: productName, requestedQuantity: quantity)
            item.notes = notes
            shoppingLists[idx].items.append(item)
            return ActionExecutionResult(ids: [item.id])

        case .createShoppingList(let name):
            if let existingIndex = shoppingListIndex(matching: name) {
                return ActionExecutionResult(ids: [shoppingLists[existingIndex].id])
            }
            let list = ShoppingList(name: name)
            shoppingLists.append(list)
            return ActionExecutionResult(ids: [list.id], undo: .createdShoppingList(id: list.id))

        case .updateShoppingList(let existingListName, let newName, let plannedDate):
            guard let idx = shoppingListIndex(matching: existingListName) else { return .empty }
            let snapshot = UndoSnapshot.shoppingListFields(
                id: shoppingLists[idx].id,
                name: shoppingLists[idx].name,
                plannedDate: shoppingLists[idx].plannedDate
            )
            if let newName, !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shoppingLists[idx].name = newName
            }
            if let plannedDate {
                shoppingLists[idx].plannedDate = plannedDate
            }
            return ActionExecutionResult(ids: [shoppingLists[idx].id], undo: snapshot)

        case .deleteShoppingList(let listName):
            guard let idx = shoppingListIndex(matching: listName) else { return .empty }
            let snapshot = UndoSnapshot.deletedShoppingList(shoppingLists[idx])
            let id = shoppingLists[idx].id
            shoppingLists.remove(at: idx)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .updateShoppingListItem(let listName, let productName, let newQuantity, let newNotes):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return .empty }
            let item = shoppingLists[listIdx].items[itemIdx]
            let snapshot = UndoSnapshot.shoppingListItemFields(
                listID: shoppingLists[listIdx].id,
                itemID: item.id,
                quantity: item.requestedQuantity,
                notes: item.notes
            )
            if let newQuantity, !newQuantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shoppingLists[listIdx].items[itemIdx].requestedQuantity = newQuantity
            }
            if let newNotes {
                shoppingLists[listIdx].items[itemIdx].notes = newNotes
            }
            return ActionExecutionResult(ids: [shoppingLists[listIdx].items[itemIdx].id], undo: snapshot)

        case .completeShoppingListItem(let listName, let productName, let isCompleted):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return .empty }
            let snapshot = UndoSnapshot.shoppingListItemState(
                listID: shoppingLists[listIdx].id,
                item: shoppingLists[listIdx].items[itemIdx]
            )
            shoppingLists[listIdx].items[itemIdx].isCompleted = isCompleted
            return ActionExecutionResult(ids: [shoppingLists[listIdx].items[itemIdx].id], undo: snapshot)

        case .removeShoppingListItem(let listName, let productName):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return .empty }
            let snapshot = UndoSnapshot.deletedShoppingListItem(
                listID: shoppingLists[listIdx].id,
                item: shoppingLists[listIdx].items[itemIdx]
            )
            let id = shoppingLists[listIdx].items[itemIdx].id
            shoppingLists[listIdx].items.remove(at: itemIdx)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .setShoppingListStatus(let listName, let statusRaw):
            guard let idx = shoppingListIndex(matching: listName) else { return .empty }
            let listID = shoppingLists[idx].id
            let snapshot = UndoSnapshot.shoppingListStatusFields(
                id: listID,
                status: shoppingLists[idx].status,
                completedAt: shoppingLists[idx].completedAt,
                archivedAt: shoppingLists[idx].archivedAt
            )
            switch statusRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "active": activateList(listID)
            case "completed", "done", "archived": archiveShoppingList(listID)
            default: return .empty
            }
            return ActionExecutionResult(ids: [listID], undo: snapshot)

        case .optimizeShoppingList(let listName):
            guard let idx = shoppingListIndex(matching: listName) else { return .empty }
            let listID = shoppingLists[idx].id
            optimizeShoppingList(listID)
            return ActionExecutionResult(ids: [listID])

        case .moveShoppingListItem(let listName, let productName, let storeBranchName):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName),
                  let branch = branches.first(where: { branchMatches($0, name: storeBranchName) }) else { return .empty }
            let itemID = shoppingLists[listIdx].items[itemIdx].id
            let listID = shoppingLists[listIdx].id
            let snapshot = UndoSnapshot.shoppingListItemState(listID: listID, item: shoppingLists[listIdx].items[itemIdx])
            moveItem(itemID, in: listID, toBranchID: branch.id)
            return ActionExecutionResult(ids: [itemID], undo: snapshot)

        case .substituteShoppingListItem(let listName, let productName, let newProductName):
            guard let listIdx = shoppingListIndex(matching: listName),
                  let itemIdx = shoppingListItemIndex(in: listIdx, matchingProduct: productName) else { return .empty }
            let itemID = shoppingLists[listIdx].items[itemIdx].id
            let listID = shoppingLists[listIdx].id
            let snapshot = UndoSnapshot.shoppingListItemState(listID: listID, item: shoppingLists[listIdx].items[itemIdx])
            useSubstitute(itemID, in: listID, newProductName: newProductName)
            return ActionExecutionResult(ids: [itemID], undo: snapshot)

        case .addRecipeToShoppingList(let recipeName, let listName):
            let trimmedRecipeName = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let recipe = recipes.first(where: { $0.title.lowercased() == trimmedRecipeName.lowercased() }) else { return .empty }
            let list = findOrCreateShoppingList(name: listName)
            guard let listIdx = shoppingLists.firstIndex(where: { $0.id == list.id }) else { return .empty }
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
            return ActionExecutionResult(ids: addedIDs)

        case .createStore(let chainName, let branchName, let address, let isEnabled):
            let branch = createStoreBranch(chainName: chainName, branchName: branchName, address: address, isEnabled: isEnabled)
            return ActionExecutionResult(ids: [branch.id])

        case .updateStore(let existingStoreName, let chainName, let branchName, let address, let isEnabled):
            let existingBranch = branches.first(where: { branchMatches($0, name: existingStoreName) })
            let snapshot = existingBranch.map { b in
                UndoSnapshot.storeBranchFields(id: b.id, chainName: b.chainName, branchName: b.name, address: b.address, isEnabled: b.isEnabled)
            }
            guard let branch = updateStoreBranch(matching: existingStoreName, chainName: chainName, branchName: branchName, address: address, isEnabled: isEnabled) else { return .empty }
            return ActionExecutionResult(ids: [branch.id], undo: snapshot)

        case .deleteStore(let storeName):
            guard let branchToDelete = branches.first(where: { branchMatches($0, name: storeName) }) else { return .empty }
            let snapshot = UndoSnapshot.deletedStoreBranch(branchToDelete)
            guard let deletedID = deleteStoreBranch(matching: storeName) else { return .empty }
            return ActionExecutionResult(ids: [deletedID], undo: snapshot)

        case .setStoreEnabled(let storeName, let isEnabled):
            let existingBranch = branches.first(where: { branchMatches($0, name: storeName) })
            let snapshot = existingBranch.map { b in
                UndoSnapshot.storeBranchFields(id: b.id, chainName: b.chainName, branchName: b.name, address: b.address, isEnabled: b.isEnabled)
            }
            guard let branch = setStoreBranchEnabled(matching: storeName, isEnabled: isEnabled) else { return .empty }
            return ActionExecutionResult(ids: [branch.id], undo: snapshot)

        case .createMemory(let summary, let category, let strength, let sensitivityLevel):
            guard !isDuplicateMemory(summary: summary, category: category) else { return .empty }
            let memory = AIMemory(
                summary: summary,
                category: category,
                strength: strength,
                sensitivityLevel: sensitivityLevel
            )
            memories.append(memory)
            return ActionExecutionResult(ids: [memory.id])

        case .updateMemory(let existingSummary, let newSummary, let category, let strength, let sensitivityLevel):
            let resolver = AIEntityResolver(appStore: self)
            guard case .resolved(let memory) = resolver.memory(matching: existingSummary),
                  let idx = memories.firstIndex(where: { $0.id == memory.id }) else { return .empty }
            let snapshot = UndoSnapshot.deletedMemory(memories[idx])
            memories[idx].summary = newSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? memories[idx].summary
            if let category { memories[idx].category = category }
            if let strength { memories[idx].strength = strength }
            if let sensitivityLevel { memories[idx].sensitivityLevel = sensitivityLevel }
            return ActionExecutionResult(ids: [memories[idx].id], undo: snapshot)

        case .deleteMemory(let summary):
            let resolver = AIEntityResolver(appStore: self)
            guard case .resolved(let memory) = resolver.memory(matching: summary),
                  let idx = memories.firstIndex(where: { $0.id == memory.id }) else { return .empty }
            let snapshot = UndoSnapshot.deletedMemory(memories[idx])
            let id = memories[idx].id
            memories.remove(at: idx)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .createHousehold(let name, let ownerDisplayName):
            guard household == nil else { return .empty }
            let owner = AuthUser(
                id: "local-ai-owner",
                email: "local@prispilot.app",
                displayName: ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "PrisPilot User",
                createdAt: Date()
            )
            let snapshot = UndoSnapshot.householdState(household: household, invitations: invitations)
            let created = createHousehold(name: name, owner: owner)
            return ActionExecutionResult(ids: [created.id], undo: snapshot)

        case .inviteHouseholdMember(let email):
            guard household != nil,
                  let invitation = createHouseholdInvitation(inviteeEmail: email, inviterUserID: household?.ownerUserID ?? "local-ai-owner") else { return .empty }
            return ActionExecutionResult(ids: [invitation.id], undo: .createdInvitation(id: invitation.id))

        case .updateHouseholdMember(let userID, let displayName, let role):
            guard var currentHousehold = household,
                  let idx = currentHousehold.members.firstIndex(where: { $0.userID == userID }) else { return .empty }
            let previousHousehold = currentHousehold
            if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentHousehold.members[idx].displayName = displayName
            }
            if let role {
                currentHousehold.members[idx].role = role
            }
            household = currentHousehold
            return ActionExecutionResult(ids: [currentHousehold.members[idx].id], undo: .householdState(household: previousHousehold, invitations: invitations))

        case .createProduct(let name, let category, let unit):
            let product = Product(name: name, category: category, defaultUnit: unit)
            products.append(product)
            return ActionExecutionResult(ids: [product.id])

        case .updateProduct(let existingName, let newName, let category, let unit):
            guard let idx = productIndex(matching: existingName) else { return .empty }
            let snapshot = UndoSnapshot.productFields(
                id: products[idx].id,
                name: products[idx].name,
                category: products[idx].category,
                unit: products[idx].defaultUnit
            )
            if let newName, !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                products[idx].name = newName
            }
            if let category { products[idx].category = category }
            if let unit { products[idx].defaultUnit = unit }
            return ActionExecutionResult(ids: [products[idx].id], undo: snapshot)

        case .deleteProduct(let name):
            guard let idx = productIndex(matching: name) else { return .empty }
            let snapshot = UndoSnapshot.deletedProduct(products[idx])
            let id = products[idx].id
            products.remove(at: idx)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .mergeProducts(let sourceProductName, let targetProductName):
            guard let sourceIdx = productIndex(matching: sourceProductName),
                  let targetIdx = productIndex(matching: targetProductName) else { return .empty }
            let sourceID = products[sourceIdx].id
            let targetID = products[targetIdx].id
            mergeProducts(sourceID: sourceID, targetID: targetID)
            return ActionExecutionResult(ids: [targetID])

        case .updatePriceObservation(let productName, let storeBranchName, let newPrice, let newQuantity, let newUnit):
            guard let idx = mostRecentPersonalObservationIndex(productName: productName, storeBranchName: storeBranchName) else { return .empty }
            let snapshot = UndoSnapshot.priceObservationFields(
                id: priceObservations[idx].id,
                price: priceObservations[idx].price,
                quantity: priceObservations[idx].quantity,
                unit: priceObservations[idx].unit
            )
            if let newPrice { priceObservations[idx].price = newPrice }
            if let newQuantity { priceObservations[idx].quantity = newQuantity }
            if let newUnit { priceObservations[idx].unit = newUnit }
            return ActionExecutionResult(ids: [priceObservations[idx].id], undo: snapshot)

        case .deletePriceObservation(let productName, let storeBranchName):
            guard let idx = mostRecentPersonalObservationIndex(productName: productName, storeBranchName: storeBranchName) else { return .empty }
            let snapshot = UndoSnapshot.deletedPriceObservation(priceObservations[idx])
            let id = priceObservations[idx].id
            priceObservations.remove(at: idx)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .confirmPriceObservation(let productName, let storeBranchName):
            guard let idx = mostRecentPersonalObservationIndex(productName: productName, storeBranchName: storeBranchName) else { return .empty }
            let obsID = priceObservations[idx].id
            guard let refreshed = confirmPriceObservation(obsID) else { return .empty }
            return ActionExecutionResult(ids: [refreshed.id])

        case .flagCommunityPrice(let productName, let storeBranchName):
            let target = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var candidates = priceObservations.filter { $0.productName.lowercased() == target && $0.source == .community }
            if let storeBranchName, !storeBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let storeTarget = storeBranchName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let narrowed = candidates.filter { $0.storeBranchName.lowercased().contains(storeTarget) }
                if !narrowed.isEmpty { candidates = narrowed }
            }
            guard let obs = candidates.max(by: { $0.observedDate < $1.observedDate }) else { return .empty }
            let existingContribution = communityContributions.first(where: { $0.sourceObservationID == obs.id })
            let changedContribution = flagCommunityPriceObservation(obs.id)
            let snapshot: UndoSnapshot?
            if let existingContribution {
                snapshot = .communityContributionFlag(id: existingContribution.id, wasFlagged: existingContribution.isFlagged)
            } else if let changedContribution {
                snapshot = .createdCommunityContribution(id: changedContribution.id)
            } else {
                snapshot = nil
            }
            return ActionExecutionResult(ids: [obs.id], undo: snapshot)

        case .addProductAlias(let productName, let alias):
            guard let idx = productIndex(matching: productName) else { return .empty }
            let id = products[idx].id
            let snapshot = UndoSnapshot.productMetadataFields(id: id, aliases: products[idx].aliases, barcode: products[idx].barcode)
            addProductAlias(id, alias: alias)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .removeProductAlias(let productName, let alias):
            guard let idx = productIndex(matching: productName) else { return .empty }
            let id = products[idx].id
            let snapshot = UndoSnapshot.productMetadataFields(id: id, aliases: products[idx].aliases, barcode: products[idx].barcode)
            removeProductAlias(id, alias: alias)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .setProductBarcode(let productName, let barcode):
            guard let idx = productIndex(matching: productName) else { return .empty }
            let id = products[idx].id
            let snapshot = UndoSnapshot.productMetadataFields(id: id, aliases: products[idx].aliases, barcode: products[idx].barcode)
            setProductBarcode(id, barcode: barcode)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .createRecipe(let title, let servings, let ingredients):
            let recipe = Recipe(title: title, servings: servings)
            var savedRecipe = recipe
            savedRecipe.ingredients = ingredients
            recipes.append(savedRecipe)
            return ActionExecutionResult(ids: [savedRecipe.id])

        case .updateRecipe(let existingTitle, let newTitle, let description, let servings):
            guard let idx = recipeIndex(matching: existingTitle) else { return .empty }
            let snapshot = UndoSnapshot.recipeFields(
                id: recipes[idx].id,
                title: recipes[idx].title,
                description: recipes[idx].description,
                servings: recipes[idx].servings
            )
            if let newTitle, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recipes[idx].title = newTitle
            }
            if let description { recipes[idx].description = description }
            if let servings { recipes[idx].servings = servings }
            return ActionExecutionResult(ids: [recipes[idx].id], undo: snapshot)

        case .deleteRecipe(let title):
            guard let idx = recipeIndex(matching: title) else { return .empty }
            let snapshot = UndoSnapshot.deletedRecipe(recipes[idx])
            let id = recipes[idx].id
            recipes.remove(at: idx)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .setMealPlanSlot(let date, let mealTypeRaw, let recipeTitle, let freeformText, let isEatingOut, let isLeftover):
            let resolvedMealType = mealType(fromRawValue: mealTypeRaw)
            let existingSlot = mealPlans.lazy.flatMap(\.slots).first(where: {
                Calendar.mealPlanCalendar.isDate($0.date, inSameDayAs: date) && $0.mealType == resolvedMealType
            })
            let snapshot: UndoSnapshot = existingSlot.map { .overwrittenMealPlanSlot(slot: $0) } ?? .addedMealPlanSlot(date: date, mealType: resolvedMealType)
            let content: MealSlotContent?
            if let recipeTitle, let recipe = recipes.first(where: { $0.title.lowercased() == recipeTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) {
                content = .recipe(recipeID: recipe.id, title: recipe.title)
            } else if isEatingOut {
                content = .eatingOut(note: freeformText)
            } else if let freeformText, !freeformText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = .freeform(freeformText)
            } else {
                content = nil
            }
            guard let content else { return .empty }
            setMealPlanSlot(date: date, mealType: resolvedMealType, content: content, isLeftover: isLeftover)
            return ActionExecutionResult(ids: [], undo: snapshot)

        case .removeMealPlanSlot(let date, let mealTypeRaw):
            let resolvedMealType = mealType(fromRawValue: mealTypeRaw)
            let existingSlot = mealPlans.lazy.flatMap(\.slots).first(where: {
                Calendar.mealPlanCalendar.isDate($0.date, inSameDayAs: date) && $0.mealType == resolvedMealType
            })
            let snapshot = existingSlot.map { UndoSnapshot.clearedMealPlanSlot(slot: $0) }
            clearMealPlanSlot(date: date, mealType: resolvedMealType)
            return ActionExecutionResult(ids: [], undo: snapshot)

        case .buildShoppingListFromMealPlan(let weekStart, let oneListPerWeek):
            let resolvedWeekStart = weekStartDate(for: weekStart ?? Date())
            let days = (0..<7).compactMap { Calendar.mealPlanCalendar.date(byAdding: .day, value: $0, to: resolvedWeekStart) }
            let slots = mealPlanSlots(on: days)
            let mode: ShoppingListGenerationMode = oneListPerWeek ? .perWeek : .singleList
            let generatedIDs = generateShoppingList(
                fromSlots: slots,
                mode: mode,
                listNamePrefix: "Week of \(resolvedWeekStart.formatted(date: .abbreviated, time: .omitted))"
            )
            return ActionExecutionResult(ids: generatedIDs)

        case .createMatkasseBox(let provider, let deliveryWeek, let numberOfMeals, let servingsPerMeal, let price, let notes):
            let box = createMatkasseBox(
                provider: provider,
                deliveryWeekStartDate: weekStartDate(for: deliveryWeek ?? Date()),
                numberOfMeals: numberOfMeals ?? 4,
                servingsPerMeal: servingsPerMeal ?? 2,
                price: price,
                notes: notes
            )
            return ActionExecutionResult(ids: [box.id])

        case .updateMatkasseBox(let existingProvider, let newProvider, let deliveryWeek, let numberOfMeals, let servingsPerMeal, let price, let notes):
            let target = existingProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let box = matkasseBoxes.first(where: { $0.provider.lowercased() == target }) else { return .empty }
            let snapshot = UndoSnapshot.matkasseBoxFields(
                id: box.id,
                provider: box.provider,
                deliveryWeekStartDate: box.deliveryWeekStartDate,
                numberOfMeals: box.numberOfMeals,
                servingsPerMeal: box.servingsPerMeal,
                price: box.price,
                notes: box.notes
            )
            updateMatkasseBox(
                box.id,
                provider: newProvider,
                deliveryWeekStartDate: deliveryWeek.map { weekStartDate(for: $0) },
                numberOfMeals: numberOfMeals,
                servingsPerMeal: servingsPerMeal,
                price: price,
                notes: notes
            )
            return ActionExecutionResult(ids: [box.id], undo: snapshot)

        case .deleteMatkasseBox(let provider):
            let target = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let box = matkasseBoxes.first(where: { $0.provider.lowercased() == target }) else { return .empty }
            let snapshot = UndoSnapshot.deletedMatkasseBox(box)
            let id = box.id
            deleteMatkasseBox(id)
            return ActionExecutionResult(ids: [id], undo: snapshot)

        case .addMatkasseMeal(let boxProvider, let mealTitle):
            let trimmedProvider = boxProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let box = matkasseBoxes.first(where: { $0.provider.lowercased() == trimmedProvider }) else { return .empty }
            addMatkasseMeal(to: box.id, title: mealTitle)
            let addedMealID = matkasseBoxes.first(where: { $0.id == box.id })?.includedMeals.last?.id
            return ActionExecutionResult(ids: addedMealID.map { [$0] } ?? [])

        case .removeMatkasseMeal(let boxProvider, let mealTitle):
            let trimmedProvider = boxProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let trimmedTitle = mealTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let box = matkasseBoxes.first(where: { $0.provider.lowercased() == trimmedProvider }),
                  let meal = box.includedMeals.first(where: { $0.title.lowercased() == trimmedTitle }) else { return .empty }
            let snapshot = UndoSnapshot.deletedMatkasseMeal(boxID: box.id, meal: meal)
            removeMatkasseMeal(meal.id, from: box.id)
            return ActionExecutionResult(ids: [meal.id], undo: snapshot)

        case .changeAppSetting(let key, let value):
            applySettingChange(key: key, value: value)
            return .empty

        case .generic:
            return .empty
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

    /// Case-insensitive exact-name lookup for AI actions that must target
    /// an *existing* product (update/delete/merge) — never creates one,
    /// same reasoning as `shoppingListIndex(matching:)`.
    private func productIndex(matching name: String) -> Int? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return products.firstIndex { $0.name.lowercased() == target }
    }

    /// Case-insensitive exact-title lookup for AI actions targeting an
    /// *existing* recipe (update/delete) — same non-creating reasoning as
    /// `productIndex(matching:)`.
    private func recipeIndex(matching title: String) -> Int? {
        let target = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recipes.firstIndex { $0.title.lowercased() == target }
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func mealPlanSlotExists(date: Date, mealTypeRaw: String) -> Bool {
        let mealType = mealType(fromRawValue: mealTypeRaw)
        let weekStart = weekStartDate(for: date)
        guard let plan = mealPlan(forWeekStartDate: weekStart) else { return false }
        return plan.slots.contains {
            Calendar.mealPlanCalendar.isDate($0.date, inSameDayAs: date) && $0.mealType == mealType
        }
    }

    private func matkasseBox(matchingProvider provider: String) -> MatkasseBox? {
        let target = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return matkasseBoxes.first { $0.provider.lowercased() == target }
    }

    private func communityObservationExists(productName: String, storeBranchName: String?) -> Bool {
        let targetProduct = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetStore = storeBranchName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return priceObservations.contains { observation in
            guard observation.source == .community,
                  observation.productName.lowercased() == targetProduct else { return false }
            guard let targetStore, !targetStore.isEmpty else { return true }
            return observation.storeBranchName.lowercased().contains(targetStore)
        }
    }

    private func dateIsTooFarInFuture(_ date: Date) -> Bool {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return date > tomorrow
    }

    private func dateIsTooFarInPast(_ date: Date) -> Bool {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
        return date < oneYearAgo
    }

    /// Maps a chat-provided meal-type string ("Breakfast", "dinner", ...)
    /// to `MealType`, falling back to `.custom` for anything that isn't
    /// one of the three defaults — lets a user say "add a snack Tuesday"
    /// without the AI action failing outright.
    private func mealType(fromRawValue raw: String) -> MealType {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "breakfast": return .breakfast
        case "lunch": return .lunch
        case "dinner": return .dinner
        default: return .custom(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Most recently observed non-community price for a product, optionally
    /// narrowed to a store — the "which observation did the user mean" for
    /// a chat-driven price update/delete, since a product can have many
    /// historical observations. Community prices are excluded: a chat
    /// user editing/deleting "their" price shouldn't be able to touch
    /// someone else's community-sourced observation this way.
    private func mostRecentPersonalObservationIndex(productName: String, storeBranchName: String?) -> Int? {
        let targetProduct = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidates = priceObservations.indices.filter {
            priceObservations[$0].productName.lowercased() == targetProduct &&
            priceObservations[$0].source != .community
        }
        if let storeBranchName, !storeBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let targetStore = storeBranchName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let narrowed = candidates.filter { priceObservations[$0].storeBranchName.lowercased().contains(targetStore) }
            if !narrowed.isEmpty { candidates = narrowed }
        }
        return candidates.max { priceObservations[$0].observedDate < priceObservations[$1].observedDate }
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

    // MARK: - Product Management

    func addProductAlias(_ productID: UUID, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = products.firstIndex(where: { $0.id == productID }),
              !products[idx].aliases.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        products[idx].aliases.append(trimmed)
        persistNow()
    }

    func removeProductAlias(_ productID: UUID, alias: String) {
        guard let idx = products.firstIndex(where: { $0.id == productID }) else { return }
        products[idx].aliases.removeAll { $0 == alias }
        persistNow()
    }

    func setProductBarcode(_ productID: UUID, barcode: String?) {
        guard let idx = products.firstIndex(where: { $0.id == productID }) else { return }
        products[idx].barcode = barcode
        persistNow()
    }

    /// Re-confirms a price is still accurate by recording a fresh
    /// observation with today's date — same price/quantity/unit/store,
    /// new `observedDate`. Appends rather than mutating the old
    /// observation, matching this app's append-only price history model.
    @discardableResult
    func confirmPriceObservation(_ observationID: UUID) -> PriceObservation? {
        guard let existing = priceObservations.first(where: { $0.id == observationID }) else { return nil }
        let refreshed = PriceObservation(
            productID: existing.productID,
            productName: existing.productName,
            storeBranchID: existing.storeBranchID,
            storeBranchName: existing.storeBranchName,
            price: existing.price,
            currency: existing.currency,
            quantity: existing.quantity,
            unit: existing.unit,
            isPromotion: false,
            priceKind: existing.priceKind,
            observedDate: Date(),
            source: .manual,
            scope: existing.scope
        )
        priceObservations.append(refreshed)
        queueCommunityContributionIfNeeded(for: refreshed)
        persistNow()
        return refreshed
    }

    /// Merges a duplicate product into another: every price observation and
    /// shopping-list item referencing `sourceID` is reassigned to
    /// `targetID` (name updated to match), the source's name and aliases
    /// are folded into the target's alias list, and the source product is
    /// deleted.
    func mergeProducts(sourceID: UUID, targetID: UUID) {
        guard sourceID != targetID,
              let sourceIdx = products.firstIndex(where: { $0.id == sourceID }),
              let targetIdx = products.firstIndex(where: { $0.id == targetID }) else { return }

        let source = products[sourceIdx]
        let targetName = products[targetIdx].name

        for idx in priceObservations.indices where priceObservations[idx].productID == sourceID {
            priceObservations[idx].productID = targetID
            priceObservations[idx].productName = targetName
        }

        for listIdx in shoppingLists.indices {
            for itemIdx in shoppingLists[listIdx].items.indices where shoppingLists[listIdx].items[itemIdx].productID == sourceID {
                shoppingLists[listIdx].items[itemIdx].productID = targetID
                shoppingLists[listIdx].items[itemIdx].productName = targetName
            }
        }

        var mergedAliases = Set(products[targetIdx].aliases)
        mergedAliases.formUnion(source.aliases)
        mergedAliases.insert(source.name)
        mergedAliases.remove(targetName)
        products[targetIdx].aliases = mergedAliases.sorted()
        if products[targetIdx].barcode == nil {
            products[targetIdx].barcode = source.barcode
        }

        products.remove(at: sourceIdx)
        persistNow()
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

    @discardableResult
    func flagCommunityPriceObservation(_ observationID: UUID) -> CommunityContribution? {
        guard let observation = priceObservations.first(where: { $0.id == observationID }) else { return nil }
        if let index = communityContributions.firstIndex(where: { $0.sourceObservationID == observationID }) {
            communityContributions[index].isFlagged = true
            persistNow()
            return communityContributions[index]
        } else {
            let contribution = CommunityContribution(
                sourceObservation: observation,
                anonymousContributorHash: settings.anonymousCommunityContributorID
            )
            communityContributions.append(contribution)
            communityContributions[communityContributions.count - 1].isFlagged = true
            persistNow()
            return communityContributions[communityContributions.count - 1]
        }
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

    // MARK: - Meal Planning

    func mealPlan(forWeekStartDate weekStartDate: Date) -> MealPlan? {
        mealPlans.first { Calendar.mealPlanCalendar.isDate($0.weekStartDate, inSameDayAs: weekStartDate) }
    }

    /// The Monday that starts the ISO week containing `date` — every slot
    /// lives on the `MealPlan` for its own day's week, so a day/fortnight/
    /// month view spanning multiple weeks reads/writes across several
    /// `MealPlan` records transparently rather than needing one plan per
    /// view range.
    func weekStartDate(for date: Date) -> Date {
        Calendar.mealPlanCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    @discardableResult
    private func findOrCreateMealPlan(forDate date: Date) -> MealPlan {
        let weekStart = weekStartDate(for: date)
        if let existing = mealPlan(forWeekStartDate: weekStart) {
            return existing
        }
        let plan = MealPlan(
            name: "Week of \(weekStart.formatted(date: .abbreviated, time: .omitted))",
            weekStartDate: weekStart
        )
        mealPlans.append(plan)
        return plan
    }

    /// Creates or replaces the slot for a given day + meal type — a meal
    /// plan holds at most one slot per (date, mealType) pair, so setting a
    /// slot that's already occupied overwrites its content rather than
    /// adding a second one.
    func setMealPlanSlot(date: Date, mealType: MealType, content: MealSlotContent, isLeftover: Bool = false, notes: String? = nil) {
        let plan = findOrCreateMealPlan(forDate: date)
        guard let planIdx = mealPlans.firstIndex(where: { $0.id == plan.id }) else { return }
        if let slotIdx = mealPlans[planIdx].slots.firstIndex(where: {
            Calendar.mealPlanCalendar.isDate($0.date, inSameDayAs: date) && $0.mealType == mealType
        }) {
            mealPlans[planIdx].slots[slotIdx].content = content
            mealPlans[planIdx].slots[slotIdx].isLeftover = isLeftover
            mealPlans[planIdx].slots[slotIdx].notes = notes
        } else {
            let slot = MealPlanSlot(date: date, mealType: mealType, content: content, isLeftover: isLeftover, notes: notes)
            mealPlans[planIdx].slots.append(slot)
        }
        persistNow()
    }

    func clearMealPlanSlot(date: Date, mealType: MealType) {
        let weekStart = weekStartDate(for: date)
        guard let planIdx = mealPlans.firstIndex(where: { Calendar.mealPlanCalendar.isDate($0.weekStartDate, inSameDayAs: weekStart) }) else { return }
        mealPlans[planIdx].slots.removeAll {
            Calendar.mealPlanCalendar.isDate($0.date, inSameDayAs: date) && $0.mealType == mealType
        }
        persistNow()
    }

    /// Every slot from every `MealPlan` whose date falls within `dates` —
    /// used by the planner to compute summary stats and calendar dots
    /// across a range that may span several `MealPlan` (week) records.
    func mealPlanSlots(on dates: [Date]) -> [MealPlanSlot] {
        let dayKeys = Set(dates.map { Calendar.mealPlanCalendar.startOfDay(for: $0) })
        let weekStarts = Set(dates.map { weekStartDate(for: $0) })
        return weekStarts
            .compactMap { mealPlan(forWeekStartDate: $0) }
            .flatMap { $0.slots }
            .filter { dayKeys.contains(Calendar.mealPlanCalendar.startOfDay(for: $0.date)) }
    }

    // MARK: - Meal Planning: Shopping List Generation

    enum ShoppingListGenerationMode {
        /// Every planned recipe's ingredients merged into one list.
        case singleList
        /// One list per week the selected slots span — matches how the
        /// product plan frames "one weekly list or lists per shopping trip"
        /// for ranges wider than a single week (fortnight/month).
        case perWeek
    }

    /// Builds shopping list(s) from planned *recipe* slots only — matkasse,
    /// freeform, and eating-out slots don't contribute ingredients (matkasse
    /// is deliberately excluded per the product plan's confirmed decision:
    /// its ingredients are already being delivered). Duplicate ingredients
    /// across recipes are merged via `looselyMatchesProductName`, with
    /// same-unit-family quantities summed through the Phase 6 unit-price
    /// helpers rather than listed as separate rows.
    @discardableResult
    func generateShoppingList(
        fromSlots slots: [MealPlanSlot],
        mode: ShoppingListGenerationMode,
        excludingIngredientNames excludedNames: Set<String> = [],
        listNamePrefix: String
    ) -> [UUID] {
        let recipeSlots: [(slot: MealPlanSlot, recipe: Recipe)] = slots.compactMap { slot in
            guard case .recipe(let recipeID, _) = slot.content,
                  let recipe = recipes.first(where: { $0.id == recipeID }) else { return nil }
            return (slot, recipe)
        }
        guard !recipeSlots.isEmpty else { return [] }

        switch mode {
        case .singleList:
            let list = buildMergedShoppingList(
                named: "\(listNamePrefix) Shopping List",
                from: recipeSlots.map(\.recipe),
                excluding: excludedNames
            )
            return [list.id]

        case .perWeek:
            let grouped = Dictionary(grouping: recipeSlots) { weekStartDate(for: $0.slot.date) }
            return grouped.keys.sorted().map { weekStart in
                let weekRecipes = (grouped[weekStart] ?? []).map(\.recipe)
                let list = buildMergedShoppingList(
                    named: "Week of \(weekStart.formatted(date: .abbreviated, time: .omitted))",
                    from: weekRecipes,
                    excluding: excludedNames
                )
                return list.id
            }
        }
    }

    private func buildMergedShoppingList(named name: String, from recipesToMerge: [Recipe], excluding excludedNames: Set<String>) -> ShoppingList {
        var merged: [(name: String, quantities: [(Double, MeasurementUnit)])] = []

        for recipe in recipesToMerge {
            for ingredient in recipe.ingredients {
                guard !excludedNames.contains(where: { $0.looselyMatchesProductName(ingredient.productName) }) else { continue }
                if let idx = merged.firstIndex(where: { $0.name.looselyMatchesProductName(ingredient.productName) }) {
                    merged[idx].quantities.append((ingredient.quantity, ingredient.unit))
                } else {
                    merged.append((ingredient.productName, [(ingredient.quantity, ingredient.unit)]))
                }
            }
        }

        var list = ShoppingList(name: name)
        list.items = merged.map { entry in
            ShoppingListItem(listID: list.id, productName: entry.name, requestedQuantity: mergedQuantityText(entry.quantities))
        }
        shoppingLists.append(list)
        return list
    }

    /// Sums quantities that share a unit family (grams+kilograms → kg,
    /// millilitres+litres → l) via the Phase 6 unit-normalization helpers;
    /// pieces and packs don't cross-merge with each other or with
    /// weight/volume, since "3 pieces + 2 packs" has no single sane sum.
    private func mergedQuantityText(_ quantities: [(Double, MeasurementUnit)]) -> String {
        var byNormalizedUnit: [MeasurementUnit: Double] = [:]
        for (quantity, unit) in quantities {
            let normalizedUnit = unit.normalizedComparisonUnit
            let baseQuantity = quantity * unit.baseUnitsPerUnit
            byNormalizedUnit[normalizedUnit, default: 0] += baseQuantity / normalizedUnit.baseUnitsPerUnit
        }
        return byNormalizedUnit
            .map { unit, quantity in "\(quantity.formatted()) \(unit.rawValue)" }
            .sorted()
            .joined(separator: " + ")
    }

    // MARK: - Matkasse

    @discardableResult
    func createMatkasseBox(provider: String, deliveryWeekStartDate: Date, numberOfMeals: Int, servingsPerMeal: Int, price: Decimal?, notes: String?) -> MatkasseBox {
        let box = MatkasseBox(
            provider: provider,
            deliveryWeekStartDate: deliveryWeekStartDate,
            numberOfMeals: numberOfMeals,
            servingsPerMeal: servingsPerMeal,
            price: price,
            notes: notes
        )
        matkasseBoxes.append(box)
        persistNow()
        return box
    }

    func deleteMatkasseBox(_ boxID: UUID) {
        matkasseBoxes.removeAll { $0.id == boxID }
        persistNow()
    }

    func updateMatkasseBox(
        _ boxID: UUID,
        provider: String? = nil,
        deliveryWeekStartDate: Date? = nil,
        numberOfMeals: Int? = nil,
        servingsPerMeal: Int? = nil,
        price: Decimal? = nil,
        notes: String? = nil
    ) {
        guard let idx = matkasseBoxes.firstIndex(where: { $0.id == boxID }) else { return }
        if let provider, !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            matkasseBoxes[idx].provider = provider
        }
        if let deliveryWeekStartDate { matkasseBoxes[idx].deliveryWeekStartDate = deliveryWeekStartDate }
        if let numberOfMeals { matkasseBoxes[idx].numberOfMeals = numberOfMeals }
        if let servingsPerMeal { matkasseBoxes[idx].servingsPerMeal = servingsPerMeal }
        if let price { matkasseBoxes[idx].price = price }
        if let notes { matkasseBoxes[idx].notes = notes }
        persistNow()
    }

    func addMatkasseMeal(to boxID: UUID, title: String, ingredients: [RecipeIngredient] = []) {
        guard let idx = matkasseBoxes.firstIndex(where: { $0.id == boxID }) else { return }
        var meal = MatkasseMeal(title: title)
        meal.ingredients = ingredients
        matkasseBoxes[idx].includedMeals.append(meal)
        persistNow()
    }

    func removeMatkasseMeal(_ mealID: UUID, from boxID: UUID) {
        guard let idx = matkasseBoxes.firstIndex(where: { $0.id == boxID }) else { return }
        matkasseBoxes[idx].includedMeals.removeAll { $0.id == mealID }
        persistNow()
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
