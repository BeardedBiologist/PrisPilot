# PrisPilot Chat AI Experience Improvement Plan

Last updated: 2026-08-30

## Goal

Make the chat feel like a consistent, reliable app controller for PrisPilot, not a general chatbot that sometimes proposes useful actions. The user should be able to ask for CRUD operations across Shopping, Prices, Recipes, Meal Planning, Matkasse, Stores, Settings, Memory, and Household workflows, then clearly review, approve, edit, reject, undo, and understand the resulting app changes.

The central rule: the model may interpret intent, but native app code owns truth, validation, conflict resolution, execution, persistence, and user-facing accountability.

## Current State Summary

The app already has the important foundation:

- `ChatViewModel` sends user messages to the active `AIService`, converts responses into assistant text, proposed actions, memory proposals, and activity tags.
- `GeminiAIService` uses Gemini function calling with a broad list of app action declarations.
- `ProposedAction`, `ProposedActionPayload`, and `ProposedActionType` define typed native action surfaces.
- `AppStore.validate(_:)` and `AppStore.execute(_:)` provide the native action gate and execution layer.
- The chat UI supports proposal cards, per-action approve/reject, approve all, reject all, and post-execution activity tags.
- Undo exists for some create/add actions where affected record IDs are enough to reverse the change.
- `AIScopePolicy` locally refuses some clearly out-of-scope inputs before contacting the model.

The main issue is that this is currently a permissive model-to-action path. The AI can call many functions, but the app does not yet enforce enough deterministic rules around entity resolution, ambiguity, required preconditions, side effects, action sequencing, failed execution, or regression behavior.

## Desired Chat Contract

Every chat turn should resolve into exactly one of these native outcomes:

| Outcome | Meaning | UI Result |
|---|---|---|
| Answer | The user asked an in-scope question that does not change data. | Assistant message with concise answer and optional source/context note. |
| Clarification | The user intent is valid but missing required information or has ambiguous targets. | Assistant asks one focused follow-up. No actions proposed. |
| Proposal | The user requested data changes and all required targets can be resolved or safely created. | Proposal card with typed actions and validation state. |
| Refusal | The request is outside PrisPilot scope or violates app permission policy. | Brief scoped refusal with suggested in-app alternatives. |
| Failure | The AI/provider/app action path failed unexpectedly. | User-readable error plus retry path where appropriate. |

The model should never produce a mixed unclear state like a confident answer plus invalid actions, or an action card that silently does nothing when approved.

## Key Problems To Fix

### 1. The Model Has Too Much Responsibility

Current behavior depends heavily on one large system prompt and Gemini tool selection. The model chooses action type, target names, default values, and sometimes implied data creation. Native code then executes if broad permission validation passes.

Risks:

- Wrong list, recipe, store, or product targeted by name.
- Default list names such as `Weekly Shop` used when the user meant the current active list.
- Stores and products created implicitly when the model misspells or hallucinates names.
- Ambiguous edits or deletes resolve to no-op execution instead of user-visible clarification.
- Complex requests produce incomplete action groups.

Fix direction:

- Introduce a native planning layer between model output and `ProposedAction`.
- Treat model function calls as `AIIntentDraft`s, not executable proposals.
- Resolve entities deterministically in native code before creating `ProposedAction`s.
- Require clarification when resolution confidence is low.

### 2. Validation Is Too Shallow

`AppStore.validate(_:)` currently checks permission mode and marks destructive actions as warnings. It does not consistently validate payload semantics, target existence, duplicates, date validity, price sanity, unit compatibility, or action dependencies.

Examples of required validation:

| Action Area | Required Native Validation |
|---|---|
| Shopping lists | Existing list for edits/deletes, duplicate list names, valid status transitions, item existence for item edits. |
| Prices | Positive price, valid unit/quantity pair, plausible price bounds, store resolution, product resolution or explicit product creation. |
| Recipes | Existing recipe for updates/deletes, non-empty title, positive servings, ingredient completeness. |
| Meal plans | Valid date, valid meal type, recipe exists if recipe slot, clear distinction between freeform/eating out/recipe. |
| Matkasse | Provider match, delivery week normalization, positive meal/serving counts, duplicate box handling. |
| Stores | Chain/branch split, duplicate branch detection, dependency checks before delete. |
| Settings | Key allowlist, type-safe value parsing, range checks. |
| Memory | Duplicate/similar memory detection, sensitivity classification, explicit consent for sensitive/health memory. |

