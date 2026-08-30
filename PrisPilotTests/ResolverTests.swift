import Foundation
import Testing
@testable import PrisPilot

@MainActor
struct ResolverTests {

    // MARK: - Shopping List Resolution

    @Test func resolveShoppingListExactMatch() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        guard case .resolved(let list) = resolver.shoppingList(named: "Weekly Shop", allowCreate: false) else {
            Issue.record("Expected .resolved for exact shopping list name")
            return
        }
        #expect(list.name == "Weekly Shop")
    }

    @Test func resolveShoppingListCaseInsensitiveExact() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        guard case .resolved(let list) = resolver.shoppingList(named: "weekly shop", allowCreate: false) else {
            Issue.record("Expected .resolved for lowercase exact match")
            return
        }
        #expect(list.name == "Weekly Shop")
    }

    @Test func resolveShoppingListGenericReferenceTheList() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .resolved = resolver.shoppingList(named: "the list", allowCreate: false) {
            // pass – single active list resolves via generic reference
        } else {
            Issue.record("Expected .resolved for generic reference 'the list'")
        }
    }

    @Test func resolveShoppingListGenericReferenceMyList() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .resolved = resolver.shoppingList(named: "my list", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .resolved for generic reference 'my list'")
        }
    }

    @Test func resolveShoppingListLooseSubstringMatch() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        // "Weekly" is a substring of "weekly shop" after normalization
        guard case .resolved(let list) = resolver.shoppingList(named: "Weekly", allowCreate: false) else {
            Issue.record("Expected .resolved via loose substring match")
            return
        }
        #expect(list.name == "Weekly Shop")
    }

    @Test func resolveShoppingListAmbiguousReturnsAllCandidates() {
        let store = AppStore()
        store.shoppingLists.append(ShoppingList(name: "Taco Night"))
        store.shoppingLists.append(ShoppingList(name: "Taco Weekend"))
        let resolver = AIEntityResolver(appStore: store)
        guard case .ambiguous(let candidates) = resolver.shoppingList(named: "Taco", allowCreate: false) else {
            Issue.record("Expected .ambiguous for 'Taco' matching two lists")
            return
        }
        #expect(candidates.count == 2)
    }

    @Test func resolveShoppingListMissingWhenNotFound() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .missing = resolver.shoppingList(named: "Nonexistent List XYZ", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .missing for unknown shopping list name")
        }
    }

    @Test func resolveShoppingListCreatableWhenAllowCreate() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .creatable = resolver.shoppingList(named: "Brand New List", allowCreate: true) {
            // pass
        } else {
            Issue.record("Expected .creatable when list doesn't exist and allowCreate is true")
        }
    }

    // MARK: - Product Resolution

    @Test func resolveProductExactNameMatch() {
        let store = AppStore()
        store.products = [Product(name: "Whole Milk")]
        let resolver = AIEntityResolver(appStore: store)
        guard case .resolved(let p) = resolver.product(named: "Whole Milk", allowCreate: false) else {
            Issue.record("Expected .resolved for exact product name")
            return
        }
        #expect(p.name == "Whole Milk")
    }

    @Test func resolveProductByAlias() {
        let store = AppStore()
        var milk = Product(name: "Whole Milk")
        milk.aliases = ["melk", "heile melk"]
        store.products = [milk]
        let resolver = AIEntityResolver(appStore: store)
        guard case .resolved(let p) = resolver.product(named: "melk", allowCreate: false) else {
            Issue.record("Expected .resolved via product alias")
            return
        }
        #expect(p.name == "Whole Milk")
    }

    @Test func resolveProductBySecondAlias() {
        let store = AppStore()
        var beef = Product(name: "Minced Beef")
        beef.aliases = ["kjøttdeig", "mince"]
        store.products = [beef]
        let resolver = AIEntityResolver(appStore: store)
        if case .resolved(let p) = resolver.product(named: "kjøttdeig", allowCreate: false) {
            #expect(p.name == "Minced Beef")
        } else {
            Issue.record("Expected .resolved via second alias")
        }
    }

    @Test func resolveProductLooseWordMatch() {
        let store = AppStore()
        store.products = [Product(name: "Minced Beef")]
        let resolver = AIEntityResolver(appStore: store)
        // "beef" word-matches "Minced Beef" via looselyMatchesProductName
        if case .resolved = resolver.product(named: "beef", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .resolved via loose word match")
        }
    }

    @Test func resolveProductAmbiguousReturnsMultipleCandidates() {
        let store = AppStore()
        store.products = [Product(name: "Whole Milk"), Product(name: "Skim Milk")]
        let resolver = AIEntityResolver(appStore: store)
        // "milk" Jaccard-matches both products at 50% threshold
        guard case .ambiguous(let candidates) = resolver.product(named: "milk", allowCreate: false) else {
            Issue.record("Expected .ambiguous for 'milk' matching two milk products")
            return
        }
        #expect(candidates.count == 2)
    }

    @Test func resolveProductMissingWhenNotFound() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .missing = resolver.product(named: "Beluga Caviar", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .missing for unknown product")
        }
    }

    @Test func resolveProductCreatableWhenAllowCreate() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .creatable = resolver.product(named: "New Brand Product", allowCreate: true) {
            // pass
        } else {
            Issue.record("Expected .creatable for unknown product with allowCreate: true")
        }
    }

    // MARK: - Store Branch Resolution

    @Test func resolveStoreBranchByExactDisplayName() {
        let store = AppStore()
        _ = store.createStoreBranch(chainName: "Kiwi", branchName: "Pindsle")
        let resolver = AIEntityResolver(appStore: store)
        guard case .resolved(let b) = resolver.storeBranch(named: "Kiwi Pindsle", allowCreate: false) else {
            Issue.record("Expected .resolved by exact display name 'Kiwi Pindsle'")
            return
        }
        #expect(b.chainName == "Kiwi")
        #expect(b.name == "Pindsle")
    }

    @Test func resolveStoreBranchByChainNameSingleBranch() {
        let store = AppStore()
        _ = store.createStoreBranch(chainName: "Rema 1000", branchName: "Bjørvika")
        let resolver = AIEntityResolver(appStore: store)
        if case .resolved = resolver.storeBranch(named: "Rema 1000", allowCreate: false) {
            // pass – single branch matches chain name
        } else {
            Issue.record("Expected .resolved when chain name uniquely identifies one branch")
        }
    }

    @Test func resolveStoreBranchAmbiguousMultipleBranchesSameChain() {
        let store = AppStore()
        _ = store.createStoreBranch(chainName: "Kiwi", branchName: "Pindsle")
        _ = store.createStoreBranch(chainName: "Kiwi", branchName: "Majorstuen")
        let resolver = AIEntityResolver(appStore: store)
        guard case .ambiguous(let candidates) = resolver.storeBranch(named: "Kiwi", allowCreate: false) else {
            Issue.record("Expected .ambiguous when two Kiwi branches exist")
            return
        }
        #expect(candidates.count == 2)
    }

    @Test func resolveStoreBranchMissingWhenNoBranches() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .missing = resolver.storeBranch(named: "Bunnpris Sentrum", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .missing when no branches exist")
        }
    }

    @Test func resolveStoreBranchCreatableWhenAllowCreate() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .creatable = resolver.storeBranch(named: "Bunnpris Sentrum", allowCreate: true) {
            // pass
        } else {
            Issue.record("Expected .creatable for unknown branch with allowCreate: true")
        }
    }

    // MARK: - Recipe Resolution

    @Test func resolveRecipeExactTitleMatch() {
        let store = AppStore()
        store.recipes = [Recipe(title: "Taco Night")]
        let resolver = AIEntityResolver(appStore: store)
        guard case .resolved(let r) = resolver.recipe(named: "Taco Night", allowCreate: false) else {
            Issue.record("Expected .resolved for exact recipe title")
            return
        }
        #expect(r.title == "Taco Night")
    }

    @Test func resolveRecipeLooseSubstringMatch() {
        let store = AppStore()
        store.recipes = [Recipe(title: "Spaghetti Bolognese")]
        let resolver = AIEntityResolver(appStore: store)
        // "spaghetti" is a substring of normalized "spaghetti bolognese"
        if case .resolved = resolver.recipe(named: "spaghetti", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .resolved via loose recipe title match")
        }
    }

    @Test func resolveRecipeMissingWhenNoRecipes() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .missing = resolver.recipe(named: "Beef Wellington", allowCreate: false) {
            // pass
        } else {
            Issue.record("Expected .missing for unknown recipe")
        }
    }

    @Test func resolveRecipeCreatableWhenAllowCreate() {
        let store = AppStore()
        let resolver = AIEntityResolver(appStore: store)
        if case .creatable = resolver.recipe(named: "Pasta Carbonara", allowCreate: true) {
            // pass
        } else {
            Issue.record("Expected .creatable for unknown recipe with allowCreate: true")
        }
    }

    // MARK: - Memory Resolution

    @Test func resolveMemoryWithSufficientWordOverlap() {
        let store = AppStore()
        let memory = AIMemory(summary: "Prefers organic milk when available", category: .preference)
        store.memories = [memory]
        let resolver = AIEntityResolver(appStore: store)
        // "organic milk available" shares 3 of 4 words → overlap > 50%
        if case .resolved = resolver.memory(matching: "organic milk available") {
            // pass
        } else {
            Issue.record("Expected .resolved when memory shares enough words with query")
        }
    }

    @Test func resolveMemoryMissingWithNoOverlap() {
        let store = AppStore()
        let memory = AIMemory(summary: "Prefers organic milk when available", category: .preference)
        store.memories = [memory]
        let resolver = AIEntityResolver(appStore: store)
        if case .missing = resolver.memory(matching: "nut allergy") {
            // pass
        } else {
            Issue.record("Expected .missing when memory has no word overlap with query")
        }
    }
}
