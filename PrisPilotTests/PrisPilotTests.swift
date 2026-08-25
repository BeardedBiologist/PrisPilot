//
//  PrisPilotTests.swift
//  PrisPilotTests
//
//  Created by Joshua James O’Connor on 20/08/2026.
//

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

}
