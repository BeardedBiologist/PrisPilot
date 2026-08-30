# PrisPilot Chat AI Phased Execution Plan

Last updated: 2026-08-30

## Purpose

This document converts `Chat_AI_Experience_Improvement_Plan.md` into an implementation roadmap. It is meant to be used phase by phase. At the end of each phase, update `Chat_AI_Phase_Log.md` with what changed, what was verified, what remains risky, and what should happen next.

The work should stay incremental. Each phase should leave the app compiling and the chat behavior easier to reason about than before.

## Guiding Rule

The model interprets user intent. Native app code owns app truth.

That means:

- Gemini can suggest what the user probably wants.
- Native code resolves records, validates payloads, detects ambiguity, applies permissions, executes changes, and reports results.
- The chat must never claim data changed until `AppStore.execute(_:)` or its replacement reports success.
- Silent no-op approvals are treated as bugs.

## Phase Overview

| Phase | Name | Main Outcome | Status |
|---|---|---|---|
| 0 | Baseline And Failure Inventory | Known bad behaviors are captured before changing logic. | Complete |
| 1 | Stabilize Existing Action Path | Current Gemini/function-call path becomes safer and less silent. | Ready for manual testing |
| 2 | Rich Context Builder | Chat receives enough bounded app state to act across tabs. | Ready for manual testing |
| 3 | Entity Resolver And Clarification | Ambiguous or missing targets produce deterministic clarification. | Ready for manual testing |
| 4 | Draft Intent Planner | Model output becomes provider-neutral draft intent before proposals. | Ready for manual testing |
| 5 | Semantic Validator | Every supported action gets native payload and precondition validation. | Ready for manual testing |
| 6 | Execution Results And Undo | Approval produces structured results and broader undo support. | Ready for manual testing |
| 7 | Proposal Editing And Safer Review UI | Users can inspect and correct proposed changes before execution. | Ready for manual testing |
| 8 | Regression Harness | Chat behavior has repeatable parser, resolver, validator, and golden tests. | Ready for manual testing |
| 9 | Provider And Prompt Versioning | Gemini integration becomes replaceable, traceable, and prompt-versioned. | Ready for manual testing |
| 10 | Advanced Chat UX | Chat becomes a stronger primary app-control surface. | Ready for manual testing |

## Phase 0: Baseline And Failure Inventory

### Objective

Capture current behavior before changing the architecture so improvements can be measured and regressions can be recognized.

### Scope

- Manual testing only unless quick unit tests are trivial.
- No production behavior changes required.
- Focus on documenting the specific ways chat is currently wrong.

### Tasks

- Create a short list of real failed prompts from testing.
- For each prompt, record expected outcome, actual outcome, and affected domain.
- Group failures into categories: wrong action, missing action, wrong target, bad default, hallucinated record, no-op approval, poor clarification, bad refusal, unsafe memory, poor text response.
- Add the highest-value failed prompts to the golden scenario backlog.
- Note whether each failure appears in live Gemini, mock AI, or both.

### Files Likely Touched

- `Chat_AI_Phase_Log.md`
- Optionally a future test fixture file under `PrisPilotTests/`

### Acceptance Criteria

- At least 15 representative chat failures are documented.
- Each failure has an expected behavior statement.
- Phase 1 priorities are based on observed failures, not guesses.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Failure categories found.
- Top five prompts to fix first.
- Any suspected root causes.
- Whether to proceed to Phase 1 as planned.

## Phase 1: Stabilize Existing Action Path

### Objective

Make the current Gemini function-call to `ProposedAction` flow safer without introducing the full draft-intent architecture yet.

### Scope

This phase should reduce obvious wrong behavior while preserving the existing UI and action model.

### Tasks

- Tighten `GeminiAIService.buildSystemPrompt(context:)` with explicit outcome rules:
  - answer-only
  - clarification-only
  - proposal-only
  - refusal-only
