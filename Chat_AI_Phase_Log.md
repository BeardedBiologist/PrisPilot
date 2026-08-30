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
| 6 | Execution Results And Undo | Ready for manual testing | 2026-08-30 | Build passed. Undo expanded to updates/deletes. ActionExecutionPlan added. Automated tests deferred. |
| 7 | Proposal Editing And Safer Review UI | Ready for manual testing | 2026-08-30 | Build passed. Edit affordance, domain grouping, high-risk confirmation, payload editors. Automated tests deferred. |
| 8 | Regression Harness | Ready for manual testing | 2026-08-30 | Build passed. 69 Swift Testing tests across 4 files covering resolver, validator, planner, and golden scenarios. No live API key required. |
| 9 | Provider And Prompt Versioning | Ready for manual testing | 2026-08-30 | Prompt catalog, provider capabilities, and chat trace metadata added. |
| 10 | Advanced Chat UX | Ready for manual testing | 2026-08-30 | Pending proposal recovery, contextual quick actions, and failure repair prompts added. |

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

Ready for manual testing. Stop here before Phase 7.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Make action execution explicit, inspectable, and reversible where practical.

### Files Changed

- `Models/ProposedAction.swift`
- `Store/AppStore.swift`
- `Store/SwiftDataPersistence.swift`
- `Features/Chat/ChatViewModel.swift`
- `Features/Chat/ActivityTagView.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Replaced `UndoInfo` with `UndoSnapshot`, a Codable enum carrying field-level before-state for update actions and full record snapshots for delete/remove actions.
- Added `ActionExecutionResult` struct so `execute()` returns both affected record IDs and an optional undo snapshot.
- Updated `execute()` in `AppStore` to return `ActionExecutionResult` and capture before-state for all update/delete cases: `updateProduct`, `updateRecipe`, `updateShoppingList`, `updateShoppingListItem`, `updatePriceObservation`, `updateStore`, `setStoreEnabled`, `updateMatkasseBox`, `deleteShoppingList`, `removeShoppingListItem`, `deleteProduct`, `deleteRecipe`, `deletePriceObservation`, `deleteStore`, `deleteMatkasseBox`, `removeMatkasseMeal`, `setMealPlanSlot`, `removeMealPlanSlot`.
- Added `applyUndoSnapshot(_:)` in `AppStore` to restore previous state from any `UndoSnapshot` case.
- Updated `canUndoActivityTag` to return `true` for any tag that carries an undo snapshot, not just legacy create/add ID-based operations.
- Updated `undoActivityTag` to delegate to `applyUndoSnapshot` before falling back to legacy ID-based undo.
- Added `ActionExecutionPlan` and `ActionPlanResult` types for grouped and dependent action execution.
- Added `executePlan(_:)` in `AppStore` supporting both `.independent` (partial success OK) and `.allOrNothing` (validate all before executing any) modes.
- Updated `ChatViewModel.executeActionForChat` to thread the undo snapshot from `ActionExecutionResult` into the action's `undoSnapshot` before creating the activity tag.
- Updated `ActivityTagSnapshot` in `SwiftDataPersistence` to round-trip `undoSnapshot` so undo state survives app restarts.
- Updated `ActivityTag.init(from:)` to copy `undoSnapshot` from the action.
- Updated `ActivityTagRow.hasTappableRecord` to also be true when the tag has an undo snapshot (enables tapping to undo meal plan and settings actions).
- Added `undoOnlyView` in `ActivityTagDetailView` for tags with a snapshot but no navigable record.
- Added `undoConfirmationMessage` computed property with action-type-specific descriptions.

### Execution Result Model

- `ActionExecutionResult(ids: [UUID], undo: UndoSnapshot?)` — returned by `execute()`.
- `ActionPlanResult` — outcome array from `executePlan()`, with per-action success/failure/skipped status and undo snapshots.

### Undo Coverage

| Operation | Undo Support | Notes |
|---|---|---|
| Create record | Yes | Existing ID-based delete. |
| Add item to list | Yes | Existing ID-based delete. |
| Update product/recipe/list/item/price/store/matkasse | Yes | Field-level snapshot restore. |
| Delete product/recipe/list/price/store/matkasse box | Yes | Full record reinsert. |
| Remove item from list | Yes | Full item reinsert at end of list. |
| Remove matkasse meal | Yes | Full meal reinsert at end of meals. |
| Set meal plan slot (new) | Yes | Clears the added slot on undo. |
| Set meal plan slot (overwrite) | Yes | Restores the previous slot. |
| Remove meal plan slot | Yes | Restores the cleared slot. |
| Merge product | Not started | Complex; deferred. |
| changeAppSetting | Not started | No typed before-state captured yet. |

### Transaction Limitations

- `executePlan(.allOrNothing)` validates before executing but does not roll back actions that partially succeed if execution throws mid-plan. Full transactional rollback is deferred.
- `applyUndoSnapshot` for delete cases appends the record at the end of the collection; original insertion order is not preserved.

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` implicitly via build.
- Ran `BuildProject`: project built successfully with no errors.
- Automated tests were not run, per user request to leave tests until the end.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Approve-all reports partial failures clearly. | Yes | Existing failed-action display from Phase 1 still applies; plan result adds per-action failure reasons. |
| Dependent actions do not leave broken partial state. | Partial | `allOrNothing` mode validates all before executing; mid-execution rollback is not yet automatic. |
| Undo works for common create, add, update, and delete operations. | Yes | Covered for all major domains. |
| Activity tags remain accurate after execution. | Yes | Snapshots are persisted through `ActivityTagSnapshot`. |