Fix direction:

- Replace single `ValidationResult` with richer validation details: `valid`, `warning`, `requiresClarification`, `invalid`.
- Validate each payload field and target before proposal display.
- Make approval impossible for actions that would no-op.
- Show exactly why a proposal needs clarification or cannot be approved.

### 3. Entity Resolution Is Name-Based And Fragile

Most AI actions identify records by strings, while app data is ID-based. Some helpers use exact case-insensitive matching; some create missing records; some no-op if missing.

Fix direction:

- Create `AIEntityResolver` with deterministic lookup methods.
- Return `Resolved<T>`, `Ambiguous<T>`, `Missing`, or `Creatable` instead of raw optionals.
- Use aliases, loose product matching, active/planned list priority, recency, and current tab context.
- Add confidence thresholds and tie-breaking rules.
- Store resolved record IDs in proposals before execution.

Resolution rules should be explicit:

| Entity | Resolution Rules |
|---|---|
| Shopping list | Prefer exact name; then active/planned list with close match; if user says `weekly list`, map to active `Weekly Shop` if present; if multiple matches, clarify. |
| Product | Prefer exact name; then aliases; then loose product name match; create only for create/add/price actions where user clearly supplied a new product. |
| Store branch | Prefer exact display name; then chain+branch match; if only chain is supplied and multiple branches exist, clarify; if no branch exists, only create when the user is recording a price or explicitly adding a store. |
| Recipe | Prefer exact title; then close title match; never create recipe when user asked to add existing recipe ingredients. |
| Matkasse box | Match provider plus delivery week when possible; clarify if multiple boxes from same provider exist. |
| Memory | Match by semantic-ish summary normalization and category; never delete memory from a vague `forget that` without a clear candidate. |

### 4. Tool Schema Is Broad But Not Workflow-Aware

The current function list covers many actions, but each tool is independent. Real requests often require dependent sequences:

- Create a list, then add items to it.
- Create products and prices, then optimize the list.
- Create a recipe with ingredients, then add it to a meal plan.
- Create a matkasse box, then attach meals.
- Change optimization settings, then re-run shopping plans.

Fix direction:

- Model output should represent a turn-level plan, not just independent tool calls.
- Add native support for action dependencies and generated IDs.
- Allow proposal groups with sections: `Creates`, `Updates`, `Deletes`, `Needs confirmation`, `Could not resolve`.
- Consider replacing many direct Gemini function declarations with one structured `proposePrisPilotTurn` JSON schema containing intent, entities, actions, assumptions, and clarification question.

Recommended target schema:

```json
{
  "turnType": "answer | clarification | proposal | refusal",
  "assistantText": "short text shown above proposal or as the answer",
  "clarificationQuestion": null,
  "assumptions": [],
  "actions": [
    {
      "type": "addShoppingListItem",
      "clientActionID": "a1",
      "target": { "listName": "Weekly Shop" },
      "arguments": { "productName": "Milk", "quantity": "2 l" },
      "reason": "User asked to add milk to the weekly list",
      "riskLevel": "low"
    }
  ],
  "memoryProposals": []
}
```

Native code should decode, validate, resolve, normalize, and convert this into `ProposedAction`s.

### 5. Context Is Too Thin For Full App Control

`AIContext` currently includes memories, available shopping list names, enabled store branches, user preferences, and currency. For CRUD across every tab, the model needs compact but richer context.

Add context sections:

| Context Section | Include |
|---|---|
| Current date/locale | Exact date, timezone, country, currency, metric defaults. |
| Shopping lists | ID token, name, status, planned date, scope, top pending items, recent update. |
| Products | Relevant product names, aliases, categories, default units, barcode presence. |
| Price observations | Recent relevant prices, store, quantity/unit, freshness/confidence, promotion state. |
| Recipes | Titles, servings, ingredient summaries, scope. |
| Meal plan | Current week slots and next week slots. |
| Matkasse | Active/upcoming boxes, provider, week, meals, price. |
| Stores | Enabled and disabled branches, chain, branch, distance if known. |
| Settings | Optimization thresholds, community pricing, AI permission modes. |
| Memory | Relevant personal and household memories, labeled by scope and sensitivity. |
| Current UI context | Current tab/view and selected record if available later. |

