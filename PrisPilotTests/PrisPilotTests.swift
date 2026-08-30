//
//  PrisPilotTests.swift
//  PrisPilotTests
//
//  Created by Joshua James O’Connor on 20/08/2026.
//

import Foundation
import Testing
@testable import PrisPilot

struct PrisPilotTests {

    @Test func aiScopePolicyBlocksCodingRequests() {
        let response = AIScopePolicy.localRefusal(for: "Write Swift code for a weather app")

        #expect(response?.textContent?.contains("PrisPilot tasks") == true)
    }

    @Test func aiScopePolicyBlocksGeneralReasoningPrompts() {
        let response = AIScopePolicy.localRefusal(for: "Solve this logic puzzle for me")

        #expect(response != nil)
    }

    @Test func aiScopePolicyAllowsMealPlanning() {
        let response = AIScopePolicy.localRefusal(for: "Plan taco dinner for four people under kr 250")

        #expect(response == nil)
    }

    @Test func aiScopePolicyAllowsBareShoppingItems() {
        let response = AIScopePolicy.localRefusal(for: "Add tomatoes to my list")

        #expect(response == nil)
    }

    @MainActor
    @Test func validationRejectsDuplicateShoppingListCreation() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createShoppingList,
            summary: "Create shopping list: Weekly Shop",
            payload: .createShoppingList(name: "Weekly Shop")
        )

        #expect(validationReason(for: store.validate(action)) == "A shopping list named Weekly Shop already exists.")
    }

    @MainActor
    @Test func validationRejectsMissingShoppingListItemTarget() {
        let store = AppStore()
        let action = ProposedAction(
            type: .removeShoppingListItem,
            summary: "Remove Milk from Weekly Shop",
            payload: .removeShoppingListItem(listName: "Weekly Shop", productName: "Milk")
        )

        #expect(validationReason(for: store.validate(action)) == "No item named Milk was found on Weekly Shop.")
    }

    @MainActor
    @Test func validationRejectsInvalidPriceObservation() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: Decimal(0),
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )

        #expect(validationReason(for: store.validate(action)) == "Price must be greater than zero.")
    }

    @MainActor
    @Test func validationRejectsMissingRecipeForRecipeToListAction() {
        let store = AppStore()
        let action = ProposedAction(
            type: .addRecipeToShoppingList,
            summary: "Add Pancakes ingredients to Weekly Shop",
            payload: .addRecipeToShoppingList(recipeName: "Pancakes", listName: "Weekly Shop")
        )

        #expect(validationReason(for: store.validate(action)) == "No recipe named Pancakes was found.")
    }

    @MainActor
    @Test func validationRejectsUnsupportedGenericAction() {
        let store = AppStore()
        let action = ProposedAction(
            type: .deleteMemory,
            summary: "Delete memory",
            payload: .generic(description: "Delete memory")
        )

        #expect(validationReason(for: store.validate(action)) == "Unsupported AI action.")
    }

    @MainActor
    @Test func chatHistoryPreservesProposedActionsAndActivityTagsInAIMessages() {
        let store = AppStore()
        let sessionID = store.ensureDefaultChatSession()
        let viewModel = ChatViewModel(appStore: store)

        let userMsg1 = ChatMessage(role: .user, content: .text("Add milk to my list"))
        let proposedAction = ProposedAction(
            type: .addShoppingListItem,
            summary: "Add Milk to Weekly Shop",
            payload: .addShoppingListItem(listName: "Weekly Shop", productName: "Milk", quantity: "1", notes: nil)
        )
        let assistantMsg1 = ChatMessage(role: .assistant, content: .proposedActions(intro: "I can help with that.", actions: [proposedAction], memoryProposals: []))
        let userMsg2 = ChatMessage(role: .user, content: .text("Now add eggs"))

        store.appendMessage(userMsg1, to: sessionID)
        store.appendMessage(assistantMsg1, to: sessionID)
        store.appendMessage(userMsg2, to: sessionID)

        let aiMessages = viewModel.buildAIMessages(for: sessionID)

        #expect(aiMessages.count == 3)
        #expect(aiMessages[0].role == .user)
        #expect(aiMessages[0].content == "Add milk to my list")

        #expect(aiMessages[1].role == .assistant)
        #expect(aiMessages[1].content.contains("I can help with that."))
        #expect(aiMessages[1].content.contains("[Proposed action: Add Milk to Weekly Shop]"))

        #expect(aiMessages[2].role == .user)
        #expect(aiMessages[2].content == "Now add eggs")
    }

    @MainActor
    @Test func chatHistoryPreservesCompletedActivityTagsInAIMessages() {
        let store = AppStore()
        let sessionID = store.ensureDefaultChatSession()
        let viewModel = ChatViewModel(appStore: store)

        let tag = ActivityTag(
            actionType: .addShoppingListItem,
            summary: "Added Milk to Weekly Shop",
            affectedRecordIDs: []
        )
        let assistantMsg = ChatMessage(role: .assistant, content: .activityTags([tag]))

        store.appendMessage(assistantMsg, to: sessionID)

        let aiMessages = viewModel.buildAIMessages(for: sessionID)

        #expect(aiMessages.count == 1)
        #expect(aiMessages[0].role == .assistant)
        #expect(aiMessages[0].content.contains("[Completed action: Added Milk to Weekly Shop]"))
    }

    private func validationReason(for result: ValidationResult) -> String? {
        if case .invalid(let reason) = result {
            return reason
        }
        return nil
    }

}
