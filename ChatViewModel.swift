import Foundation
import Observation

@Observable
@MainActor
class ChatViewModel {
    var inputText: String = ""
    var isSending: Bool = false
    var isTyping: Bool = false

    private let appStore: AppStore

    var messages: [ChatMessage] {
        guard let sessionID = appStore.selectedChatSessionID else { return [] }
        return appStore.messages(for: sessionID)
    }

    // Always reads the current service from AppStore so switching keys takes effect immediately.
    private var aiService: any AIService { appStore.currentAIService }

    init(appStore: AppStore) {
        self.appStore = appStore
        appStore.ensureDefaultChatSession()
    }

    // MARK: - Sessions

    func startNewChat() {
        appStore.createChatSession()
        inputText = ""
    }

    func selectChatSession(_ id: UUID) {
        appStore.selectChatSession(id)
        inputText = ""
    }

    func deleteChatSessions(at offsets: IndexSet) {
        appStore.deleteChatSessions(at: offsets)
        appStore.ensureDefaultChatSession()
    }

    // MARK: - Sending

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        let sessionID = appStore.ensureDefaultChatSession()
        inputText = ""
        appStore.appendMessage(ChatMessage(role: .user, content: .text(text)), to: sessionID)

        if appStore.isAIOnboardingActive(for: sessionID) {
            handleAIOnboardingAnswer(text, in: sessionID)
            return
        }

        isSending = true
        isTyping = true