Context must be bounded. Do not send all data blindly. Build a `AIContextBuilder` that selects records relevant to the latest user message, plus important current state.

### 6. Chat Needs Clarification And Repair Loops

Right now failed parsing or missing data often becomes no proposal or a generic answer. The user needs the assistant to ask precise follow-up questions.

Examples:

| User Request | Correct Assistant Behavior |
|---|---|
| `Add milk to the list` when multiple active lists exist | Ask `Which list should I add milk to: Weekly Shop or Taco Night?` |
| `Delete Kiwi` when several Kiwi branches exist | Ask which branch. |
| `Add Adams Matkasse next week` with no meal/serving count | Propose creating a box with defaults only if defaults are clearly shown; otherwise ask. |
| `Move the expensive stuff to Rema` with multiple Rema branches | Ask which branch or offer top enabled branch. |
| `Forget I dislike Q milk` with no matching memory | Say no matching memory was found, offer saved memories. |

Fix direction:

- Add `PendingClarification` state to chat sessions.
- Store unresolved draft intent and candidate choices.
- When the user answers, resolve the pending draft instead of starting a new unrelated turn.
- Render clarification choices as tappable chips where possible.

### 7. Approvals Need Better Semantics

The proposal card currently has approve/reject controls but does not expose enough detail for higher-risk workflows.

Improve proposal UI:

- Show grouped action count by area: Shopping, Prices, Meals, Settings, Memory.
- Show assumptions explicitly, especially defaults and inferred dates.
- Show destructive changes with stronger visual treatment.
- Show invalid or ambiguous proposals inline with the exact reason.
- Add `Edit` for action arguments before approval.
- Preserve partially approved proposals as proposal cards until all actions are terminal.
- After approval, activity tags should include enough detail and route to affected records.

Approval policy:

| Risk | Examples | Required Approval |
|---|---|---|
| Low | Add list item, create non-sensitive memory, record price. | Normal approve. |
| Medium | Edit item/list/recipe/store, replace meal slot, disable store. | Normal approve plus clear before/after summary. |
| High | Delete records, merge products, sensitive memory, household invite/settings. | Explicit confirm phrase or second confirmation sheet. |

### 8. Execution Should Be Transactional Enough

`approveAll` executes actions in a loop. If some succeed and later ones fail, the result can be partial without a clear transaction model.

Fix direction:

- Introduce `ActionExecutionPlan` with ordered actions and dependency metadata.
- Validate the entire plan before executing any action when actions are dependent.
- For independent actions, allow partial execution but report per-action results clearly.
- Add execution result objects: created IDs, updated IDs, skipped reason, failure reason, undo snapshot.
- Consider lightweight rollback for grouped low-risk create actions if a later dependent action fails.

### 9. Undo Needs Snapshots For Edits And Deletes

Current undo works for simple create/add actions. It cannot restore edits/deletes because `UndoInfo` does not carry enough before-state.

Fix direction:

- Add `UndoOperation` cases: deleteCreatedRecords, restoreRecords, restoreFieldValues, reinsertRecords, restoreCollectionOrder.
- Capture undo snapshots before execution for update/delete/merge actions.
- Surface undo availability per activity tag.
- Expire undo after app restart only if snapshots are not persisted; otherwise persist recent undo history.

### 10. Testing Must Measure AI Consistency

Prompt changes without tests will regress. The app needs a repeatable AI behavior test harness.

Build three layers of tests:

| Test Layer | Purpose | Runs Against |
|---|---|---|
| Parser tests | Given model JSON/function-call output, ensure correct draft/proposal decoding. | Pure Swift unit tests. |
| Resolver/validator tests | Given app state and draft actions, ensure correct valid/clarify/invalid outcomes. | Pure Swift unit tests using `AppStore`. |
| Golden conversation tests | Given user utterance and fixture state, assert expected outcome type and action payloads. | Mock/deterministic AI service first; optional live Gemini manual suite. |

Golden scenarios should cover:

