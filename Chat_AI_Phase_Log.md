# PrisPilot Chat AI Phase Log

Last updated: 2026-08-30

## Purpose

This is the living implementation log for `Chat_AI_Phased_Execution_Plan.md`.

At the end of each phase, update the matching section with:

- date completed
- files changed
- work completed
- verification performed
- behavior improvements observed
- remaining risks or bugs
- recommended next step

Do not treat a phase as complete just because code was written. A phase is complete when the app compiles or the blocker is documented, and the acceptance criteria for that phase are either met or explicitly deferred.

## Current Phase Status

| Phase | Name | Status | Completed Date | Notes |
|---|---|---|---|---|
| 0 | Baseline And Failure Inventory | Complete | 2026-08-30 | Initial baseline from current implementation and known test concerns. Add more live failures as they appear. |
| 1 | Stabilize Existing Action Path | Ready for manual testing | 2026-08-30 | Build passed. Automated tests deferred until the end by request. |
| 2 | Rich Context Builder | Ready for manual testing | 2026-08-30 | Build passed. Automated tests deferred until the end by request. |
| 3 | Entity Resolver And Clarification | Ready for manual testing | 2026-08-30 | Build passed. Automated tests deferred until the end by request. |
| 4 | Draft Intent Planner | Ready for manual testing | 2026-08-30 | Build passed. Legacy AIResponse compatibility kept. Automated tests deferred until the end by request. |
| 5 | Semantic Validator | Ready for manual testing | 2026-08-30 | Build passed. Expanded no-op and type/payload validation. Automated tests deferred until the end by request. |
| 6 | Execution Results And Undo | Not started |  |  |
| 7 | Proposal Editing And Safer Review UI | Not started |  |  |
| 8 | Regression Harness | Not started |  |  |
| 9 | Provider And Prompt Versioning | Not started |  |  |
| 10 | Advanced Chat UX | Not started |  |  |

## Phase 0: Baseline And Failure Inventory

### Status

Complete for the initial baseline pass. Keep adding real live-testing failures here as they are found.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Capture current bad chat behaviors before changing implementation.

### Files Changed

- `Chat_AI_Phase_Log.md`

### Work Completed

- Reviewed `Chat_AI_Experience_Improvement_Plan.md`, `Chat_AI_Phased_Execution_Plan.md`, and the current chat implementation assumptions already captured in those files.
- Converted the likely and observed AI consistency problems into a concrete baseline failure inventory.
- Identified the first code-phase priorities for Phase 1.

### Failure Inventory

| Prompt | Expected Behavior | Actual Behavior | Failure Category | AI Mode | Priority |
|---|---|---|---|---|---|
| `Add milk to the list.` with two active lists | Ask which list to use before proposing an action. | Current path can let the model choose/default a list name. | Bad default / poor clarification | Live | High |
| `Add milk to the weekly list.` when no weekly list exists | Ask whether to create `Weekly Shop` or choose an existing list. | Existing executor may create a list if the model sends `Weekly Shop`. | Hallucinated record / implicit create | Live/Mock | High |
| `Delete Kiwi.` with multiple Kiwi branches | Ask which branch, or suggest disabling instead of deleting. | Model can propose a delete by broad name; native lookup may pick a match or no-op. | Wrong target / no-op approval | Live | High |
| `Move milk to Rema.` with multiple Rema branches | Ask which Rema branch. | Model may send a partial branch name that cannot resolve cleanly. | Ambiguous target | Live | High |
| `Remove milk from my list.` | Remove the item only from the intended list after resolving the list. | May target `Weekly Shop` or fail silently if product/list does not match. | Wrong target / no-op approval | Live/Mock | High |
| `Mark milk bought.` when milk appears on several active lists | Ask which list/item. | Current action shape requires list name, so the model may guess. | Poor clarification | Live/Mock | High |
| `Actually that beef was 49.90.` after recording a price | Update the most recent relevant personal beef price. | Model may not have enough context to connect `that beef` to the previous observation. | Missing context / wrong target | Live | High |
| `Delete the price I just added for beef.` | Delete the recent personal price observation and show activity/undo where possible. | Name-only resolution may fail or hit the wrong recent observation. | Fragile resolution | Live | High |
| `Rema has milk for 22.50 per liter.` | Record a price for milk at a resolved Rema branch or ask which branch. | If multiple Rema branches exist, the model may invent or omit branch detail. | Ambiguous store | Live | High |
| `Save a pancake recipe for 4 with flour, milk, eggs, and butter.` | Create a recipe with servings and structured ingredients. | Current `createRecipe` payload only supports title and servings. | Missing action capability | Live | High |
| `Add all pancake ingredients to Saturday breakfast list.` | Require an existing pancake recipe and target list, then add ingredients. | Missing recipe/list can lead to no-op execution instead of clarification. | No-op approval / missing precondition | Live | High |
| `Plan tacos for dinner every Tuesday this month.` | Expand recurring dates or ask to confirm a multi-date plan. | Current `setMealPlanSlot` supports one date at a time; model may under-propose. | Incomplete action group | Live | Medium |
| `Build my shopping list from next week's meal plan.` | Resolve next week from current date and generate from recipe slots only. | Model/context may not include enough meal plan state or exact date grounding. | Missing context / date ambiguity | Live | Medium |
| `Add Adams Matkasse for next week.` | Ask for missing details or propose clear defaults. | Current executor defaults meal count and servings without necessarily showing assumptions. | Hidden default | Live | Medium |
| `Add fish tacos to that matkasse.` | Resolve `that matkasse` from recent context or ask. | Current action requires provider name; model may guess or fail. | Conversation reference failure | Live | Medium |
| `Forget that.` after discussing a memory | Resolve the referenced memory from conversation context or ask which memory. | Current delete-memory support is incomplete and can degrade to generic/no-op behavior. | Fragile memory deletion | Live/Mock | High |
| `Remember my child has a peanut allergy.` | Propose a health/sensitive memory with explicit approval. | Current validation does not enforce sensitive/health approval semantics. | Unsafe memory | Live/Mock | High |
| `Use at most two stores unless savings are over 100 kr.` | Propose typed settings changes for max store count and minimum savings. | Model may produce string settings; native validation does not range/type check deeply. | Weak settings validation | Live | Medium |
| `Compare Kiwi and Rema prices for my taco list and tell me a joke.` | Handle the price comparison portion and refuse/ignore the joke. | Scope policy/model may over-refuse or answer the out-of-scope portion. | Partial-scope handling | Live | Medium |
| `Write Swift code for a button.` | Refuse as out of scope. | Local scope policy should catch this; needs regression coverage. | Scope regression risk | Live/Mock | Medium |

