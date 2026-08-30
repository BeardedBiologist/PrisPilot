import Foundation
import Testing
@testable import PrisPilot

@MainActor
struct ValidatorTests {

    // MARK: - Helpers

    private func invalidReason(for result: ValidationResult) -> String? {
        if case .invalid(let reason) = result { return reason }
        return nil
    }

    private func warningMessage(for result: ValidationResult) -> String? {
        if case .warning(let message) = result { return message }
        return nil
    }

    private func clarificationQuestion(for result: ValidationResult) -> String? {
        if case .requiresClarification(let question) = result { return question }
        return nil
    }

    // MARK: - Price Observation Validation

    @Test func validateCreatePriceBlankProductNameIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price",
            payload: .createPriceObservation(
                productName: "",
                storeBranchName: "Kiwi Pindsle",
                price: 29.90,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Price needs a product name.")
    }

    @Test func validateCreatePriceBlankStoreNameIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "",
                price: 29.90,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Price needs a store branch.")
    }

    @Test func validateCreatePriceZeroPriceIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: 0,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Price must be greater than zero.")
    }

    @Test func validateCreatePriceExcessivePriceIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: 200_000,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Price is outside the expected grocery range.")
    }

    @Test func validateCreatePriceZeroQuantityIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: 29.90,
                quantity: 0,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Quantity must be greater than zero.")
    }

    @Test func validateCreatePriceQuantityWithoutUnitIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: 29.90,
                quantity: 1,
                unit: nil,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Quantity needs a unit such as g, kg, ml, l, stk, or pk.")
    }

    @Test func validateCreatePriceFutureDateIsInvalid() {
        let store = AppStore()
        let futureDate = Date(timeIntervalSinceNow: 60 * 60 * 48)
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "Milk",
                storeBranchName: "Kiwi Pindsle",
                price: 29.90,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: futureDate
            )
        )
        #expect(invalidReason(for: store.validate(action)) == "Price date cannot be more than one day in the future.")
    }

    @Test func validateCreatePriceAmbiguousProductRequiresClarification() {
        let store = AppStore()
        store.products = [Product(name: "Whole Milk"), Product(name: "Skim Milk")]
        let action = ProposedAction(
            type: .createPriceObservation,
            summary: "Add price: Milk",
            payload: .createPriceObservation(
                productName: "milk",
                storeBranchName: "Kiwi Pindsle",
                price: 29.90,
                quantity: 1,
                unit: .litres,
                isPromotion: false,
                date: Date()
            )
        )
        #expect(clarificationQuestion(for: store.validate(action)) != nil)
    }

    // MARK: - Update Price Validation

    @Test func validateUpdatePriceBlankProductIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .updatePriceObservation,
            summary: "Update price",
            payload: .updatePriceObservation(productName: "", storeBranchName: nil, newPrice: 25.00, newQuantity: nil, newUnit: nil)
        )
        #expect(invalidReason(for: store.validate(action)) == "Price update needs a product name.")
    }

    @Test func validateUpdatePriceNoNewDataIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .updatePriceObservation,
            summary: "Update price",
            payload: .updatePriceObservation(productName: "Milk", storeBranchName: nil, newPrice: nil, newQuantity: nil, newUnit: nil)
        )
        #expect(invalidReason(for: store.validate(action)) == "Price update needs a new price or quantity.")
    }

    // MARK: - Shopping List Item Validation

    @Test func validateAddShoppingListItemBlankListNameIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .addShoppingListItem,
            summary: "Add Milk",
            payload: .addShoppingListItem(listName: "", productName: "Milk", quantity: "1", notes: nil)
        )
        #expect(invalidReason(for: store.validate(action)) == "List item needs a shopping list name.")
    }

    @Test func validateAddShoppingListItemBlankProductNameIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .addShoppingListItem,
            summary: "Add item",
            payload: .addShoppingListItem(listName: "Weekly Shop", productName: "", quantity: "1", notes: nil)
        )
        #expect(invalidReason(for: store.validate(action)) == "List item needs a product name.")
    }

    @Test func validateRemoveShoppingListItemMissingTargetIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .removeShoppingListItem,
            summary: "Remove Caviar from Weekly Shop",
            payload: .removeShoppingListItem(listName: "Weekly Shop", productName: "Caviar")
        )
        #expect(invalidReason(for: store.validate(action)) == "No item named Caviar was found on Weekly Shop.")
    }

    @Test func validateCompleteShoppingListItemMissingTargetIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .completeShoppingListItem,
            summary: "Mark Caviar bought",
            payload: .completeShoppingListItem(listName: "Weekly Shop", productName: "Caviar", isCompleted: true)
        )
        #expect(invalidReason(for: store.validate(action)) == "No item named Caviar was found on Weekly Shop.")
    }

    // MARK: - Shopping List Validation

    @Test func validateCreateShoppingListDuplicateIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createShoppingList,
            summary: "Create list: Weekly Shop",
            payload: .createShoppingList(name: "Weekly Shop")
        )
        #expect(invalidReason(for: store.validate(action)) == "A shopping list named Weekly Shop already exists.")
    }

    // MARK: - Recipe Validation

    @Test func validateAddRecipeToListNoRecipeIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .addRecipeToShoppingList,
            summary: "Add Pancakes to Weekly Shop",
            payload: .addRecipeToShoppingList(recipeName: "Pancakes", listName: "Weekly Shop")
        )
        #expect(invalidReason(for: store.validate(action)) == "No recipe named Pancakes was found.")
    }

    // MARK: - Store Validation

    @Test func validateCreateStoreBlankChainIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createStore,
            summary: "Add store",
            payload: .createStore(chainName: "", branchName: "Sentrum", address: nil, isEnabled: true)
        )
        #expect(invalidReason(for: store.validate(action)) == "Store needs a chain name.")
    }

    @Test func validateCreateStoreBlankBranchIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .createStore,
            summary: "Add store",
            payload: .createStore(chainName: "Kiwi", branchName: "", address: nil, isEnabled: true)
        )
        #expect(invalidReason(for: store.validate(action)) == "Store needs a branch name.")
    }

    // MARK: - App Setting Validation

    @Test func validateChangeSettingUnknownKeyIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .changeAppSetting,
            summary: "Change unknown setting",
            payload: .changeAppSetting(key: "unknownKey", value: "someValue")
        )
        #expect(invalidReason(for: store.validate(action)) == "Unknown app setting: unknownKey.")
    }

    @Test func validateChangeSettingBadMaxStoreCountIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .changeAppSetting,
            summary: "Set max store count",
            payload: .changeAppSetting(key: "maxStoreCount", value: "99")
        )
        #expect(invalidReason(for: store.validate(action)) == "Maximum store count must be a number from 1 to 5.")
    }

    @Test func validateChangeSettingValidMaxStoreCountIsValid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .changeAppSetting,
            summary: "Set max store count",
            payload: .changeAppSetting(key: "maxStoreCount", value: "3")
        )
        if case .valid = store.validate(action) {
            // pass
        } else {
            Issue.record("Expected .valid for maxStoreCount = 3")
        }
    }

    @Test func validateChangeSettingBadCheapestDefinitionIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .changeAppSetting,
            summary: "Change cheapest definition",
            payload: .changeAppSetting(key: "cheapestDefinition", value: "nonsense")
        )
        #expect(invalidReason(for: store.validate(action)) == "Unknown cheapest strategy: nonsense.")
    }

    @Test func validateChangeSettingNegativeMinimumSavingsIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .changeAppSetting,
            summary: "Set minimum savings",
            payload: .changeAppSetting(key: "minimumSavings", value: "-50")
        )
        #expect(invalidReason(for: store.validate(action)) == "minimumSavings must be a non-negative number.")
    }

    @Test func validateChangeSettingCommunityPricingYieldsWarning() {
        let store = AppStore()
        let action = ProposedAction(
            type: .changeAppSetting,
            summary: "Enable community pricing",
            payload: .changeAppSetting(key: "communityPricingEnabled", value: "true")
        )
        #expect(warningMessage(for: store.validate(action)) != nil)
    }

    // MARK: - Generic / Unsupported Action

    @Test func validateGenericPayloadIsInvalid() {
        let store = AppStore()
        let action = ProposedAction(
            type: .deleteMemory,
            summary: "Delete memory",
            payload: .generic(description: "Delete memory")
        )
        #expect(invalidReason(for: store.validate(action)) == "Unsupported AI action.")
    }
}