- Create shopping list with multiple items.
- Add item to existing list.
- Add item when multiple lists match.
- Record price with quantity/unit/store.
- Record price and add quantity to list in one request.
- Correct a recent price.
- Delete a price only when explicitly requested.
- Create recipe from natural language.
- Update recipe servings.
- Add recipe ingredients to a list.
- Plan meals for the week.
- Build a shopping list from a meal plan.
- Add/update/delete matkasse box.
- Add/remove matkasse meals.
- Enable/disable store branch.
- Update optimization settings.
- Create/delete memory.
- Refuse out-of-scope request.
- Ask clarification for ambiguous targets.
- Respect disabled AI permission.
- Avoid duplicate products, lists, stores, and memories.

### 11. Observability Is Needed During Testing

The tester needs to see why the AI did something wrong.

Add a debug-only AI trace panel:

- Raw user message.
- Context summary sent to model.
- Raw model response or function calls.
- Parsed draft intent.
- Resolver results.
- Validation results.
- Final proposal/action execution results.
- Provider/model/latency/token estimate if available.

Keep this behind `#if DEBUG` and do not expose API keys or sensitive memory contents unnecessarily.

## Target Architecture

### Proposed Components

| Component | Responsibility |
|---|---|
| `AIContextBuilder` | Builds compact, relevant, bounded context for each chat turn. |
| `AIIntentService` | Talks to Gemini and returns a decoded `AIIntentDraft`, not executable actions. |
| `AIIntentDraft` | Provider-neutral model output containing turn type, assistant text, assumptions, draft actions, and memory drafts. |
| `AIEntityResolver` | Resolves names and references into app record IDs with confidence and ambiguity metadata. |
| `AIActionValidator` | Performs payload, permission, semantic, dependency, and risk validation. |
| `AIActionPlanner` | Converts drafts into ordered `ProposedAction`s or a clarification request. |
| `AIActionExecutor` | Executes validated plans and returns structured per-action results. |
| `AIUndoManager` | Captures and applies undo snapshots. |
| `AITraceStore` | Debug-only trace capture for tests and manual diagnosis. |

This can be introduced incrementally without rewriting the whole app at once.

### Suggested Data Flow

1. User sends message.
2. `ChatViewModel` builds a `ChatTurnRequest` with session ID, latest message, pending clarification if any, and app context.
3. `AIContextBuilder` selects relevant app state.
4. `AIIntentService` asks Gemini for strict JSON or function output.
5. Native decoder converts the provider result into `AIIntentDraft`.
6. `AIActionPlanner` resolves entities, validates actions, and either returns an answer, clarification, refusal, or proposal.
7. Chat renders the result.
8. User approves, edits, or rejects proposals.
9. `AIActionExecutor` executes approved actions and emits activity tags plus undo data.
10. Debug trace records the full decision path in development builds.

## Prompt Strategy

The prompt should become shorter, stricter, and testable.

Core rules:

- You are PrisPilot, not a general assistant.
- Return only the requested structured JSON unless the native integration uses function calls.
- Do not invent records. If a target is ambiguous or missing, ask a clarification unless the action type safely permits creation.
- Use the provided context as app truth.
- Use exact user-provided names for products, recipes, stores, and lists unless normalizing obvious casing/plurals.
- Never include emojis in structured fields.
- Do not combine answer and proposal unless the text only explains the proposal.
- For destructive changes, require explicit user intent.
- For dates, use exact ISO dates based on the supplied current date.
- For Norwegian grocery context, understand NOK, metric units, Kiwi, Rema 1000, Coop, Meny, Spar, and local branch names, but do not assume branches.

Prompt files should be versioned separately from `GeminiAIService.swift` so they can be reviewed and tested like product logic.

## Native Validation Rules By Domain

### Shopping

- Creating a list requires non-empty unique name after trimming.
- Adding an item requires non-empty product and quantity.
- If list name is omitted, resolve to one active list; otherwise ask.
- Do not auto-create a new list from vague words like `the list` when multiple candidates exist.
- Updating, completing, removing, moving, or substituting an item requires an existing list and existing item.
- If multiple items loosely match, ask for clarification.
- Optimization requires at least one enabled store and at least one pending item.

### Prices