- Lower chat temperature if current behavior is too variable.
- Add clear prompt rules for defaults:
  - Do not default to `Weekly Shop` when multiple active/planned lists exist.
  - Do not invent store branches.
  - Do not create recipes when user asked for an existing recipe.
  - Do not save memory unless the user states a durable preference or restriction.
- Make `ChatViewModel.handleResponse` surface invalid/no-action model results with a helpful assistant message.
- Add initial semantic checks to `AppStore.validate(_:)` for values that are obviously invalid.
- Ensure `approveAll` and single approval preserve failed action state and reason when execution fails.

### Files Likely Touched

- `Services/GeminiAIService.swift`
- `Features/Chat/ChatViewModel.swift`
- `Store/AppStore.swift`
- `Models/ProposedAction.swift` if validation state needs a new case
- `PrisPilotTests/PrisPilotTests.swift`

### Acceptance Criteria

- Ambiguous requests are less likely to become guessed proposals.
- Invalid actions cannot be approved.
- Execution failures are visible to the user.
- No approved action silently disappears.
- Existing mock and live AI flows still compile.

### Suggested Verification

- Run `XcodeRefreshCodeIssuesInFile` on touched Swift files.
- Run focused unit tests if added.
- Run `BuildProject` before ending the phase.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Prompt rules changed.
- Validation rules added.
- Manual prompts retested.
- Remaining known failures.
- Next recommended phase.

## Phase 2: Rich Context Builder

### Objective

Give the AI a compact but useful snapshot of the app state needed for CRUD across all tabs.

### Scope

This phase is about context construction, not yet full native planning.

### Tasks

- Add or expand an `AIContextBuilder` abstraction.
- Extend `AIContext` with bounded structured summaries:
  - current date and timezone
  - locale/country/currency
  - active and planned shopping lists with item summaries
  - enabled and disabled store branches
  - relevant products and aliases
  - recent relevant price observations
  - recipe titles and ingredient summaries
  - current and next week meal-plan summaries
  - upcoming matkasse boxes
  - key shopping optimization settings
  - relevant memories with scope labels
- Keep context bounded by relevance and item limits.
- Add debug formatting for the context so testers can inspect what was sent.
- Update Gemini prompt to refer to these context sections as app truth.

### Files Likely Touched

- `Models/AITypes.swift`
- `Features/Chat/ChatViewModel.swift`
- `Services/GeminiAIService.swift`
- `Store/AppStore.swift` or a new `Services/AIContextBuilder.swift`
- `PrisPilotTests/PrisPilotTests.swift`

### Acceptance Criteria

- The model can see enough state to target existing lists, recipes, stores, and matkasse boxes.
- The context does not send unbounded full app state.
- Current date is always available for relative-date interpretation.
- Context summaries are deterministic enough to test.

### Suggested Verification

- Unit-test context output for seeded app state.
- Manually inspect debug context for a populated app.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- New context fields.
- Context limits.
- Any privacy/sensitivity choices.
- Prompts that improved or still fail.

## Phase 3: Entity Resolver And Clarification

### Objective

Move name matching and ambiguity decisions into native code.

### Scope

This phase can still consume existing `ProposedAction`s, but before showing or executing them, the app should check whether targets are resolvable.

### Tasks

- Add `AIEntityResolver`.
- Add result types for entity lookup:
  - resolved
  - ambiguous
  - missing
  - creatable
- Implement resolvers for:
  - shopping lists
  - shopping list items
  - products and aliases
  - store branches
  - recipes
  - meal-plan slots
  - matkasse boxes
  - memories
- Add native clarification messages for ambiguous targets.
- Add pending clarification state to chat sessions if needed for multi-turn repair.
- Ensure approval is blocked when an action needs clarification.

### Files Likely Touched

- New `Services/AIEntityResolver.swift`
- `Models/ChatModels.swift`
- `Models/ProposedAction.swift`
- `Features/Chat/ChatViewModel.swift`
- `Store/AppStore.swift`
- `PrisPilotTests/PrisPilotTests.swift`