### Verification

- Documentation-only baseline pass; no build required.
- Read the current plans and mapped their risks to specific prompts.
- No live Gemini prompts were run during this pass.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| At least 15 representative chat failures are documented. | Yes | 20 baseline failure prompts documented. |
| Each failure has an expected behavior statement. | Yes | Each row includes expected behavior and likely/current actual behavior. |
| Phase 1 priorities are based on observed failures. | Yes | Priorities are derived from the current implementation risks and the user's testing concern that chat does some things right and some things wrong. |

### Remaining Risks

- This baseline is partly implementation-inferred because the user's exact live-testing failure transcripts are not yet captured.
- Some failures may be model-dependent and only reproducible with a live Gemini key.
- Mock AI behavior is intentionally simplistic, so it may hide live AI failure modes.

### Next Step

- Proceed to Phase 1: stabilize the existing action path with tighter prompt rules, basic native validation, and visible failure handling before introducing the larger draft-intent architecture.

## Phase 1: Stabilize Existing Action Path

### Status

Ready for manual testing. Stop here before Phase 2.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Make the current Gemini function-call to `ProposedAction` flow safer without a large architecture rewrite.

### Files Changed

- `Models/ProposedAction.swift`
- `Store/AppStore.swift`
- `Services/GeminiAIService.swift`
- `Features/Chat/ChatViewModel.swift`
- `PrisPilotTests/PrisPilotTests.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Added `ProposedActionType.expectsAffectedRecordIDs` so chat approval can distinguish real record-changing actions from valid recordless actions such as settings and meal-slot changes.
- Added first-pass semantic validation in `AppStore.validate(_:)` after permission checks and before destructive-action warnings.
- Added validation for empty names, invalid prices, invalid quantities, missing existing targets, duplicate lists/products/recipes/stores, unsupported generic actions, invalid setting keys/values, missing meal-plan data, and missing matkasse targets.
- Updated chat action approval to mark actions as failed when execution throws or returns no affected records for actions that should affect records.
- Updated all-terminal proposal collapsing so failed actions remain visible instead of being replaced by empty activity tags.
- Added a fallback assistant message when the AI returns neither text nor proposed actions.
- Tightened Gemini chat prompt rules around exact turn outcomes, ambiguity, default list behavior, store branch invention, existing recipes, and durable memories.
- Reduced chat generation temperature from `0.3` to `0.2` for more stable behavior.
- Added focused unit-test coverage for key validation failures. Per user request, automated tests are deferred until the end and were not completed in this phase.

### Prompt Rules Changed

- Each chat turn should be answer-only, clarification-only, proposal-only, refusal-only, or failure explanation.
- Ask one concise clarification question when list/product/store/recipe/matkasse/memory/date targets are ambiguous.
- Do not default to `Weekly Shop` when `the list` could mean multiple lists.
- Do not invent store branches when a specific branch is needed.
- Do not create a recipe when the user asks for an existing recipe's ingredients.
- Only propose memory for durable preferences, habits, restrictions, allergies, or decision rules.

### Validation Rules Added

| Domain | Rules Added | Deferred Rules |
|---|---|---|
| Shopping | Non-empty list/item fields, duplicate list detection, existing list/item checks, valid status values, optimization preconditions. | Full ambiguity resolver and better loose item matching. |
| Prices | Positive/plausible price, positive quantity, unit required with quantity, existing personal observation checks, community price existence for flags. | Store ambiguity resolver and promotion end-date handling. |
| Products | Non-empty names, duplicate create detection, existing target checks, merge self-check, alias existence checks, barcode non-empty check. | Barcode format validation and stronger duplicate similarity. |
| Recipes | Non-empty title, positive servings, duplicate create detection, existing recipe checks. | Full recipe creation with ingredients/instructions. |
| Meal Planning | Slot content checks, existing recipe check, existing slot check for removal, recipe-slot presence before building shopping list. | Recurrence expansion and overwrite warnings. |
| Matkasse | Provider required, positive meals/servings/price, existing box/meal checks. | Provider+week disambiguation. |
| Stores | Chain/branch required, duplicate branch detection, existing branch checks for edit/delete/enable/disable. | Multi-branch clarification and dependency warnings before delete. |
| Settings | Known key allowlist, typed/ranged values for strategy/store count/money/bool settings, community pricing warning. | Country/currency cascade validation. |
| Memory | Non-empty summary, duplicate memory check, warning for sensitive/health memory, generic memory delete blocked as unsupported. | First-class update/delete memory payloads and confirmation UX. |

### Manual Prompts To Retest

| Prompt | Before | Expected After | Result |
|---|---|---|---|
| `Add milk to the list.` with multiple lists | Model could guess/default. | Gemini should ask which list more often; full deterministic clarification waits for Phase 3. | Needs manual test |
| `Remove milk from Weekly Shop.` when milk is missing | Could approve and collapse to empty activity result. | Proposal/action should fail visibly with `No item named Milk was found on Weekly Shop.` | Needs manual test |
| `I paid 0 kr for milk at Kiwi.` | Could produce invalid price proposal. | Proposal should be blocked with `Price must be greater than zero.` | Needs manual test |
| `Add Pancakes ingredients to Weekly Shop.` when no recipe exists | Could no-op. | Proposal should fail validation with `No recipe named Pancakes was found.` | Needs manual test |
| `Forget that.` | Could become unsupported generic delete-memory action. | Unsupported generic action should fail visibly. | Needs manual test |
| `Use at most two stores unless savings are over 100 kr.` | Weak string setting validation. | Setting payloads should validate typed values/ranges before approval. | Needs manual test |

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on changed Swift files.
- `Store/AppStore.swift` has no new errors; it still reports three pre-existing actor-isolation warnings around onboarding/welcome message creation.
- `Features/Chat/ChatViewModel.swift`: no issues found.
- `Models/ProposedAction.swift`: no issues found.
- `Services/GeminiAIService.swift`: no issues found.
- `PrisPilotTests/PrisPilotTests.swift`: no issues found after adding `Foundation`.
- Ran `BuildProject`: project built successfully.
- Started `RunAllTests`, but the tool timed out and the user requested leaving automated tests for the end. No test result is claimed for this phase.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Ambiguous requests are less likely to become guessed proposals. | Partial | Prompt now instructs clarification, but deterministic native clarification is Phase 3. |
| Invalid actions cannot be approved. | Partial | Many obvious invalid payloads now fail validation; full coverage is Phase 5. |
| Execution failures are visible to the user. | Yes | Failed actions remain in proposal cards with validation/failure reasons. |
| No approved action silently disappears. | Partial | Empty affected-record results now fail for record-affecting actions; broader execution result modeling is Phase 6. |
| Existing mock and live AI flows still compile. | Yes | Build passed. Manual behavior testing still needed. |

### Remaining Risks

- Validation still uses string-based lookups; robust ambiguity handling waits for `AIEntityResolver` in Phase 3.
- Some valid recordless actions may need better activity text because they do not produce affected record IDs.
- Memory update/delete is still not first-class in payloads.
- The prompt improvement reduces bad defaults but cannot guarantee them without native planning.
- Automated tests were added but not run to completion in this phase by request.

### Next Step

- Phase 2 was started next to add a richer bounded `AIContextBuilder` so Gemini can see enough app state to target existing records more reliably.

## Phase 2: Rich Context Builder

### Status

Ready for manual testing. Stop here before Phase 3.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Give the AI a compact but useful snapshot of app state for CRUD across all tabs.

### Files Changed

- `Models/AITypes.swift`
- `Services/AIContextBuilder.swift`
- `Features/Chat/ChatViewModel.swift`
- `Services/GeminiAIService.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Expanded `AIContext` with current date, timezone, locale summary, settings summary, shopping list summaries, product summaries, recent price summaries, recipe summaries, meal-plan summaries, matkasse summaries, and memory summaries.
- Added `AIContextBuilder` as a dedicated `@MainActor` service that builds bounded context from `AppStore`.
- Replaced inline `ChatViewModel.buildContext()` logic with `AIContextBuilder(appStore:).build()`.
- Updated Gemini's system prompt to include the richer context sections when present.
- Preserved existing `relevantMemories`, `availableShoppingLists`, `enabledStoreBranches`, `userPreferences`, and `currency` fields for compatibility with current mock/live AI flows.