- Price must be positive and within plausible grocery bounds.
- Quantity must be positive when supplied.
- Unit is required when quantity is supplied for weight/volume/package-size comparisons.
- Store must resolve to a branch or be explicitly creatable from the user utterance.
- `updatePriceObservation`, `deletePriceObservation`, and `confirmPriceObservation` must target a specific existing personal observation or ask clarification.
- Promotions should include promotion end date when user mentions an offer period.
- Community prices cannot be edited/deleted through personal price actions.

### Products

- Product names must be plain text without emoji or quantity.
- Create product should dedupe against exact name, aliases, and loose match.
- Update/delete/merge require existing products.
- Merge requires distinct products and high confidence they are duplicates.
- Barcode must pass length/character sanity checks.

### Recipes

- Creating a recipe should support title, servings, ingredients, and instructions, not only title/servings.
- Recipe ingredients should be structured as product name, quantity, unit, notes.
- Updating/deleting requires existing recipe resolution.
- Adding recipe to shopping list requires an existing saved recipe and resolvable list.
- Scaling recipe should be a first-class action or an update flow with clear servings change.

### Meal Planning

- Dates must be ISO `YYYY-MM-DD` after native parsing.
- Relative dates must be resolved using current date from context.
- Meal type should be one of Breakfast, Lunch, Dinner, or a supported custom value.
- Setting a slot should warn if overwriting an existing meal.
- Building shopping list from meal plan should skip eating-out and matkasse/freeform slots that do not have ingredients.

### Matkasse

- Provider is required.
- Delivery week should normalize to week start in native code.
- Meal count, servings, and price must be positive when supplied.
- Updating/deleting a box requires resolving provider and week if multiple boxes exist.
- Adding/removing a meal requires existing box resolution.

### Stores

- Creating a store requires chain and branch/location name.
- If user supplies only a chain, ask for branch unless intent is enabling/disabling all branches, which should be a separate supported workflow.
- Detect duplicate branches by chain+branch normalized names.
- Deleting a store should warn if prices or shopping assignments reference it.
- Disabling a store is lower risk than deleting and should be preferred when the user says `do not shop there`.

### Settings

- Settings must use typed native keys, not arbitrary strings.
- Numeric settings must have range checks.
- Currency/country changes should update formatting defaults consistently.
- Community pricing changes should clearly explain privacy implications.

### Memory

- Create memory only when the user states a durable preference, habit, restriction, or decision rule.
- Do not save transient commands as memories.
- Sensitive or health memories require explicit approval and clear labeling.
- Update/delete memory requires resolving a saved memory or asking clarification.
- Memory summaries should be concise, neutral, and user-controllable.

### Household

- Household actions should be high risk until backend/auth is complete.
- Invites require a valid email or local share code flow.
- Household data scope must be explicit for shared lists, recipes, and memories.
- The AI should not claim cloud sync or real invitation delivery until implemented.

## Implementation Phases

### Phase 1: Stabilize The Existing Path

Objective: reduce wrong actions without a large architecture rewrite.

Tasks:

- Add richer `AIContext` fields: current date, settings summary, active/planned list details, recipe titles, upcoming meal plan, matkasse boxes.
- Tighten `buildSystemPrompt` with explicit outcome rules and clarification rules.
- Set stricter generation config for chat turns: lower temperature and JSON/function-call discipline where supported.
- Add payload validation to `AppStore.validate(_:)` for obvious invalid values.
- Ensure invalid/no-op execution surfaces as failed proposal with reason, not silent disappearance.
- Add unit tests for `AIScopePolicy`, action parsing, and validation.

Acceptance criteria:

- Ambiguous target requests ask a follow-up instead of guessing.
- Invalid actions cannot be approved.
- Approving a proposal never silently does nothing.
- Basic CRUD across shopping lists, prices, stores, products, recipes, meal slots, and matkasse has deterministic tests.

### Phase 2: Introduce Draft Intent And Native Planning

Objective: stop treating model tool calls as directly executable proposals.

Tasks:

- Add `AIIntentDraft`, `AIDraftAction`, `AITurnOutcome`, and `AIClarificationRequest` models.
- Update Gemini parsing to produce draft actions first.
- Add `AIActionPlanner` to convert drafts into proposed actions.
- Add `AIEntityResolver` for products, lists, stores, recipes, meal slots, matkasse boxes, and memories.
- Add pending clarification state to `ChatSession`.
- Add candidate-choice UI for clarification where practical.