### Acceptance Criteria

- `Add milk to the list` asks which list when multiple lists are plausible.
- `Delete Kiwi` asks which branch when multiple Kiwi branches exist.
- Existing-record operations do not create missing records by accident.
- Resolver behavior is unit-tested with exact, loose, ambiguous, and missing cases.

### Suggested Verification

- Resolver unit tests.
- Manual chat tests with multiple similar records.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Resolver rules implemented.
- Clarification examples that now work.
- Remaining ambiguous cases.
- Any model prompt changes needed next.

## Phase 4: Draft Intent Planner

### Objective

Stop treating model output as executable proposals. Convert provider output into draft intent, then native planning decides what the chat should show.

### Scope

This is the main architecture shift.

### Tasks

- Add `AIIntentDraft`, `AIDraftAction`, `AITurnOutcome`, and `AIClarificationRequest` models.
- Change Gemini response parsing so function calls become draft actions first.
- Optionally introduce a single strict JSON schema for `proposePrisPilotTurn`.
- Add `AIActionPlanner` to convert draft intent into one of:
  - answer
  - clarification
  - proposal
  - refusal
  - failure
- Preserve compatibility with current `AIResponse` until UI migration is complete.
- Ensure memory proposals also pass through draft/planner logic.

### Files Likely Touched

- New `Models/AIIntentModels.swift`
- New `Services/AIActionPlanner.swift`
- `Services/GeminiAIService.swift`
- `Models/AITypes.swift`
- `Features/Chat/ChatViewModel.swift`
- `PrisPilotTests/PrisPilotTests.swift`

### Acceptance Criteria

- Model output and app proposals are separate concepts.
- The same draft can become a proposal, clarification, or invalid result depending on app state.
- App state resolution happens before proposal display.
- Parser tests cover both existing Gemini function calls and new draft shape.

### Suggested Verification

- Parser tests.
- Planner tests against seeded app states.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Draft schema introduced.
- Compatibility choices.
- Any old direct-parsing paths still remaining.
- Next migration step.

## Phase 5: Semantic Validator

### Objective

Make every supported action enforce native rules before approval and execution.

### Scope

This phase can happen partly before or after Phase 4, but it should be completed before broader UX work.

### Tasks

- Add a dedicated `AIActionValidator` or expand `AppStore.validate(_:)` cleanly.
- Validate shopping-list create/update/delete/item actions.
- Validate price create/update/delete/confirm/flag actions.
- Validate product create/update/delete/merge/alias/barcode actions.
- Validate recipe create/update/delete/add-to-list actions.
- Validate meal-plan set/remove/build-list actions.
- Validate matkasse create/update/delete/add-meal/remove-meal actions.
- Validate store create/update/delete/enable/disable actions.
- Validate setting changes with typed keys and ranges.
- Validate memory create/update/delete with duplicate and sensitivity rules.
- Treat no-op execution as validation failure whenever it is knowable before execution.

### Files Likely Touched

- `Store/AppStore.swift`
- New `Services/AIActionValidator.swift` if separated
- `Models/ProposedAction.swift`
- `PrisPilotTests/PrisPilotTests.swift`

### Acceptance Criteria

- Every `ProposedActionPayload` case has explicit validation.
- Invalid payloads show precise reasons.
- High-risk actions show warnings even when valid.
- Silent no-op approval rate is zero for covered scenarios.

### Suggested Verification

- Unit tests for each payload family.
- Build project.
- Manual approval tests for invalid, warning, and valid actions.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Validation coverage by domain.
- Any intentionally deferred rules.
- Bugs found during validation testing.
- Remaining no-op risks.

## Phase 6: Execution Results And Undo

### Objective

Make action execution explicit, inspectable, and reversible where practical.

### Scope

This phase improves what happens after approval.

### Tasks