### Context Fields Added

| Context Area | Added? | Limit/Selection Rule | Notes |
|---|---|---|---|
| Current date/timezone | Yes | One ISO date and current timezone identifier. | Gives the model exact grounding for `today`, `next week`, and meal planning. |
| Locale/country/currency | Yes | One compact summary. | Includes Norway/NOK/language/metric defaults from settings. |
| Shopping lists | Yes | 10 most recently created lists; 6 pending items per list. | Includes status, scope, planned date, pending/completed counts, store and estimate when present. |
| Products/aliases | Yes | First 30 products sorted by name; up to 4 aliases per product. | Includes category, default unit, aliases, and barcode presence. |
| Price observations | Yes | 20 most recent observations. | Includes product, store, price, package size when present, date, source, confidence, promotion/stale flags. |
| Recipes | Yes | First 15 recipes sorted by title; 5 ingredients per recipe. | Includes servings, scope, and ingredient summaries. |
| Meal plan | Yes | Current week and next week. | Includes date, meal type, content type/title, and leftover marker. |
| Matkasse | Yes | 10 boxes sorted by delivery week. | Includes provider, week, meal count, servings, price, and up to 5 meal titles. |
| Stores | Yes | 20 branches sorted by display name. | Includes enabled/disabled status, distance, and address when present. |
| Settings | Yes | Fixed set of key optimization/community settings. | Includes cheapest strategy, max stores, savings threshold, travel cost, visit cost, community pricing. |
| Memory | Yes | 12 active personal/household memories; household included only when household exists. | Includes summary, category, strength, scope, and sensitivity. |