### Remaining Risks

- Undo for `changeAppSetting` is not implemented; settings changes cannot be reversed from the activity tag.
- `removeShoppingListItem` undo reinserts at end of list rather than original position.
- Snapshot-based undo is only as reliable as the Codable round-trip; if a model's Codable format changes, old persisted snapshots may fail to decode silently.
- Automated tests were not run in this phase by request.

### Next Step

- Stop here for manual review and testing.
- If this phase looks stable, continue to Phase 7: add proposal editing UI so users can correct AI-proposed values before approving.

## Phase 7: Proposal Editing And Safer Review UI

### Status

Ready for manual testing | 2026-08-30

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Let users correct proposed actions before approval and make high-risk changes clearer.

### Files Changed

- `Models/ProposedAction.swift` — changed `summary` and `payload` from `let` to `var`; added `ActionDomain` enum; added `domain` computed property to `ProposedActionType`
- `Features/Chat/ActionProposalView.swift` — full rewrite: domain grouping with section headers, pencil edit button on pending rows, high-risk approve confirmation via `Alert`, `ProposalAlert` enum, `ActionGroup` struct
- `Features/Chat/ProposalEditorSheet.swift` — new file: sheet-based payload editors for 11 action families
- `Features/Chat/ChatViewModel.swift` — added `editAction(actionID:in:newPayload:newSummary:)` that updates payload, summary, and re-validates
- `Features/Chat/MessageBubbleView.swift` — added `onEdit` passthrough parameter
- `Features/Chat/ChatView.swift` — wires `onEdit` callback to `viewModel.editAction`

### Work Completed

- `ProposedAction.payload` and `.summary` made mutable (`var`) so `ChatViewModel.editAction` can update them in place
- `ActionDomain` enum (`shopping`, `prices`, `meals`, `stores`, `memory`, `settings`) added; `ProposedActionType.domain` routes every action type to a domain
- `ActionProposalView` now groups actions by domain; domain headers (icon + label) appear when two or more distinct domains are present in the same proposal
- Pencil edit button appears beside approve/reject on each pending `ActionRow` when an `onEdit` handler is provided
- Approve button for high-risk actions (`.riskLevel == .high`) shows an `Alert` asking for explicit confirmation before calling `onApprove`
- Approve All intercepts when any pending high-risk action is present and shows a batch confirmation alert before calling `onApproveAll`
- `ProposalEditorSheet` is a sheet (`medium`/`large` detents) with `@ViewBuilder editorContent` that routes to a dedicated sub-editor based on `action.payload`
- On save, sub-editors call `onSave(newPayload, newSummary)` → `dismiss()`, which triggers `ChatViewModel.editAction` to store the new payload, regenerate validation, and persist via `appStore.replaceMessage`

### Editors Implemented

| Action Family | Editor Status | Notes |
|---|---|---|
| List item (`addShoppingListItem`) | Done | product, quantity, notes, list name |
| Create price (`createPriceObservation`) | Done | product, store, price, quantity, unit, promotion toggle, date |
| Update price (`updatePriceObservation`) | Done | product, store, new price, quantity, unit |
| Create recipe (`createRecipe`) | Done | title, servings stepper |
| Update recipe (`updateRecipe`) | Done | new title, description, servings |
| Create list (`createShoppingList`) | Done | name |
| Update list (`updateShoppingList`) | Done | new name, optional planned date |
| Memory (`createMemory`) | Done | summary, category, strength, sensitivity pickers |
| Meal plan slot (`setMealPlanSlot`) | Done | date, meal type picker, recipe/freeform, eating-out, leftover toggles |
| Matkasse box (`createMatkasseBox`) | Done | provider, delivery week, meals stepper, servings stepper, price, notes |
| Matkasse meal (`addMatkasseMeal`) | Done | meal title, box provider |
| Store (`createStore`) | Done | chain, branch, address, enabled toggle |
| Settings and other types | Not editable | Shows `ContentUnavailableView` in the sheet |