- Add structured execution result objects:
  - status
  - affected record IDs
  - failure reason
  - skipped reason
  - undo operation
- Introduce an `ActionExecutionPlan` for grouped and dependent actions.
- Validate dependent groups before executing any action.
- Preserve partial result details for independent groups.
- Expand undo beyond simple create/add actions:
  - restore updated fields
  - reinsert deleted records
  - restore collection membership/order
  - handle product merge rollback where feasible
- Update activity tags to carry enough data for undo and navigation.

### Files Likely Touched

- `Models/ProposedAction.swift`
- `Store/AppStore.swift`
- `Features/Chat/ChatViewModel.swift`
- `Features/Chat/ActivityTagView.swift`
- New `Services/AIActionExecutor.swift` or `Services/AIUndoManager.swift`
- Persistence models if undo history becomes persisted

### Acceptance Criteria

- Approve-all reports partial failures clearly if they occur.
- Dependent actions do not leave broken partial state.
- Undo works for common create, add, update, and delete operations.
- Activity tags remain accurate after execution.

### Suggested Verification

- Unit tests for execution result mapping.
- Manual approve-all tests with mixed valid and invalid actions.
- Manual undo tests.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Execution result model added.
- Undo coverage added.
- Known operations without undo.
- Any transaction limitations.

## Phase 7: Proposal Editing And Safer Review UI

### Objective

Let users correct the AI before approving and make higher-risk proposals clear.

### Scope

This phase is mostly chat UI and proposal-state ergonomics.

### Tasks

- Add `Edit` affordance for proposal rows.
- Build payload editors for common actions first:
  - list item product/quantity/list
  - price product/store/price/quantity/unit
  - recipe title/servings
  - meal-plan date/meal type/content
  - matkasse provider/week/count/price
  - store chain/branch/enabled
  - memory summary/category/sensitivity
- Group proposal rows by domain.
- Show assumptions and inferred defaults above actions.
- Add stronger high-risk confirmation sheet.
- Preserve partially reviewed proposal cards until all rows are terminal.
- Improve validation display for edited actions.

### Files Likely Touched

- `Features/Chat/ActionProposalView.swift`
- `Features/Chat/MessageBubbleView.swift`
- `Features/Chat/ChatViewModel.swift`
- `Models/ProposedAction.swift`
- Possibly new editor views under `Features/Chat/`

### Acceptance Criteria

- User can edit common wrong fields before approval.
- High-risk proposals are visibly different and require explicit confirmation.
- Proposal cards remain understandable with many actions.
- Edited actions are revalidated before approval.

### Suggested Verification

- Preview or simulator check for compact and long proposals.
- Dynamic type and dark mode spot checks.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Editors implemented.
- High-risk UI behavior.
- Proposal display limitations.
- Follow-up UI polish needed.

## Phase 8: Regression Harness

### Objective

Make chat behavior repeatable and hard to regress.

### Scope

This phase creates test infrastructure and scenario coverage.

### Tasks

- Add deterministic test fixtures for app state.
- Add `ScriptedAIService` for predictable test responses.
- Add parser tests for Gemini function call and draft JSON output.
- Add resolver tests for exact, alias, loose, ambiguous, missing, and creatable targets.
- Add validator tests by action family.
- Add golden conversation tests that assert outcome type and action payloads.
- Add optional manual live-AI runner that logs output but does not fail normal tests.

### Files Likely Touched

- `PrisPilotTests/PrisPilotTests.swift`
- New test support files under `PrisPilotTests/`
- `Services/MockAIService.swift` if shared fixtures are useful
- New fixture JSON files if the project supports them cleanly

### Acceptance Criteria

- At least 50 golden chat scenarios exist.
- Known manual failures are represented as tests.
- Tests do not require a live Gemini API key.
- Prompt/parser/planner changes can be validated locally.

### Suggested Verification

- Run all unit tests.
- Build project.
- Optionally run a small live-AI manual scenario suite.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Test count and coverage areas.
- Known gaps.
- Any flaky scenarios.
- Whether live-AI behavior matches deterministic expectations.