### Privacy Notes

- Context remains local app data sent to the configured AI provider only when the user sends a chat message.
- Household memories are included only if a household exists, matching the previous context behavior.
- Sensitive memory summaries can still be included if saved and active; Phase 9/debug trace work should make redaction policy more explicit.
- The builder sends bounded summaries instead of full unbounded records.

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on changed Swift files:
  - `Models/AITypes.swift`: no issues found.
  - `Services/AIContextBuilder.swift`: no issues found.
  - `Features/Chat/ChatViewModel.swift`: no issues found.
  - `Services/GeminiAIService.swift`: no issues found.
- Ran `BuildProject`: project built successfully.
- Automated tests were not run, per user request to leave tests until the end.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Model can see enough state to target existing app records. | Partial | It now sees richer records across domains, but deterministic targeting still requires Phase 3 resolver work. |
| Context does not send unbounded full app state. | Yes | Lists, products, prices, recipes, meal plans, matkasse boxes, stores, and memories all have explicit limits. |
| Current date is always available. | Yes | `currentDateISO` and `timeZoneIdentifier` are included in every built context. |
| Context summaries are deterministic enough to test. | Partial | Builder output is deterministic for a fixed app state/date except date formatter timezone dependence; formal tests are deferred. |

### Remaining Risks

- Context is still string summaries, not structured IDs; model may still choose wrong names until Phase 3/4.
- The context builder uses broad fixed limits rather than relevance scoring from the user's latest message.
- More context can increase prompt size and latency for heavily populated app states.
- Sensitive memory redaction policy is not yet formalized.
- No automated tests were run in this phase by request.

### Next Step

- Phase 3 was started next to add `AIEntityResolver` and native clarification rules for ambiguous or missing targets.

## Phase 3: Entity Resolver And Clarification

### Status

Ready for manual testing. Stop here before Phase 4.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Move name matching and ambiguity decisions into native code.

### Files Changed