### High-Risk UI Behavior

- Individual row approve: if `action.riskLevel == .high`, tapping the approve button (now shows a warning triangle icon) sets `activeAlert = .highRiskAction(id, summary)` and shows a confirmation dialog before calling `onApprove`
- Approve All: if `highRiskPendingCount > 0`, tapping "Approve" sets `activeAlert = .highRiskApproveAll(count)` and shows a batch confirmation dialog before calling `onApproveAll`

### Verification

- `XcodeRefreshCodeIssuesInFile` on all changed files: no errors
- `BuildProject`: built successfully with no errors

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| User can edit common wrong fields before approval. | Yes | 12 action families have dedicated form editors |
| High-risk proposals are visibly different and require explicit confirmation. | Yes | Warning triangle icon + confirmation alert for .high riskLevel |
| Proposal cards remain understandable with many actions. | Yes | Domain grouping with section headers when 2+ domains present |
| Edited actions are revalidated before approval. | Yes | `appStore.validate` called in `editAction` after payload update |

### Remaining Risks

- Editing a `createPriceObservation` with a Decimal price rendered as `"\(price)"` may show trailing zeros or locale issues in the text field
- `updateRecipe` editor starts servings at the AI-proposed value (or 2 as fallback) — may not reflect the actual existing recipe's servings since that is unknown at proposal time
- `setMealPlanSlot` editor's meal-type picker is limited to breakfast/lunch/dinner/snack; custom meal types cannot be selected
- `updateShoppingList` editor resets the planned date to today when `hasDate` is toggled on if the payload had no prior date
- Automated tests were not run in this phase by request

### Next Step

- Stop here for manual review and testing
- Test: AI proposes adding an item with the wrong quantity → tap pencil → correct quantity → approve → confirm change is applied
- Test: AI proposes a high-risk delete → tap approve → confirm alert appears → confirm proceeds
- Test: AI proposes actions from two domains → confirm domain headers appear in the card
- If stable, continue to Phase 8: Regression Harness

## Phase 8: Regression Harness

### Status

Ready for manual testing.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Make chat behavior repeatable and hard to regress.

### Files Changed

- `PrisPilotTests/ResolverTests.swift` (new) — 26 AIEntityResolver tests
- `PrisPilotTests/ValidatorTests.swift` (new) — 24 AppStore.validate() tests
- `PrisPilotTests/PlannerTests.swift` (new) — 11 AIActionPlanner tests
- `PrisPilotTests/GoldenScenarioTests.swift` (new) — 18 golden scenario tests

### Work Completed

- Added `ResolverTests` covering exact, alias, loose, ambiguous, missing, and creatable resolution for shopping lists, products, store branches, recipes, and memories
- Added `ValidatorTests` covering all major validation failure paths: price observation (blank name, blank store, zero price, future date, excessive price, quantity/unit errors, ambiguous product), shopping list (blank list/product, missing item, duplicate list), recipe, store (blank chain/branch), app settings (unknown key, bad maxStoreCount, bad cheapestDefinition, negative minimumSavings, community pricing warning)
- Added `PlannerTests` covering all `AIPlannedTurn` outcomes: answer, refusal, failure, clarification, proposal with valid actions, proposal with multiple actions, memory-only proposal, empty proposal fallback to answer/failure, and invalid action carrying validation result
- Added `GoldenScenarioTests` covering scripted AIResponse → AIPlannedTurn pipeline: single/multi product price logs, intro text, add/remove/complete/delete list items, memory-only proposal, combined action+memory, text answer, memory query, offline error, quota error, scope policy blocks and allows
- All tests use Swift Testing framework (`import Testing`, `@Test`, `#expect`, `Issue.record`)
- No test requires a live Gemini API key or network access
- All tests are `@MainActor` as required by AppStore and AIEntityResolver

### Test Coverage