## Phase 9: Provider And Prompt Versioning

### Objective

Make the AI provider layer maintainable as models, prompts, and schemas evolve.

### Scope

This phase separates Gemini transport from PrisPilot planning and makes prompts inspectable.

### Tasks

- Move prompt text and schema text out of large inline Swift blocks where practical.
- Add prompt and schema version constants.
- Add provider capability flags:
  - function calling
  - JSON mode
  - streaming
  - token usage reporting
- Add development-only model/provider selection if useful.
- Ensure fallback models preserve the same expected schema.
- Add debug trace fields for prompt version, schema version, provider, model, latency, and response format.

### Files Likely Touched

- `Services/GeminiAIService.swift`
- `Models/AITypes.swift`
- New prompt/schema resource files if supported
- Settings/debug UI if model selection is exposed

### Acceptance Criteria

- Provider code can change without rewriting app-domain planning.
- Prompt/schema versions are visible in traces.
- Fallback behavior does not weaken the native action contract.
- Prompt changes are reviewable and testable.

### Suggested Verification

- Parser tests still pass.
- Golden tests still pass.
- Manual live Gemini smoke test.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- Prompt/schema versions introduced.
- Provider separation completed.
- Debug trace fields added.
- Model fallback behavior observed.

## Phase 10: Advanced Chat UX

### Objective

Make chat feel like the first-class control surface for the whole app.

### Scope

This phase assumes the safer core behavior exists.

### Tasks

- Add contextual quick actions after answers and activity tags.
- Add tappable entity references in messages and activities.
- Add chat-driven navigation intents:
  - open shopping list
  - show recipe
  - compare prices
  - show store
  - show memory
  - show meal plan week
- Add `Review pending changes` surface for unresolved proposals.
- Add proactive repair suggestions after failed actions.
- Add streaming text for answer-only responses if provider supports it.
- Improve empty-state suggestions based on actual app state.

### Files Likely Touched

- `Features/Chat/ChatView.swift`
- `Features/Chat/MessageBubbleView.swift`
- `Features/Chat/ActivityTagView.swift`
- `Features/Chat/ActionProposalView.swift`
- `App/RootTabView.swift` if navigation intents cross tabs
- `Models/ChatModels.swift`

### Acceptance Criteria

- Users can move from chat to affected records naturally.
- Pending proposals are recoverable after conversation continues.
- Failed actions provide useful next steps.
- Chat suggestions are contextual, not generic.

### Suggested Verification

- Manual simulator QA.
- UI tests for core navigation intents if practical.
- Build project.

### Exit Log Requirements

Update `Chat_AI_Phase_Log.md` with:

- UX flows added.
- Navigation surfaces supported.
- Known polish gaps.
- Final stabilization recommendations.

## Cross-Phase Rules

### Keep The App Compiling

Each phase should end with either:

- a passing build, or
- a clearly logged blocker explaining why the build could not be completed.

### Keep Behavior Observable

When chat behavior changes, add either:

- a test,
- a debug trace field,
- or a log entry with a manual prompt and result.

### Avoid Large Rewrites Without A Checkpoint

Prefer small vertical slices:

1. one action family,
2. one resolver,
3. one validation path,
4. one proposal UI improvement,
5. one set of tests.

### Do Not Hide Failures

When a model response cannot be parsed, resolved, validated, or executed, the user should see a clear message. Developers should be able to inspect why in DEBUG.

## Recommended Immediate Next Step

Start with Phase 0, then Phase 1. The first useful implementation slice is:

1. Document the current bad prompts.
2. Add basic payload validation for shopping lists, prices, products, stores, recipes, meal plans, matkasse, settings, and memory.
3. Make failed execution produce visible failed proposal state.
4. Tighten the Gemini prompt to ask clarification for ambiguous targets.
5. Add tests for the failures that triggered this planning work.
