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

    private func validationReason(for result: ValidationResult) -> String? {
        if case .invalid(let reason) = result {
            return reason
        }
        return nil
    }

}