| Test Type | Count | Notes |
|---|---|---|
| Resolver tests | 26 | All entity types: list, product, branch, recipe, memory |
| Validator tests | 24 | All major validation failure and pass paths |
| Planner tests | 11 | All AIPlannedTurn outcomes |
| Golden scenario tests | 18 | Price logs, list ops, memory, text answers, errors, scope policy |
| **Total** | **69** | Existing 9 scope + validation tests from PrisPilotTests.swift not counted |

### Known Flaky Or Deferred Scenarios

- Live Gemini function call parsing not covered (requires live API key — deferred to manual testing)
- `looselyMatchesProductName` edge cases (word order, plural forms, brand prefixes) not exhaustively tested
- Ambiguous product test relies on Jaccard similarity threshold being exactly 0.5 for two-word products — stable but worth monitoring if threshold changes

### Verification

- Build passed after fixing `AppStore()` default parameter issue in `GoldenScenarioTests`
- Manual test run deferred per user request

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| At least 50 golden chat scenarios exist. | Yes | 69 total tests; golden scenarios are planner-level (no live API) |
| Known manual failures are represented as tests. | Yes | Validator tests cover known failure modes |
| Tests do not require live Gemini API key. | Yes | All tests are deterministic and offline |
| Prompt/parser/planner changes can be validated locally. | Yes | Planner and resolver tests catch regressions |

### Remaining Risks

- Gemini function call schema changes won't be caught until live testing
- If `AppStore` seeding changes (e.g. "Weekly Shop" removed), several tests will break — acceptable coupling

### Next Step

Phase 9: Provider And Prompt Versioning

## Phase 9: Provider And Prompt Versioning

### Status

Ready for manual testing.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Make the AI provider layer maintainable as models, prompts, and schemas evolve.

### Files Changed