        Task {
            defer {
                isSending = false
                isTyping = false
            }
            do {
                let response = try await aiService.send(
                    messages: buildAIMessages(for: sessionID),
                    context: buildContext(),
                    availableTools: []
                )
                handleResponse(response, in: sessionID)
            } catch let error as AIServiceError {
                appStore.appendMessage(ChatMessage(role: .assistant, content: .error(error)), to: sessionID)
            } catch {
                appStore.appendMessage(ChatMessage(role: .assistant, content: .error(.unknown(error.localizedDescription))), to: sessionID)
            }
        }
    }

    private func handleAIOnboardingAnswer(_ text: String, in sessionID: UUID) {
        isSending = true
        isTyping = true

        Task {
            defer {
                isSending = false
                isTyping = false
            }

            guard let questionIndex = appStore.aiOnboardingProgressBySessionID[sessionID],
                  let question = OnboardingFlow.question(after: questionIndex),
                  let onboardingService = aiService as? any OnboardingAIService else {
                let message = appStore.nextAIOnboardingMessage(after: text, in: sessionID)
                appStore.appendMessage(message, to: sessionID)
                return
            }

            do {
                let result = try await onboardingService.sendOnboardingTurn(
                    question: question,
                    userAnswer: text,
                    knownAnswers: appStore.onboardingAnswers,
                    context: buildContext()
                )
                applyOnboardingResult(result, originalAnswer: text, sessionID: sessionID)
            } catch let error as AIServiceError {
                appStore.appendMessage(ChatMessage(role: .assistant, content: .error(error)), to: sessionID)
            } catch {
                appStore.appendMessage(ChatMessage(role: .assistant, content: .error(.unknown(error.localizedDescription))), to: sessionID)
            }
        }
    }

    private func applyOnboardingResult(_ result: OnboardingAIResult, originalAnswer: String, sessionID: UUID) {
        appStore.appendMessage(ChatMessage(role: .assistant, content: .text(result.assistantText)), to: sessionID)

        var tags: [ActivityTag] = []
        for action in result.proposedActions {
            var executableAction = action
            if let ids = try? appStore.execute(executableAction) {
                executableAction.resultingRecordIDs = ids
                executableAction.status = .completed
                tags.append(ActivityTag(from: executableAction))
            }
        }

        for proposal in result.memoryProposals {
            let action = ProposedAction(
                type: .createMemory,
                summary: "Remembered: \(proposal.memory.summary)",
                payload: .createMemory(
                    summary: proposal.memory.summary,
                    category: proposal.memory.category,
                    strength: proposal.memory.strength,
                    sensitivityLevel: proposal.memory.sensitivityLevel
                ),
                requiresConfirmation: false
            )
            var executableAction = action
            if let ids = try? appStore.execute(executableAction) {
                executableAction.resultingRecordIDs = ids
                executableAction.status = .completed
                tags.append(ActivityTag(from: executableAction))
            }
        }

        if !tags.isEmpty {
            appStore.appendMessage(ChatMessage(role: .assistant, content: .activityTags(tags)), to: sessionID)
        }

        guard result.shouldAdvance else { return }
        let answer = result.normalizedAnswer ?? originalAnswer
        let nextMessage = appStore.nextAIOnboardingMessage(after: answer, in: sessionID)
        appStore.appendMessage(nextMessage, to: sessionID)
    }

    // MARK: - Action Approval

    func approveAll(in messageID: UUID) {
        guard let sessionID = appStore.selectedChatSessionID,
              let message = appStore.messages(for: sessionID).first(where: { $0.id == messageID }),
              case .proposedActions(_, var actions, let memoryProposals) = message.content
        else { return }

        var tags: [ActivityTag] = []

        for i in 0..<actions.count where actions[i].status == .pending {
            actions[i].status = .executing
            if let ids = try? appStore.execute(actions[i]) {
                actions[i].resultingRecordIDs = ids
                actions[i].status = .completed
                tags.append(ActivityTag(from: actions[i]))
            } else {
                actions[i].status = .failed
            }
        }

        for proposal in memoryProposals {
            let memAction = ProposedAction(
                type: .createMemory,
                summary: "Remembered: \(proposal.memory.summary)",
                payload: .createMemory(
                    summary: proposal.memory.summary,
                    category: proposal.memory.category,
                    strength: proposal.memory.strength,
                    sensitivityLevel: proposal.memory.sensitivityLevel
                )
            )
            if let _ = try? appStore.execute(memAction) {
                let tag = ActivityTag(from: memAction)
                tags.append(tag)
            }
        }

        appStore.replaceMessage(messageID, in: sessionID, with: .activityTags(tags))
    }

    func approve(actionID: UUID, in messageID: UUID) {
        guard let sessionID = appStore.selectedChatSessionID,
              let message = appStore.messages(for: sessionID).first(where: { $0.id == messageID }),
              case .proposedActions(let intro, var actions, let memoryProposals) = message.content,
              let actIdx = actions.firstIndex(where: { $0.id == actionID })
        else { return }

        actions[actIdx].status = .executing
        if let ids = try? appStore.execute(actions[actIdx]) {
            actions[actIdx].resultingRecordIDs = ids
            actions[actIdx].status = .completed
        } else {
            actions[actIdx].status = .failed
        }

        let content = ChatMessageContent.proposedActions(intro: intro, actions: actions, memoryProposals: memoryProposals)
        appStore.replaceMessage(messageID, in: sessionID, with: content)
        collapseIfAllTerminal(messageID: messageID, sessionID: sessionID)
    }

    func reject(actionID: UUID, in messageID: UUID) {
        guard let sessionID = appStore.selectedChatSessionID,
              let message = appStore.messages(for: sessionID).first(where: { $0.id == messageID }),
              case .proposedActions(let intro, var actions, let memoryProposals) = message.content,
              let actIdx = actions.firstIndex(where: { $0.id == actionID })
        else { return }

        actions[actIdx].status = .rejected
        let content = ChatMessageContent.proposedActions(intro: intro, actions: actions, memoryProposals: memoryProposals)
        appStore.replaceMessage(messageID, in: sessionID, with: content)
        collapseIfAllTerminal(messageID: messageID, sessionID: sessionID)
    }

    func rejectAll(in messageID: UUID) {
        guard let sessionID = appStore.selectedChatSessionID,
              let message = appStore.messages(for: sessionID).first(where: { $0.id == messageID }),
              case .proposedActions(_, var actions, _) = message.content
        else { return }

        for i in 0..<actions.count where !actions[i].status.isTerminal {
            actions[i].status = .rejected
        }
        appStore.replaceMessage(messageID, in: sessionID, with: .activityTags([]))
    }

    // MARK: - Private

    private func handleResponse(_ response: AIResponse, in sessionID: UUID) {
        if let error = response.error {
            appStore.appendMessage(ChatMessage(role: .assistant, content: .error(error)), to: sessionID)
            return
        }

        if !response.proposedActions.isEmpty || !response.memoryProposals.isEmpty {
            appStore.appendMessage(ChatMessage(
                role: .assistant,
                content: .proposedActions(
                    intro: response.textContent,
                    actions: response.proposedActions,
                    memoryProposals: response.memoryProposals
                )
            ), to: sessionID)
        } else if let text = response.textContent {
            appStore.appendMessage(ChatMessage(role: .assistant, content: .text(text)), to: sessionID)
        }
    }

    private func collapseIfAllTerminal(messageID: UUID, sessionID: UUID) {
        guard let message = appStore.messages(for: sessionID).first(where: { $0.id == messageID }),
              case .proposedActions(_, let actions, _) = message.content,
              actions.allSatisfy({ $0.status.isTerminal })
        else { return }

        let tags = actions.filter { $0.status == .completed }.map { ActivityTag(from: $0) }
        appStore.replaceMessage(messageID, in: sessionID, with: .activityTags(tags))
    }

    private func buildAIMessages(for sessionID: UUID) -> [AIMessage] {
        appStore.messages(for: sessionID).compactMap { msg in
            if case .text(let text) = msg.content {
                return AIMessage(role: msg.role == .user ? .user : .assistant, content: text)
            }
            return nil
        }
    }

    private func buildContext() -> AIContext {
        AIContext(
            relevantMemories: Array(appStore.activeMemories.prefix(10)),
            availableShoppingLists: appStore.activeLists.map { $0.name },
            enabledStoreBranches: appStore.branches.map { "\($0.displayName) (\($0.isEnabled ? "enabled" : "disabled"))" },
            userPreferences: "",
            currency: appStore.settings.currency
        )
    }
}