Acceptance criteria:

- The same model output can lead to either proposal or clarification based on current app state.
- Entity IDs are resolved before approval for existing-record operations.
- Missing/ambiguous targets are visible and recoverable.

### Phase 3: Make Proposals Editable And Safer

Objective: give the user enough control to correct the AI before execution.

Tasks:

- Add `editAction` flow for proposal payloads.
- Add before/after display for update/delete actions.
- Add high-risk confirmation sheet for destructive actions.
- Add grouped proposal UI by domain.
- Add undo snapshots for update/delete actions.
- Add per-action execution results and persistent activity history.

Acceptance criteria:

- User can fix wrong list/product/store/quantity/date before approving.
- Destructive actions require stronger confirmation.
- Undo works for common edits and deletes, not just creates.

### Phase 4: Build AI Regression Harness

Objective: make chat behavior testable before every release.

Tasks:

- Create JSON fixtures for representative app states.
- Create golden user utterance files with expected outcome/action payloads.
- Add deterministic `ScriptedAIService` for tests.
- Add parser tests for Gemini function call and strict JSON modes.
- Add resolver/validator tests for ambiguous, missing, duplicate, and invalid cases.
- Add optional manual live-AI test runner that logs diffs but does not fail CI.

Acceptance criteria:

- A change to prompt/schema/parser can be regression-tested without using the live API.
- At least 50 golden chat scenarios pass locally.
- Known bad behaviors from manual testing are captured as named regression tests.

### Phase 5: Improve Provider Strategy

Objective: make the AI layer replaceable and measurable.

Tasks:

- Split provider code from PrisPilot-specific planning code.
- Move prompts/schemas into versioned resources.
- Add model/provider settings for development builds.
- Add provider capability flags: function calling, JSON mode, token usage, streaming.
- Add fallback behavior that preserves schema compatibility.
- Add trace logging for raw provider responses in DEBUG only.

Acceptance criteria:

- Gemini can be swapped or upgraded without changing app-domain planning logic.
- Prompt/schema versions are visible in debug traces.
- Provider fallback does not change the native action contract.

### Phase 6: Advanced Chat UX

Objective: make the chat feel like the primary interface for the whole app.

Tasks:

- Add contextual quick actions after assistant answers.
- Add tappable entity references in messages and activity tags.
- Add `Review all pending changes` surface if proposals are left unresolved.
- Add proactive repair suggestions when execution fails.
- Add chat-driven navigation intents: open list, show recipe, compare prices, show memory.
- Add streaming text for answer-only responses if provider supports it.

Acceptance criteria:

- The user can move naturally from chat to the affected tab record.
- Pending proposal state is not lost in long conversations.
- Failed actions are understandable and recoverable.

## Prompt And Schema Versioning

Create a small internal version matrix:

| Version | Change | Migration Concern |
|---|---|---|
| `chat-schema-v1` | Existing function-call action parsing. | Direct function calls map to proposals. |
| `chat-schema-v2` | Draft intent JSON with native planning. | Requires parser, planner, resolver. |
| `chat-schema-v3` | Dependency-aware grouped plans. | Requires transactional executor. |

Each trace should include prompt version, schema version, provider, model name, and app build version.

## Golden Test Scenario Backlog

### Shopping List Scenarios

- `Create a list called Taco Night and add beef, shells, lettuce, tomatoes, salsa, sour cream.`
- `Add milk to the weekly list.`
- `Add milk to the list.` with two active lists should clarify.
- `Remove milk from the weekly list.` should remove item, not mark complete.
- `Mark milk bought.` should complete item if one obvious candidate exists.
- `Move milk to Rema 1000 Pindsle.` should require existing item and store.
- `Substitute oat milk for milk.` should update the item and clear price assignment.

### Price Scenarios

- `I paid 39.90 for 400 g minced beef at Kiwi Majorstuen.`
- `Actually that beef was 49.90.` should update the most recent relevant personal price.
- `Delete the price I just added for beef.` should target the recent personal observation.
- `Rema has milk for 22.50 per liter.` should record price with unit.
- `Kiwi has apples on offer for 29.90 this week.` should mark promotion and handle missing quantity appropriately.

### Recipe Scenarios