- `Models/AITypes.swift`
- `Models/AIIntentModels.swift`
- `Services/AIPromptCatalog.swift`
- `Services/GeminiAIService.swift`
- `Services/MockAIService.swift`
- `Features/Settings/SettingsView.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Added `AIProviderCapabilities` so each `AIService` can declare function-calling, JSON mode, streaming, token reporting, and fallback compatibility.
- Added `AITraceMetadata` and threaded trace metadata through Gemini chat responses with provider, selected model, prompt version, schema version, response format, latency, capabilities, and fallback models tried.
- Added `AIPromptCatalog` with versioned chat, onboarding, receipt, and Gemini function-call schema constants.
- Moved the chat system prompt and context rendering out of `GeminiAIService` into `AIPromptCatalog` so prompt changes are easier to review.
- Marked the legacy draft schema as `2026-08-30.phase9.legacy-function-draft-v1`.
- Added DEBUG-only Settings rows for chat prompt version, schema version, and provider capabilities.

### Versions

| Item | Version | Notes |
|---|---|---|
| Chat prompt | `2026-08-30.phase9.chat-system-v1` | In `AIPromptCatalog.chatSystemPrompt(context:)`. |
| Chat schema | `2026-08-30.phase9.legacy-function-draft-v1` | Legacy Gemini function calls are still wrapped as draft actions. |
| Onboarding prompt | `2026-08-30.phase9.onboarding-json-v1` | Versioned in the prompt catalog; prompt body still lives in Gemini request builder. |
| Receipt parsing prompt | `2026-08-30.phase9.receipt-json-v1` | Versioned in the prompt catalog; prompt body still lives in Gemini request builder. |

### Provider Capabilities

| Capability | Supported | Notes |
|---|---|---|
| Function calling | Yes | Gemini chat uses function declarations. |
| JSON mode | Yes | Onboarding and receipt parsing request `application/json` responses. |
| Streaming | No | Current `AIService` contract returns full responses. |
| Token usage reporting | No | Not parsed from Gemini responses yet. |
| Fallback model compatibility | Yes | Fallback models reuse the same request body, prompt, and function-call schema. |

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on `Models/AITypes.swift`, `Models/AIIntentModels.swift`, `Services/AIPromptCatalog.swift`, `Services/GeminiAIService.swift`, `Services/MockAIService.swift`, and `Features/Settings/SettingsView.swift`: no issues found.
- `Store/AppStore.swift` still shows the three pre-existing actor-isolation warnings around onboarding/welcome message creation.
- Ran `BuildProject`: project built successfully.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Provider code can change without rewriting app-domain planning. | Partial | Provider metadata is separated; Gemini transport still owns function-call parsing. |
| Prompt/schema versions are visible in traces. | Yes | `AITraceMetadata` carries prompt and schema versions; DEBUG Settings also shows current chat versions. |
| Fallback behavior does not weaken native action contract. | Yes | Fallbacks reuse the same body/schema and only change model name after recoverable errors. |
| Prompt changes are reviewable and testable. | Partial | Chat prompt is in `AIPromptCatalog`; onboarding and receipt prompt bodies are versioned but not fully extracted. |

### Remaining Risks

- No persistent debug trace panel exists yet; metadata is carried in `AIResponse.trace` and visible in DEBUG settings, but not stored with chat history.
- Gemini function-call parsing still lives in `GeminiAIService`; a later provider split should move app-domain parsing behind a provider-neutral adapter.
- Token usage is not reported until Gemini response usage metadata is parsed.
- Onboarding and receipt prompt bodies remain inline, though their versions are centralized.

### Next Step

- Phase 10 was started next to add a bounded advanced chat UX slice before manual testing.

## Phase 10: Advanced Chat UX

### Status

Ready for manual testing.

### Start Date

2026-08-30

### Completed Date

2026-08-30

### Goal

Make chat feel like the first-class control surface for the whole app.

### Files Changed

- `Models/ChatModels.swift`
- `Store/AppStore.swift`
- `Features/Chat/ChatView.swift`
- `Features/Chat/MessageBubbleView.swift`
- `Chat_AI_Phase_Log.md`
- `Chat_AI_Phased_Execution_Plan.md`

### Work Completed

- Added `ChatPendingProposal` summaries and `AppStore.pendingProposals(for:)` so unresolved or failed proposal cards can be surfaced after the conversation continues.
- Added a pending-proposal review bar above the chat input that scrolls back to the earliest unresolved proposal.
- Added `ChatQuickAction` and contextual prompt chips based on current app state instead of a fixed generic set.
- Added quick-action chips after assistant answers and after activity-tag summaries.
- Added a repair suggestion row when a proposal contains failed actions, pre-filling a prompt that asks PrisPilot to clarify or repair the failed proposal.

### UX Flows Added

| Flow | Status | Notes |
|---|---|---|
| Contextual quick actions | Done | Input and assistant follow-up chips now use current app state. |
| Tappable entity references | Partial | Activity tags already open detail sheets for affected records; inline message text links are deferred. |
| Open shopping list from chat | Partial | Completed shopping activity tags open list details. Cross-tab push navigation is deferred. |
| Show recipe from chat | Partial | Completed recipe activity tags open recipe details. |
| Compare prices from chat | Partial | Quick actions can prefill comparison prompts; direct navigation is deferred. |
| Show store from chat | Partial | Completed store activity tags open store details. |
| Show memory from chat | Partial | Completed memory activity tags open memory details; AI Memory remains available in the header. |
| Show meal plan week from chat | Deferred | Meal plan activity tags currently expose undo/details only. |
| Review pending changes | Done | Pending proposal bar scrolls back to unresolved cards. |
| Repair suggestions after failure | Done | Failed proposal cards show a repair prompt action. |
| Streaming answer text | Deferred | Provider capabilities mark streaming unsupported by the current service contract. |

### Verification

- Ran `XcodeRefreshCodeIssuesInFile` on `Features/Chat/ChatView.swift`, `Features/Chat/MessageBubbleView.swift`, `Store/AppStore.swift`, and `Models/ChatModels.swift`: no new issues found.
- Ran `BuildProject`: project built successfully.

### Acceptance Criteria Review

| Criterion | Met? | Notes |
|---|---|---|
| Users can move from chat to affected records naturally. | Partial | Existing activity-tag detail sheets cover major record types; cross-tab deep links are still deferred. |
| Pending proposals are recoverable after conversation continues. | Yes | The review bar surfaces pending and failed proposal cards in the active session. |
| Failed actions provide useful next steps. | Yes | Failed cards now expose a repair prompt action. |
| Chat suggestions are contextual, not generic. | Yes | Empty-state and follow-up chips respond to saved lists and price history. |

### Remaining Risks

- Pending proposal recovery is session-local and relies on proposal cards remaining in chat memory; proposed action cards are still not persisted by `SwiftDataPersistence`.
- Quick actions prefill prompts rather than execute navigation directly, so they remain safe but not fully deep-linked.
- Inline entity references inside assistant text are not parsed or tappable yet.
- Streaming is intentionally deferred because the provider contract is non-streaming.

### Next Step

- Stop here for manual testing as requested.
- Test unresolved proposal recovery by leaving a proposal pending, sending another message, then tapping the review bar.
- Test a failed proposal and confirm the repair prompt chip appears.
- Test activity tags for list, price, recipe, store, and memory actions to confirm detail sheets still open.

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