- `Services/AIEntityResolver.swift`
- `Models/ProposedAction.swift`
- `Features/Chat/ActionProposalView.swift`
- `Features/Chat/ChatViewModel.swift`
- `Store/AppStore.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Added `AIEntityResolver` with native resolution results: `resolved`, `ambiguous`, `missing`, and `creatable`.
- Added resolver support for shopping lists, shopping-list items, products, store branches, recipes, matkasse boxes, and memories.
- Added generic-list reference handling for values like `list`, `the list`, `my list`, `shopping list`, `grocery list`, and `handleliste`.
- Added exact, loose, alias, or partial matching where safe for each entity family.
- Added `ValidationResult.requiresClarification(question:)` and made it block approval like invalid validation.
- Updated `ActionProposalView` to display clarification validation messages if a mixed proposal reaches the UI.
- Updated `ChatViewModel.handleResponse` so clarification-only action responses become a normal assistant question instead of an action card.
- Integrated resolver ambiguity checks into `AppStore.validate(_:)` for list, item, product, store, recipe, matkasse, price, and memory-related actions.

### Resolver Rules Implemented

| Entity | Exact Match | Alias/Loose Match | Ambiguity Handling | Missing Handling |
|---|---|---|---|---|
| Shopping list | Yes | Partial name match; active/planned priority for generic references. | Returns a question with up to 4 list candidates. | Returns missing unless create is allowed. |
| Shopping item | Yes | Uses existing loose product-name matching. | Returns a question with matching item candidates. | Returns missing. |
| Product | Yes | Alias match and loose product-name match. | Returns a question with matching product candidates. | Returns missing or creatable depending on action. |
| Store branch | Yes | Chain-only and partial display-name matching. | Returns a question with branch candidates, useful for chain-only names like `Kiwi`. | Returns missing or creatable depending on action. |
| Recipe | Yes | Partial title matching. | Returns a question with recipe candidates. | Returns missing or creatable depending on action. |
| Meal-plan slot | Partial | Uses existing date+meal-type lookup for removal validation. | Full slot ambiguity not implemented yet. | Missing slot returns invalid validation. |
| Matkasse box | Yes | Partial provider matching. | Returns a question with provider plus delivery week candidates. | Returns missing or creatable depending on action. |
| Memory | Partial | Word-overlap matching against active memory summaries. | Returns a question with memory candidates. | Missing memory returns missing; first-class delete/update memory payloads still deferred. |

### Clarification Examples To Manually Verify

| Prompt | Expected Clarification | Result |
|---|---|---|
| `Add milk to the list.` with multiple active/planned lists | `Which shopping list do you mean: ...?` | Needs manual test |
| `Delete Kiwi.` with multiple Kiwi branches | `Which store branch do you mean: Kiwi ..., Kiwi ...?` | Needs manual test |
| `Move milk to Rema.` with multiple Rema branches | `Which store branch do you mean: Rema 1000 ..., Rema 1000 ...?` | Needs manual test |
| `Change pancakes to serve 6.` with multiple matching pancake recipes | `Which recipe do you mean: ...?` | Needs manual test |
| `Add fish tacos to Adams.` with multiple Adams boxes | `Which matkasse box do you mean: ...?` | Needs manual test |

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on changed Swift files:
  - `Services/AIEntityResolver.swift`: no issues found.
  - `Models/ProposedAction.swift`: no issues found.
  - `Features/Chat/ActionProposalView.swift`: no issues found.
  - `Features/Chat/ChatViewModel.swift`: no issues found.
  - `Store/AppStore.swift`: no new errors; same three pre-existing actor-isolation warnings around onboarding/welcome message creation remain.
- Ran `BuildProject`: project built successfully.
- Automated tests were not run, per user request to leave tests until the end.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Ambiguous list requests ask which list. | Partial | Native validation can now produce list clarification questions; full pending-clarification state is deferred. |
| Ambiguous store requests ask which branch. | Partial | Chain-only or partial store matches now clarify when multiple branches match. |
| Existing-record operations do not create missing records by accident. | Partial | Validation now blocks many missing existing-target operations before approval; execution helpers still use some string-based fallbacks until Phase 4/5. |
| Resolver behavior is unit-tested. | No | Tests are deferred until the end by request. |

### Remaining Risks

- No persistent `PendingClarification` state yet; if the user answers a clarification, the next message is still handled as a normal turn. That belongs with Phase 4 draft intent planning.
- Resolver returns candidate labels but does not yet rewrite action payloads to canonical names or IDs before execution.
- Execution still uses older private string lookup helpers, so validation and execution can drift in edge cases until Phase 4/5.
- Ambiguity detection depends on what Gemini puts in the function-call arguments; a wrong but exact model guess can still pass until draft planning exists.
- Automated tests were not run in this phase by request.

### Next Step

- Stop here for manual review/testing.
- If this phase looks stable, continue to Phase 4: add draft intent models and planner so model output stops mapping directly to executable proposals.

## Phase 4: Draft Intent Planner

### Status

Ready for manual testing. Stop here before Phase 5.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Convert provider output into draft intent before native planning creates proposals.

### Files Changed

- `Models/AIIntentModels.swift`
- `Services/AIActionPlanner.swift`
- `Services/GeminiAIService.swift`
- `Features/Chat/ChatViewModel.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Added provider-neutral draft intent models: `AITurnOutcome`, `AIClarificationRequest`, `AIDraftAction`, `AIIntentDraft`, and `AIPlannedTurn`.
- Added `AIActionPlanner` as the single native place that decides whether a provider response becomes an answer, clarification, proposal, refusal, or failure.
- Moved proposal validation out of `ChatViewModel.handleResponse` and into the planner.
- Preserved existing `AIService.send(...) -> AIResponse` compatibility so mock AI, scope policy, onboarding, and existing Gemini function calls keep working.
- Updated Gemini response parsing so parsed text, function-call actions, and memory proposals are wrapped as an `AIIntentDraft` before returning through the legacy `AIResponse` shape.
- Added lightweight turn-outcome inference for legacy Gemini output: actions/memories become proposals, question-like text becomes clarification, scope-refusal text becomes refusal, empty output becomes failure, and remaining text becomes answer.