- `Save a pancake recipe for 4 with flour, milk, eggs, and butter.`
- `Change pancakes to serve 6.`
- `Add all pancake ingredients to Saturday breakfast list.`
- `Delete the pancake recipe.` should be high risk.

### Meal Plan Scenarios

- `Plan tacos for dinner every Tuesday this month.`
- `Plan pasta Monday, salmon Tuesday, and leftovers Wednesday.`
- `Clear dinner next Friday.`
- `Build my shopping list from next week's meal plan.`

### Matkasse Scenarios

- `Add Adams Matkasse for next week, 4 meals for 2 people, 899 kr.`
- `Add fish tacos to that matkasse.`
- `Remove fish tacos from Adams next week.`
- `Delete next week's Adams box.`

### Store And Settings Scenarios

- `Add Rema 1000 Pindsle and Kiwi Kilgata as stores.`
- `Disable Kiwi Kilgata for shopping plans.`
- `Use at most two stores unless the savings are over 100 kr.`
- `Change currency to euros.`
- `Turn off community pricing.`

### Memory Scenarios

- `Remember that I prefer Tine milk.`
- `Remember my child has a peanut allergy.` should require sensitive/health confirmation.
- `What do you remember about me?`
- `Forget that I prefer Tine milk.`
- `Forget that.` immediately after a memory discussion should use conversation context.

### Refusal And Scope Scenarios

- `Write Swift code for a button.` should refuse as out of scope.
- `Translate this paragraph.` should refuse unless it is directly tied to a grocery label or recipe in the app.
- `What is the weather in Oslo?` should refuse.
- `Compare Kiwi and Rema prices for my taco list and also tell me a joke.` should handle price comparison and ignore/refuse joke portion.

## Manual QA Checklist

Before considering the chat experience stable, manually test:

- Fresh install with mock AI.
- Fresh install with live Gemini.
- Existing data with many lists, products, stores, memories, and recipes.
- Low-connectivity/error cases.
- API quota exhausted case.
- Permission disabled for each major AI area.
- Approve all, approve single, reject all, reject single.
- Partial proposal completion.
- App restart after unresolved proposal.
- Undo after create/add/edit/delete.
- Dark mode and dynamic type in proposal cards.
- Norwegian and English user phrasing.

## Metrics To Track During Testing

| Metric | Target |
|---|---|
| Valid first-turn outcome rate | 95%+ for golden scenarios. |
| Wrong-action proposal rate | Below 2% on golden scenarios. |
| Silent no-op approval rate | 0%. |
| Clarification when ambiguous | 95%+ on ambiguity scenarios. |
| Out-of-scope refusal accuracy | 95%+ without blocking normal grocery requests. |
| Average live AI latency | Under 3 seconds for simple turns where possible. |
| Proposal edit need rate | Track manually; high rate points to parser/resolver issues. |

## Recommended First Implementation Slice

Start with the smallest changes that most improve consistency:

1. Add a richer `AIContextBuilder` with current date, active lists with items, recipe titles, matkasse boxes, stores, and settings.
2. Add semantic payload validation to `AppStore.validate(_:)` for existing `ProposedActionPayload` cases.
3. Add an `AIEntityResolver` for lists, products, stores, recipes, matkasse boxes, and memories.
4. Change Gemini parsing so draft actions pass through resolver/validator before becoming proposal cards.
5. Add pending clarification support for ambiguous list/store/product/recipe/memory targets.
6. Add golden tests for the known manual-testing failures.

This gives immediate behavior improvements while preserving the existing UI and action model.

## Non-Goals For The First Pass

- Do not rebuild every feature tab.
- Do not introduce a cloud backend solely for AI consistency.
- Do not let Gemini directly mutate data.
- Do not rely on prompt changes as the only safeguard.
- Do not expose raw debug traces in production.
- Do not attempt fully autonomous destructive actions.

## Final Definition Of Done

The chat enhancement work is done when:

- Every supported CRUD action has a native validation rule and golden scenario.
- Ambiguous requests produce clarification, not guesses.
- Approved proposals either execute successfully or show a precise failure reason.
- The same user request produces stable action payloads under fixture tests.
- The AI never claims a change was made before native execution succeeds.
- Users can inspect, edit, reject, approve, and undo meaningful changes.
- Debug builds provide enough trace detail to diagnose bad AI behavior quickly.