### Draft Schema Introduced

- Schema version: `2026-08-30.phase4.legacy-function-calls`
- Prompt version: existing Gemini prompt retained from Phase 1/2.
- Compatibility mode: legacy Gemini function calls are wrapped into `AIIntentDraft`; the strict single JSON `proposePrisPilotTurn` schema is deferred.

### Remaining Direct Parsing Paths

- `AIService` still returns `AIResponse` publicly for compatibility.
- `MockAIService` and `AIScopePolicy` still construct `AIResponse` directly, then pass through `AIActionPlanner` in chat.
- `GeminiAIService.parseFunctionCall(_:)` still maps each provider function call to `ProposedAction`; Phase 4 wraps that output in `AIDraftAction` but does not yet replace the function-call schema.
- Onboarding still consumes `OnboardingAIResult` directly and is not routed through the chat planner.

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on changed Swift files:
  - `Models/AIIntentModels.swift`: no issues found.
  - `Services/AIActionPlanner.swift`: no issues found.
  - `Services/GeminiAIService.swift`: no issues found.
  - `Features/Chat/ChatViewModel.swift`: no issues found.
- Ran `BuildProject`: project built successfully.
- Automated tests were not run, per user request to leave tests until the end.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Model output and app proposals are separate concepts. | Partial | New draft models exist, and Gemini wraps parsed output into a draft before returning compatibility `AIResponse`; provider function-call parsing still creates `ProposedAction` internally. |
| Same draft can become proposal, clarification, or invalid result based on app state. | Yes | `AIActionPlanner` validates draft actions with current `AppStore` state before choosing proposal, clarification, answer, or failure. |
| App state resolution happens before proposal display. | Yes | The planner calls `appStore.validate(_:)`, including Phase 3 resolver checks, before proposals reach `ChatViewModel` display. |
| Parser tests cover old and new output shapes. | No | Tests are deferred until the end by request; strict new output shape is not introduced yet. |

### Remaining Risks

- This is an architecture bridge, not the final provider contract. Gemini function calls still map to `ProposedAction` before being wrapped as draft actions.
- `AIClarificationRequest` is not persisted as pending chat state, so follow-up answers are still interpreted as normal turns.
- Draft actions do not yet carry canonical resolved entity IDs or rewritten payloads; validation can block ambiguity, but execution still uses string payloads.
- The planner currently treats memory proposals as proposal-worthy without deep memory-specific draft validation beyond existing approval flow.
- Automated tests were not run in this phase by request.

### Next Step

- Stop here for manual review/testing.
- If this phase looks stable, continue to Phase 5: extract or expand semantic validation so every `ProposedActionPayload` case has explicit native rules and known no-op risks are closed.

## Phase 5: Semantic Validator

### Status

Ready for manual testing. Stop here before Phase 6.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Give every supported action explicit native validation.

### Files Changed

- `Store/AppStore.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Added an action type/payload consistency gate before semantic validation. This blocks unsupported or mismatched AI actions before approval.
- Tightened price validation for future-dated observations, store-specific price updates, out-of-range update prices, and community price flags narrowed by store branch.
- Added explicit replacement-product validation for shopping-list substitutions, including blank replacement names, self-substitution, and ambiguous product matches.
- Added recipe update no-op detection and duplicate-title validation.
- Added meal-plan meal-type validation and blocked meal planning dates more than one year in the past.
- Added matkasse delivery-week sanity checks, upper bounds for meals/servings/price, duplicate meal checks, duplicate provider checks on update, and no-op update detection.
- Added store update no-op detection, duplicate branch validation after rename, and blocked enable/disable actions when the store is already in that state.
- Added helper checks for community observations and date sanity.

### Validation Coverage

| Payload Family | Coverage | Notes |
|---|---|---|
| Shopping lists/items | Covered | Existing list/item validation from Phase 3 now includes stronger substitution checks. |
| Prices | Covered | Product/store ambiguity, personal observation existence, community observation existence, positive/ranged values, and future-date checks are covered. |
| Products | Covered | Create/update/delete/merge/alias/barcode rules are explicit. Barcode format is still permissive. |
| Recipes | Covered | Create/update/delete and add-recipe-to-list preconditions are explicit. Recipe ingredients remain limited by current payload shape. |
| Meal planning | Covered | Slot content, recipe existence, meal type, old-date guard, remove-slot existence, and build-from-week preconditions are explicit. |
| Matkasse | Covered | Provider, target box, meal names, numeric ranges, duplicate meals, duplicate provider updates, and no-op updates are explicit. |
| Stores | Covered | Create/update/delete/enable/disable target and duplicate rules are explicit. |
| Settings | Covered | Known setting keys and typed/ranged values are explicit. |
| Memory | Partial | Create-memory validation is explicit. Update/delete memory action types are blocked by type/payload mismatch because typed payloads do not exist yet. |
| Household | Partial | Household action types are blocked by type/payload mismatch because typed household payloads do not exist yet. |

### Known No-Op Risks

- `changeAppSetting` intentionally returns no affected IDs, so chat treats it as a valid recordless action. Phase 6 should add structured execution results so settings can report a meaningful applied result.
- `setMealPlanSlot` and `removeMealPlanSlot` also return no affected IDs today. Phase 6 should return execution metadata or affected slot IDs where possible.
- `addRecipeToShoppingList` can still produce an empty execution result when the recipe exists but has no ingredients; this needs either validator access to recipe ingredient count or richer execution results.
- Product barcode validation only checks non-empty values, not barcode format or duplicate barcode ownership.
- Memory update/delete and household CRUD need first-class payload cases before they can be truly supported.

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on changed Swift files:
  - `Store/AppStore.swift`: no new errors; same three pre-existing actor-isolation warnings around onboarding/welcome message creation remain.
  - `Services/AIActionPlanner.swift`: no issues found.
  - `Models/ProposedAction.swift`: no issues found.
- Ran `BuildProject`: project built successfully.
- Automated tests were not run, per user request to leave tests until the end.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Every `ProposedActionPayload` case has explicit validation. | Yes | All current payload cases now pass through explicit semantic validation, including `.generic` as unsupported. |
| Invalid payloads show precise reasons. | Partial | Most covered failures now have domain-specific reasons; some unsupported action types still report type/payload mismatch until typed payloads exist. |
| High-risk actions show warnings even when valid. | Yes | Existing destructive-action warning still applies after semantic validation returns no blocking issue. |
| Silent no-op approval rate is zero for covered scenarios. | Partial | Known predictable no-ops are reduced, but structured execution results in Phase 6 are needed to close recordless actions and recipe-with-no-ingredients cases. |

### Remaining Risks

- `AppStore.validate(_:)` is getting large. It may be worth extracting `AIActionValidator` after Phase 6 clarifies execution-result needs.
- Validation and execution still both resolve from string payloads, so canonical ID rewriting remains unfinished.
- Date sanity limits are conservative and may need product decisions for historical price entry and old meal-plan edits.
- Automated tests were not run in this phase by request.

### Next Step

- Stop here for manual review/testing.
- If this phase looks stable, continue to Phase 6: add structured execution results so approvals can report what happened, explain no-op cases, and support broader undo.

## Phase 6: Execution Results And Undo

### Status

Not started.

### Start Date

TBD

### Completed Date

TBD

### Goal

Make action execution explicit, inspectable, and reversible where practical.

### Files Changed

- TBD

### Work Completed

- TBD

### Execution Result Model

- TBD

### Undo Coverage

| Operation | Undo Support | Notes |
|---|---|---|
| Create record | Partial | Existing simple ID-based undo exists for some actions. |
| Add item | Partial | Existing simple ID-based undo exists for some actions. |
| Update record | Not started |  |
| Delete record | Not started |  |
| Merge product | Not started |  |
| Meal-plan overwrite | Not started |  |

### Transaction Limitations

- TBD

### Verification

- TBD

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Approve-all reports partial failures clearly. | No |  |
| Dependent actions do not leave broken partial state. | No |  |
| Undo works for common create, add, update, and delete operations. | No |  |
| Activity tags remain accurate after execution. | No |  |

### Remaining Risks

- TBD

### Next Step

- TBD

## Phase 7: Proposal Editing And Safer Review UI

### Status

Not started.

### Start Date

TBD

### Completed Date

TBD

### Goal

Let users correct proposed actions before approval and make high-risk changes clearer.

### Files Changed

- TBD

### Work Completed

- TBD

### Editors Implemented

| Action Family | Editor Status | Notes |
|---|---|---|
| List item | Not started |  |
| Price | Not started |  |
| Recipe | Not started |  |
| Meal plan | Not started |  |
| Matkasse | Not started |  |
| Store | Not started |  |
| Memory | Not started |  |
| Settings | Not started |  |

### High-Risk UI Behavior

- TBD

### Verification

- TBD

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| User can edit common wrong fields before approval. | No |  |
| High-risk proposals are visibly different and require explicit confirmation. | No |  |
| Proposal cards remain understandable with many actions. | No |  |
| Edited actions are revalidated before approval. | No |  |

### Remaining Risks

- TBD

### Next Step

- TBD

## Phase 8: Regression Harness

### Status

Not started.

### Start Date

TBD

### Completed Date

TBD

### Goal

Make chat behavior repeatable and hard to regress.

### Files Changed

- TBD

### Work Completed

- TBD

### Test Coverage

| Test Type | Count | Notes |
|---|---|---|
| Parser tests | 0 |  |
| Resolver tests | 0 |  |
| Validator tests | 0 |  |
| Golden conversation tests | 0 |  |
| UI tests | 0 |  |
| Live AI manual scenarios | 0 |  |

### Known Flaky Or Deferred Scenarios

- TBD

### Verification

- TBD

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| At least 50 golden chat scenarios exist. | No |  |
| Known manual failures are represented as tests. | No |  |
| Tests do not require live Gemini API key. | No |  |
| Prompt/parser/planner changes can be validated locally. | No |  |

### Remaining Risks

- TBD

### Next Step

- TBD

## Phase 9: Provider And Prompt Versioning

### Status

Not started.

### Start Date

TBD

### Completed Date

TBD

### Goal

Make the AI provider layer maintainable as models, prompts, and schemas evolve.

### Files Changed

- TBD

### Work Completed

- TBD

### Versions

| Item | Version | Notes |
|---|---|---|
| Chat prompt | TBD |  |
| Chat schema | TBD |  |
| Onboarding prompt | TBD |  |
| Receipt parsing prompt | TBD |  |

### Provider Capabilities

| Capability | Supported | Notes |
|---|---|---|
| Function calling | TBD |  |
| JSON mode | TBD |  |
| Streaming | TBD |  |
| Token usage reporting | TBD |  |
| Fallback model compatibility | TBD |  |

### Verification

- TBD

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Provider code can change without rewriting app-domain planning. | No |  |
| Prompt/schema versions are visible in traces. | No |  |
| Fallback behavior does not weaken native action contract. | No |  |
| Prompt changes are reviewable and testable. | No |  |

### Remaining Risks

- TBD

### Next Step

- TBD

## Phase 10: Advanced Chat UX

### Status

Not started.

### Start Date

TBD

### Completed Date

TBD

### Goal

Make chat feel like the first-class control surface for the whole app.

### Files Changed

- TBD

### Work Completed

- TBD

### UX Flows Added

| Flow | Status | Notes |
|---|---|---|
| Contextual quick actions | Not started |  |
| Tappable entity references | Not started |  |
| Open shopping list from chat | Not started |  |
| Show recipe from chat | Not started |  |
| Compare prices from chat | Not started |  |
| Show store from chat | Not started |  |
| Show memory from chat | Not started |  |
| Show meal plan week from chat | Not started |  |
| Review pending changes | Not started |  |
| Repair suggestions after failure | Not started |  |
| Streaming answer text | Not started |  |

### Verification

- TBD

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Users can move from chat to affected records naturally. | No |  |
| Pending proposals are recoverable after conversation continues. | No |  |
| Failed actions provide useful next steps. | No |  |
| Chat suggestions are contextual, not generic. | No |  |

### Remaining Risks

- TBD

### Next Step

- TBD

## Final Completion Summary

Fill this in when all phases are complete.

### Completed Date

TBD

### Final Files Changed

- TBD

### Final Verification

- TBD

### Remaining Product Risks

- TBD

### Follow-Up Backlog

- TBD
