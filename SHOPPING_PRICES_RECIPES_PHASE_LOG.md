# Shopping, Prices, and Meals — Handoff Log

Companion to `SHOPPING_PRICES_RECIPES_PHASE_PLAN.md` (which is itself built
on `SHOPPING_PRICES_RECIPES_REDESIGN_PLAN.md`). Append an entry per work
session/phase so any agent (or Josh) can pick this up cold. Newest entry at
the top. Each entry: what changed, why, how it was verified, what's next.

---

## 2026-08-25 — Phase 9 (Prices: AI actions expansion) implemented

Josh confirmed Phase 8 looks good. `xcodebuild ... build` → **BUILD
SUCCEEDED**. This closes out the Prices block — five phases done now,
matching Shopping's five.

**`Models/ProposedAction.swift`:** new `ProposedActionType.mergeProducts`
case (the other four types this phase needed —
`updateProduct`/`deleteProduct`/`updatePriceObservation`/
`deletePriceObservation` — already existed, same "type exists, payload
doesn't" gap Phase 5 closed for Shopping). Added it to `isDestructive`
alongside the delete types, since a merge deletes the source product even
though it isn't itself a "delete" action type. Five new
`ProposedActionPayload` cases matching.

**`Store/AppStore.swift`:**
- `execute(_:)` gained all five cases. `permissionTarget(for:)` extended
  with one new line for `.mergeProducts` (mapped to `(.products, .delete)`
  — it deletes the source product, so gating it at the stricter delete
  permission felt safer than treating it as a mere edit).
- Two new private lookup helpers: `productIndex(matching:)` (exact
  case-insensitive name match, same non-creating pattern as
  `shoppingListIndex(matching:)` from Phase 5) and the more involved
  `mostRecentPersonalObservationIndex(productName:storeBranchName:)` — a
  product can have many historical price observations, so "update/delete
  the price for milk" needs a rule for *which* one. Picked: most recent by
  `observedDate`, optionally narrowed to a store first if one was
  mentioned, and **always excluding `source == .community`** — a chat user
  correcting "their" price shouldn't be able to silently edit or delete
  someone else's community-sourced observation through this path.
- `updateProduct`/`deleteProduct`/`mergeProducts` execute cases all reuse
  `productIndex(matching:)`; `mergeProducts`'s case just resolves both
  names to IDs and calls the existing `mergeProducts(sourceID:targetID:)`
  method Phase 8 already built for the UI merge sheet — no new merge logic,
  just a second entry point into the same one.

**`Services/GeminiAIService.swift`:** five new `functionDeclarations()` +
`parseFunctionCall(_:)` pairs, same `makeFn` pattern as every prior phase.
Risk levels: `high` for `deleteProduct` and `mergeProducts` (both
irreversible-ish — merge folds one product's history into another with no
UI undo path), `medium` for `deletePriceObservation`, `low` for the
update/rename actions.

**Deliberately skipped `MockAIService` this time** (unlike Phase 5, which
added matching keyword triggers there) — the no-API-key fallback is a
convenience for development without a Gemini key, and continuing to hand-
tune keyword heuristics for every new action type is its own maintenance
burden with diminishing return; Phase 5's known-issue entry above already
flags that even the *live* model isn't reliably picking the right target
for actions like this, so investing more in the mock's string-matching
felt like the wrong place to spend effort right now.

**Not committed.** Changed: `Models/ProposedAction.swift`,
`Services/GeminiAIService.swift`, `Store/AppStore.swift`.

### What's next

Review checkpoint: Josh to test via Chat with a live Gemini key — "delete
the milk product" (should require confirmation), "merge tomato and
tomatoes" (should propose merging one into the other), "update the price I
logged for bread to 25 kr". Given the standing known issue about the AI
not reliably targeting the right existing record, it's worth watching
specifically whether `updatePriceObservation`/`mergeProducts` pick the
product the user actually meant, or (like the shopping-list case) go
sideways in a similar way — that would be useful confirming evidence for
the earlier bug note rather than a new, separate problem. Once confirmed,
Shopping and Prices are both fully done (10 phases). Phase 10 (Meals:
rename tab + data model — `MealPlan`/`MealPlanSlot`/`MatkasseBox`/
`MatkasseMeal`) starts the Meals block.

---

## 2026-08-25 — Phase 8 (Prices: product/store detail & trust model) implemented

Josh confirmed Phase 7 looks OK. `xcodebuild ... build` → **BUILD
SUCCEEDED**.

**`Store/AppStore.swift`** — new `// MARK: - Product Management` section:
- `addProductAlias`/`removeProductAlias`/`setProductBarcode` — small
  focused mutators (not one big `updateProduct(...)` with ambiguous
  optional-of-optional semantics for "clear vs. don't change" — same
  reasoning as Phase 5's item mutators).
- `confirmPriceObservation(_:)` — "still accurate" re-confirmation.
  Appends a **new** `PriceObservation` with today's date rather than
  mutating the stale one in place, matching this app's existing
  append-only price-history model (nothing else in the codebase edits a
  `PriceObservation` after creation either).
- `mergeProducts(sourceID:targetID:)` — reassigns every
  `PriceObservation.productID`/`productName` and `ShoppingListItem
  .productID`/`productName` from source to target, folds the source's name
  and aliases into the target's alias list (so old receipts/observations
  that still say the old name remain searchable via alias), keeps the
  target's barcode unless it didn't have one, then deletes the source
  product.

**Unit-price helper now has its first call site** (built inert in Phase
6): `ProductPriceHistoryView` gained a "Unit Price Comparison" section —
latest non-expired observation per store, normalized via
`PriceObservation.normalizedUnitPrice`, sorted cheapest-first with a
"CHEAPEST" badge — only shown when 2+ stores have package-size data to
compare (a single data point isn't a comparison).

**`Features/Prices/PricesView.swift`, `ProductPriceHistoryView`:**
- Split the old flat "All observations" section into "Your Prices" and
  "Community Prices" — the product plan's "community and personal prices
  can share the same product surface, but need separate fields/labels"
  requirement; Phase 7 handled the reverse case (community mode showing a
  match against personal), this is personal-mode showing community
  clearly labeled as a second section rather than mixed in.
- New "Barcode" section (a live `TextField` bound straight to
  `store.setProductBarcode`, empty string treated as clearing it) and
  "Aliases" section (list with swipe-to-delete via
  `removeProductAlias`, add-new via a text field + button).
- New "Merge Duplicate Product" button opens a new `MergeProductSheet`
  (in the same file) — lists every other product, tapping one merges *it*
  into the currently-viewed product and dismisses. One-directional by
  design (pick the duplicate to absorb, not "which one survives") to keep
  the flow to a single tap.

**New file `Features/Prices/StoreDetailView.swift`** (registered in
`project.pbxproj`, same four-piece manual wiring as every prior new file
this session): latest-per-product price list for one branch, a stale
count, and a "Confirm These Prices" section — stale observations whose
product name exact-matches something on an active/planned shopping list or
in a recipe (`importantProductNames`, a `Set<String>` exact-lowercased
match — **not** the `looselyMatchesProductName` fuzzy matcher Phase 7 used
for Needs Prices, since this needed a cheap `Set.contains` for a
potentially large candidate list rather than an O(n²) fuzzy pass; noted as
a real gap, not an oversight — a product named slightly differently on a
list vs. in `priceObservations` won't get flagged as important here). Each
"Confirm These Prices" row has a one-tap "Still Accurate" button wired to
`confirmPriceObservation`. Wired in from `PricesView`'s `.byStore` mode —
the store section header is now a button (`selectedBranch = branch`,
`.sheet(item:)`), matching the existing header-as-button pattern
`.byProduct` mode already used.

**Not committed.** Changed: `Features/Prices/PricesView.swift`,
`Features/Prices/StoreDetailView.swift` (new),
`PrisPilot.xcodeproj/project.pbxproj`, `Store/AppStore.swift`.

### What's next

Review checkpoint: Josh to check a product detail page (barcode field,
adding/removing an alias, the merge flow with two similarly-named test
products, and the unit-price comparison once 2+ stores have package-size
data for the same product) and a store detail page (tap a store header in
Stores mode — stats, and "Confirm These Prices" if anything stale is on an
active list). Once confirmed, Phase 9 (Prices: AI actions expansion —
`updateProduct`/`deleteProduct`/`updatePriceObservation`/
`deletePriceObservation`, plus a chat-triggered merge) is next, closing out
the Prices block the same way Phase 5 closed out Shopping.

---

## 2026-08-25 — Phase 7 (Prices: overview redesign) implemented

`xcodebuild ... build` → **BUILD SUCCEEDED**.

**Closed a gap from Phase 6 first:** the phase plan expected Phase 6 to
extract the product-name matching helper for reuse here, but Phase 6 only
extracted the unit-conversion piece. Fixed now instead of re-deriving a
third copy: pulled `RecipesView.swift`'s private
`RecipeCostEstimate.namesMatch`/`normalisedWords` out into
`String.looselyMatchesProductName(_:)` in `Models/AppModels.swift` (word-
overlap matching — same logic, just shared). `RecipesView.swift`'s
`namesMatch` is now a one-line wrapper calling the shared version, so
recipe costing's behavior is provably unchanged.

**`Store/AppStore.swift`:** new `NeedsPriceEntry` struct + `needsPriceEntries()`
method — unions (a) pending items on active/planned lists with no
`estimatedPrice`, (b) recipe ingredients with no usable price match (via
the now-shared `looselyMatchesProductName`), merged by product name so one
product needed in three places shows once with all three sources listed
(e.g. "Weekly Shop · Taco Night (recipe)").

**`Features/Prices/PricesView.swift`:**
- `PriceViewMode` gained `.needsPrices` and `.community`; existing cases'
  raw values renamed "Product"/"Store" → "Products"/"Stores" to match the
  product plan's exact wording for the four top-level modes.
- Body's content switch restructured to branch per-mode first, each with
  its own empty/search-empty state, instead of the old shared chain that
  only handled `.byProduct` specially and would have silently mis-rendered
  the two new modes.
- **Needs Prices mode:** one row per `NeedsPriceEntry`, each with an "Add
  Price" button opening `AddPriceObservationSheet(prefilledProductName:)`
  via a new `productNameForNewPrice` sheet-state (same prefill pattern
  Phase 3 already used in Shopping's own Needs Price Data section).
- **Community mode:** community-sourced (`source == .community`)
  observations grouped by product, reusing `PriceObservationRow` with a
  new `matchesPersonalPrice: Bool?` param — `true`/`false` when a non-stale
  personal observation exists for the same product+store (`nil` shows
  nothing extra), rendered as "Confirms your price" (green) or "Differs
  from your price" (blue). This is the product plan's "if values match,
  show that the community confirms the price" requirement.
- Summary stat row gained two new tiles (only shown when non-zero): "need
  price" (red) and "community" (purple, counts unique community products).

**Not committed.** Changed: `Models/AppModels.swift`,
`Features/Recipes/RecipesView.swift`, `Features/Prices/PricesView.swift`,
`Store/AppStore.swift`.

### What's next

Review checkpoint: Josh to check the Prices tab's four-mode segmented
control — Needs Prices should list anything missing a price across active/
planned Shopping lists and recipes, with working Add Price buttons;
Community mode needs actual `source: .community` observations to populate
(there's no seeded community data, so this may show its empty state unless
some exist from earlier testing/chat). Also worth re-confirming Products/
Stores modes still work exactly as before — this phase restructured the
body's branching logic around them even though their content views
(`productSections`/`storeSections`) weren't touched. Once confirmed, Phase
8 (Prices: product/store detail & trust model — unit-price comparison row,
Store detail screen, duplicate-product merge tool) is next.

---

## 2026-08-25 — Phase 6 (Prices: data model tweaks) implemented

Shopping's five phases are done; this starts the Prices block. `xcodebuild
... build` → **BUILD SUCCEEDED**. This phase touches only
`Models/AppModels.swift` — no new files, no `project.pbxproj` surgery
needed this time.

**Stale threshold, `PriceObservation.isStale`:** `ageInDays > 30` →
`> 60`, per the product plan's confirmed decision ("Prices become stale
after 60 days by default"). Confirmed no UI hardcodes "30 days" anywhere
(grepped `isStale`/`freshnessAdjustedConfidence`/"30 day" across the whole
codebase) — every call site (`PricesView`, `PriceComparisonView`,
`ShoppingListDetailView`, `RecipesView`'s cost estimator, `AppStore`'s
optimizer/outlier logic) reads the computed property, so they all picked up
the new threshold automatically with no call-site changes needed.

**Confidence decay, `freshnessAdjustedConfidence`:** old bands were
0–30/31–60/61–90/91+, which no longer lined up with the new 60-day stale
line (a "stale" 61-day-old price was already two decay steps in under the
old bands). Rebanded to 0–60 (full)/61–120 (one step down)/121–180 (two
steps down)/181+ (Unconfirmed) — same three-step shape, just rescaled
around the new line.

**New unit-price normalization helper**, the other half of this phase:
extracted the *idea* behind `RecipesView.swift`'s existing
`RecipeCostEstimate.baseQuantity`/`unitFamily` (kept those in place,
untouched — didn't want to risk regressing recipe costing over an unrelated
Prices phase) into a fresh, more general home:
- `MeasurementUnit.baseUnitsPerUnit` (grams/ml/count-of-1 per unit) and
  `.normalizedComparisonUnit` (kg for weight, l for volume, self for
  pieces/packs) — two small extensions on the existing enum.
- `PriceObservation.normalizedUnitPrice: UnitPrice?` — `nil` when no
  package size was recorded, otherwise the price converted to kr/kg, kr/l,
  or kr/stk.
- New `UnitPrice` struct (`value: Decimal`, `unit: MeasurementUnit`, plus a
  `formatted(currencySymbol:)` helper) — intentionally not `Codable`/stored
  anywhere, it's a derived display value computed on demand.

Not wired into any UI yet — Phase 8 (Prices: product/store detail & trust
model) is where the plan actually calls for a "unit-price comparison row,"
and that's what this was built for. Landing the model piece now, on its
own, so Phase 8 doesn't have to do model work and UI work in the same pass.

**Not committed.** Changed: `Models/AppModels.swift` only.

### What's next

Review checkpoint: Josh to confirm nothing regressed in Prices/Shopping/
Meals cost displays now that "stale" means 60 days instead of 30 (fewer
things should show as stale/grayed-out than before). There's no new UI
surface from this phase specifically to test — the unit-price helper has
no call site yet. Once confirmed, Phase 7 (Prices: overview redesign —
Needs Prices and Community as real top-level modes) is next.

---

## 2026-08-25 — Known issue: AI list matching creates duplicates instead of finding the existing list

Josh tested Phase 5 live via Chat: "some things are janky." Concrete repro
he gave: asked to "add milk to the tacos list" — the assistant created a
**new** shopping list and added milk to that, instead of finding and using
the existing one. He said there were "other weird things" too but this was
the main one, and asked to note it and come back later rather than fix now
— continuing on to Phase 6.

**Likely mechanism (not yet confirmed by fixing it, just read the code
this session already touched):** `AppStore.findOrCreateShoppingList(name:)`
(pre-existing, not new this session — used by `addShoppingListItem` and
now also `addRecipeToShoppingList` from Phase 5) does an **exact**
case-insensitive name match:
```swift
if let existing = shoppingLists.first(where: { $0.name.lowercased() == name.lowercased() }) { ... }
```
If the model's `listName` argument doesn't come back as a byte-for-byte
match to the real list's name (e.g. real list is "Taco Night" and the model
says "Tacos", "Taco List", or similar), this silently falls through to
creating a brand-new list rather than fuzzy-matching or asking for
clarification. The system prompt does tell the model the exact available
list names (`context.availableShoppingLists`), so this is at least partly a
prompting/model-adherence problem, not purely a matching-code problem — but
the matching code has no safety net for the mismatch either way. Compounding
it: `ActionProposalView`'s summary text ("Add milk to Tacos") looks
identical whether it's about to reuse an existing list or silently create a
new one, so there's no way for the user to catch this at approval time
before it happens.

This same exact-match brittleness applies to every lookup this session
added in Phase 5 (`shoppingListIndex(matching:)`,
`shoppingListItemIndex(in:matchingProduct:)` for update/complete/remove/
delete) and to product-name matching more broadly — likely the shape of at
least some of the "other weird things" Josh mentioned without a specific
repro.

**Not fixed yet — deferred per Josh's instruction.** When this gets picked
up: consider (a) fuzzy/substring list-name matching similar to
`RecipesView.swift`'s existing `namesMatch` word-overlap matcher rather
than exact-match, (b) having the proposed-action summary explicitly say
"(new list)" when `findOrCreateShoppingList` is about to create rather than
reuse, and/or (c) tightening the system prompt to more forcefully require
reusing an exact string from the provided list. Worth getting the other
"weird things" repro'd concretely too before attempting a fix, rather than
guessing at all of them from one example.

---

## 2026-08-25 — Phase 5 (Shopping: AI actions expansion) implemented

Josh confirmed Phases 3 and 4 look good on-device. `xcodebuild ... build` →
**BUILD SUCCEEDED**. Not yet tested via live Chat — that's the check for
this phase (needs a live Gemini key + actually talking to the assistant,
not just a simulator screenshot).

**`Models/ProposedAction.swift`:** six new `ProposedActionPayload` cases —
`updateShoppingList`, `deleteShoppingList`, `updateShoppingListItem`,
`completeShoppingListItem`, `removeShoppingListItem`,
`addRecipeToShoppingList`. All six `ProposedActionType` cases already
existed (with `displayName`/`systemImage`/`isDestructive` already correct)
— this phase was purely closing the payload/execution gap, as the phase
plan described.

**`Store/AppStore.swift`:**
- `execute(_:)` gained all six cases. Two new private lookup helpers:
  `shoppingListIndex(matching:)` and
  `shoppingListItemIndex(in:matchingProduct:)` — deliberately *not*
  auto-creating a list on miss (unlike `findOrCreateShoppingList`, which
  `addShoppingListItem`/`addRecipeToShoppingList` still use): an update/
  delete/complete/remove targeting a list that doesn't exist should be a
  silent no-op, not a surprise new list.
- `addRecipeToShoppingList` converts each `RecipeIngredient` into a
  `ShoppingListItem` with `requestedQuantity` formatted as `"<qty> <unit>"`
  (e.g. "400 g") — reuses `findOrCreateShoppingList` since adding a
  recipe's ingredients *should* create the target list if it doesn't
  exist yet (matches `addShoppingListItem`'s existing behavior).
- Undo: added `.addRecipeToShoppingList` to both `canUndoActivityTag` and
  the `.addShoppingListItem` case of `undoActivityTag` (identical removal
  logic — added items get removed by ID from whichever list holds them).
  **Deliberately did not add undo for the other four** — this app's undo
  model only ever supported "created records" (delete-by-ID), and
  update/delete/complete/remove actions don't fit that shape without
  snapshotting prior state, which nothing else in the codebase does either
  (e.g. `updateStore`/`deleteStore` aren't undoable today). Kept consistent
  with the existing pattern rather than inventing a new one for just this
  phase.

**`Services/GeminiAIService.swift`:** six new `functionDeclarations()`
entries and matching `parseFunctionCall(_:)` cases, following the file's
existing `makeFn`/`strProp`/`boolProp` pattern exactly. `plannedDate` is
passed as a `YYYY-MM-DD` string (Gemini's function-calling schema has no
native date type) and parsed via a new `Self.dateFormatter` (UTC,
gregorian) — mirrors how the rest of the file already treats dates as
plain strings elsewhere (e.g. receipt parsing). Risk levels: `high` for
`deleteShoppingList`, `medium` for `removeShoppingListItem` (both already
`isDestructive` per their `ProposedActionType`), `low` for the rest —
matches the existing `deleteStore`/`updateStore`/`setStoreEnabled`
gradient in the same file.

**`Services/MockAIService.swift`:** added matching keyword-triggered mock
responses (`completeItemResponse`, `removeItemResponse`,
`deleteListResponse`, dispatched on "mark ... bought/done", "remove ...
from", "delete ... list") so the no-API-key fallback path stays
representative of the app's actual capabilities, not just the pre-Phase-5
ones. Refactored the inline product-guessing logic in `addToListResponse`
into a shared `knownProduct(from:)` helper reused by all three new
responses rather than copy-pasting the same four-branch if/else three more
times. Kept the existing convention of hardcoding "Weekly Shop" as the
target list (every existing mock response already does this — the mock
service has never done fuzzy list-name matching against
`context.availableShoppingLists`, so this doesn't introduce a new
capability tier just for the new actions).

**Not committed.** Changed: `Models/ProposedAction.swift`,
`Services/GeminiAIService.swift`, `Services/MockAIService.swift`,
`Store/AppStore.swift`.

### What's next

Review checkpoint: Josh to test via Chat with a live Gemini key — "mark
milk as bought", "remove bread from the list", "add my taco recipe to
Weekly Shop", "delete my old test list" — confirming each proposes the
right action, approval executes correctly, and destructive ones
(delete list, remove item) still require explicit confirmation. Also worth
trying the no-API-key Mock path for the same phrasings since that changed
too. Once confirmed, Shopping's five phases are complete and Phase 6
(Prices: data model tweaks — 60-day stale threshold, unit-price
normalization helper) starts the Prices block.

---

## 2026-08-25 — Phase 4 (Shopping: in-store mode) implemented

`xcodebuild ... build` → **BUILD SUCCEEDED**. Not yet on-device tested —
per Josh's note this turn, we're now reviewing after every phase before
continuing, so this is the next thing for him to check.

**New file `Features/Shopping/InStoreModeView.swift`** (registered in
`project.pbxproj` the same manual way as every new file this project needs —
`PBXFileReference` + `PBXBuildFile` + Sources-phase entry + group child,
all four, checked this time against a mistake caught mid-edit: earlier in
this file's own creation, `\.actualPrice ?? $0.estimatedPrice` was
originally written as an invalid keypath/closure mix
(`compactMap(\.actualPrice ?? $0.estimatedPrice)`) — SourceKit's live
diagnostics flagged it immediately as "anonymous closure argument not
contained in a closure" and it was fixed before the build was even run,
to a proper closure: `compactMap { $0.actualPrice ?? $0.estimatedPrice }`).

Full-screen (`fullScreenCover`), one-store-at-a-time mode: large
checkboxes (32pt vs. the normal row's ~24pt), a running subtotal/spent
band, a segmented store-switcher when the trip has more than one store,
and a blue-highlighted "next item" focus row (first uncompleted item).
Completing every item at the current store shows a "This store is done!"
banner with a "Continue to `<next store>`" button when another store still
has pending items, plus a light success haptic
(`UINotificationFeedbackGenerator`, gated only on the
`pendingItems.count` transition to zero — not wrapped in a Reduce Motion
check since haptics aren't a Reduce-Motion-governed effect). Reuses the
exact same `toggle`/`captureActualPrice` logic and `PriceCaptureSheet` as
the main detail view rather than duplicating completion semantics —
in-store mode is a different *presentation* of the same list state, not a
separate data path.

**Entry point:** `Features/Shopping/ShoppingListDetailView.swift` gained a
toolbar "checklist" icon button (only shown when at least one priced,
assigned, pending item exists — `firstStoreWithPendingItems`), opening
`InStoreModeView` as a `fullScreenCover` seeded with that first store.

**Not committed.** Changed: `Features/Shopping/InStoreModeView.swift`
(new), `Features/Shopping/ShoppingListDetailView.swift`,
`PrisPilot.xcodeproj/project.pbxproj`.

### What's next

**Review checkpoint per Josh's instruction this turn:** stopping here for
him to test Phases 3 and 4 on his phone (Phase 2 is already confirmed
working). Once he confirms nothing's broken, next up is Phase 5 (Shopping:
AI actions expansion) — closing the gap between what `ProposedActionType`
already lists and what `AppStore.execute(_:)` implements for shopping
lists, plus wiring the new function declarations into
`Services/GeminiAIService.swift`'s `functionDeclarations()`/
`parseFunctionCall(_:)` (already read and scoped this file this turn, no
code written yet). Continuing to build without a manual test gate between
*every single* phase was the earlier assumption from "keep going through
all phases" — corrected now to: build + log each phase, but pause for
Josh's on-device check before starting the next one.

---

## 2026-08-25 — Phase 3 (Shopping: list detail redesign) implemented

Josh tested Phase 2 on-device ("starting to look smart") and asked to keep
going through all remaining phases before circling back to refine — the
tabs feed into each other, so the plan continues phase-by-phase without a
manual test gate after each one for now.

All of the phase plan's Phase 3 tasks done, plus one from Phase 1's
groundwork put to use for the first time (`selectedPriceObservationID`).
`xcodebuild ... build` → **BUILD SUCCEEDED**.

**Split `ShoppingListDetailView`, `ShoppingItemRow`, and `PriceCaptureSheet`
out of `ShoppingView.swift`** into a new
`Features/Shopping/ShoppingListDetailView.swift` (per the phase plan's own
suggestion — the file was already 700+ lines before this redesign).
`ShoppingView.swift` is back down to just the overview + `ShoppingListCard`
(333 lines). Same manual `project.pbxproj` wiring as Phase 2's new file
(new `PBXFileReference`/`PBXBuildFile`/Sources-phase entries, generated IDs
checked for collisions) — now a confirmed pattern for every future new file
under `Features/`.

**`Store/AppStore.swift`** — new methods: `moveItem(_:in:toBranchID:)`
(manual store reassignment, reuses the existing private `bestObservation`
lookup), `assignPriceObservation(_:toItem:in:)` (assign a *specific* known
observation — used by the community-price CTA), `addSubstituteCandidate`/
`useSubstitute` (substitute tracking — swapping keeps the old name as a
candidate so it's reversible, and clears price/store since the substitute
needs its own pricing), `undoCompleteItem` (explicit undo, distinct from
just re-tapping the row). `optimizeShoppingList(_:)` gained a
`maxStoresOverride: Int?` param for the new "force one store" toggle,
without touching the actual `maxSupermarketCount` setting.

**`DesignSystem/GlassTheme.swift` / `App/RootTabView.swift`:** added a
`switchToSettingsTab` environment hook, same shape as Phase 2's
`switchToChatTab` — used by the new optimization-controls readout row
("Up to N stores · saves ≥ kr X to add one") so it can link out to Settings
instead of duplicating editable controls in the detail view.

**New `ShoppingListDetailView` body,** section by section:
- **Trip summary band:** kept the existing optimization banner + running
  total, added a stat-pair row (store count, priced/unpriced count) sourced
  from either the live `optimizationResult` or a new `fallbackResult(from:)`
  that synthesizes the same shape from the list's persisted
  `optimizationSnapshot` (Phase 1) — so the stat pair doesn't flicker blank
  while the optimizer's `Task` is still in flight, and still shows
  something for a list that was optimized in a previous session.
- **Optimization controls:** new "Force one store" toggle (re-runs
  optimization on change via `maxStoresOverride: 1`) plus the settings
  readout row above.
- **Store sections:** header now shows item count + subtotal, and a small
  orange warning icon when any item in that store's group has a
  freshness-adjusted confidence of Low/Unconfirmed — the first real use of
  Phase 1's `selectedPriceObservationID` field, looked up against
  `store.priceObservations` to get the actual confidence rather than
  guessing from the item alone. Also added `.textCase(nil)` on these
  headers, which the old code didn't have — the default List section-header
  uppercase transform was rendering store names like "Kiwi Majorstuen" as
  "KIWI MAJORSTUEN"; fixed as a drive-by since the new header content made
  it obvious.
- **Needs Price Data section:** replaces the old implicit "Unassigned"
  store-group bucket entirely. Each row: Add Price (opens
  `AddPriceObservationSheet(prefilledProductName:)`, already supported that
  parameter — re-runs the optimizer on dismiss so the new price gets
  picked up automatically), Use Community Price (only shown when a
  non-expired community observation exists for that product; assigns the
  cheapest match directly via `assignPriceObservation`), and a barcode-scan
  icon. **Scoped down from the plan's literal text:** the barcode button
  opens the same general `.addToList` scanner as the toolbar's existing
  barcode button (adds a new item by barcode) rather than fixing *this*
  item's price specifically — `BarcodeScannerView`'s `.priceEntry` mode has
  no product-name-prefill path today, and building one felt like scope
  creep for a phase that's already touching a lot of surface. Noted here
  rather than quietly shipping a half-connected button.
- **Completed section:** now a collapsible `DisclosureGroup` (default
  collapsed) instead of a flat section, each row swipeable for an explicit
  Undo (`undoCompleteItem` — clears `actualPrice` too, distinct from
  tap-to-toggle which is still there and still just flips `isCompleted`).
- **Item rows** (in store sections): trailing swipe → Move (opens
  `MoveItemToStoreSheet`, a plain store-picker driving `moveItem`), leading
  swipe → Substitute (opens `SubstituteItemSheet` — list existing
  candidates with a one-tap "Use", plus a text field to add a new
  candidate idea via `addSubstituteCandidate`).

**Verification:** compile-only (`xcodebuild build` → BUILD SUCCEEDED). Per
Josh's message this turn, **not tested on-device this phase** — he's
testing on his phone directly rather than having the agent drive a
simulator, so the plan is to keep landing phases and let him batch-test
once more of the surface exists.

**Not committed.** Changed: `App/RootTabView.swift`,
`DesignSystem/GlassTheme.swift`, `Features/Shopping/ShoppingView.swift`
(trimmed), `Features/Shopping/ShoppingListDetailView.swift` (new),
`PrisPilot.xcodeproj/project.pbxproj`, `Store/AppStore.swift`.

### What's next

Phase 4 (Shopping: in-store mode) is next, explicitly marked optional/
stretch in the phase plan — large checkboxes, one store at a time, fast
actual-price entry. Continuing straight through per Josh's instruction to
land all phases before refinement testing.

---

## 2026-08-25 — Phase 2 (Shopping: overview screen redesign) implemented

All of the phase plan's Phase 2 tasks done. `xcodebuild -project
PrisPilot.xcodeproj -scheme PrisPilot -sdk iphonesimulator build` →
**BUILD SUCCEEDED**.

**New file `Features/Shopping/ShoppingOverviewComponents.swift`:**
`ShoppingListSegment` enum (active/planned/completed/archived, with per-case
empty-state copy), `ShoppingSummaryHeader` (horizontal stat-tile row: active
count, next planned date, estimated spend, missing-price count),
`ShoppingPrimaryActionsRow` (New List / Optimize All / Ask AI, `.glass`
button style). This needed manual `project.pbxproj` surgery — this project
uses `PBXFileSystemSynchronizedRootGroup` only for `DesignSystem/` and the
`PrisPilot/` asset folder; `Features/`, `Models/`, `Store/` are plain
`PBXGroup`s with an explicit `PBXFileReference`/`PBXBuildFile` pair per
file, so a new file written straight to disk in `Features/Shopping/` does
**not** get picked up automatically — confirmed by a first build that failed
with "cannot find type in scope" for everything the new file defined. Added
the file reference, build file, and Sources-phase entry by hand (new
24-hex-char IDs generated via `openssl rand -hex 12`, checked against the
existing file for collisions first). Worth remembering for every future
phase that adds a new file under `Features/`, `Models/`, or `Store/` — it is
not optional and won't surface as a Swift error, it surfaces as a
whole-file "cannot find X in scope" cascade that looks like something else
broke.

**`DesignSystem/GlassTheme.swift` / `App/RootTabView.swift`:** added a
`switchToChatTab: () -> Void` `@Entry` environment value (defaults to a
no-op so previews don't crash), set by `RootTabView` to its own
`selectTab(.chat)`. This is the general "jump to Chat from another tab"
hook the phase plan's Prices/Meals phases will also want for their own
"Ask AI" entry points — built once here rather than only for Shopping.

**`Features/Shopping/ShoppingView.swift`** — root view rebuilt:
- Header summary band (via `ShoppingSummaryHeader`), sourced from
  `store.activeLists`/`store.plannedLists` regardless of which segment is
  selected — "next planned date" filters out past dates so a stale
  `plannedDate` on an active list doesn't show as the next shop.
- Segmented control (`ShoppingListSegment`) replaces the old flat
  "all active lists" list; each segment reads the Phase 1 computed
  properties (`activeLists`/`plannedLists`/`completedLists`/`archivedLists`)
  and gets its own `ContentUnavailableView` copy when empty.
- Primary actions row: New List opens the existing `AddShoppingListSheet`;
  Optimize All loops `store.optimizeShoppingList(_:)` over every active list
  (only shown on the Active segment, and only when there's at least one
  enabled store branch); Ask AI calls the new `switchToChatTab()` hook.
- Context menu per list card now branches on `list.status`: Planned gets
  "Start Shopping" (new `AppStore.activateList(_:)`), Active gets "Mark
  Completed"/"Archive", Completed gets "Archive"/"Reopen", Archived gets
  "Reopen" — all backed by the Phase 1 status-transition methods, wired to
  UI for the first time. Delete stayed available in every state.

**`ShoppingListCard`** (same file): restructured from a single `HStack` into
a `VStack` (main row + a conditional badge row) rather than a new type, to
keep `NavigationLink`/`matchedTransitionSource` call sites unchanged. Badge
row shows: planned-date badge (relative format), store-count-or-name badge
and a green savings badge when `optimizationSnapshot` is populated, and an
orange "N need price" badge from a per-card missing-price count. Row only
renders at all when there's something to show.

**`Features/Shopping/ManualEntrySheets.swift`** (`AddShoppingListSheet`):
setting a planned date now also sets `list.status = .planned` (a product
decision this phase had to make on the spot — the phase plan didn't specify
it, "Assumed answers" section in the plan doc didn't cover it either). A new
list without a planned date still starts Active, unchanged. Added a form
footer explaining the Planned behavior so it isn't a silent surprise. Flag
this one if it's not the right call — an easy alternative is a separate
Active/Planned picker independent of the date toggle.

**Verification:** compiles clean. Attempted an actual on-device/simulator
screenshot pass (per this project's usual practice from
`LIQUID_GLASS_REDESIGN_LOG.md` and this session's own instructions to
verify UI before calling it done) — got as far as installing and launching
the built app on a booted simulator (`iPhone 17 Pro`,
`55B9DDA6-0EE5-493F-AD4F-DAA9C3F7C563`) and screenshotting the (correctly
rendered, pre-existing) onboarding screen, but this sandbox has no
accessibility/automation permission (`osascript`/System Events returned
"not allowed assistive access"), so simulated taps to get past onboarding
into the Shopping tab weren't possible, and no `idb` or other UI-automation
tool is installed either. Started down the path of a temporary local-only
build tweak (default tab → Shopping, `onboardingCompleted` default → true,
purely to screenshot layout) but **Josh asked mid-task to skip this and
test on his own phone instead** — both temporary edits were reverted
(`git diff --stat` confirmed no leftover changes beyond the real Phase 2
diff) and the test install was removed from the simulator
(`simctl uninstall`). Final rebuild after reverting: green. **So: verified
by compilation only, not visually** — Josh is testing live.

**Not committed.** Changed: `App/RootTabView.swift`,
`DesignSystem/GlassTheme.swift`, `Features/Shopping/ManualEntrySheets.swift`,
`Features/Shopping/ShoppingView.swift`,
`Features/Shopping/ShoppingOverviewComponents.swift` (new),
`Models/AppModels.swift` (Phase 1 leftover, unchanged this phase),
`PrisPilot.xcodeproj/project.pbxproj`, `Store/AppStore.swift`.

### What's next

Josh to test Phase 2 on his phone: the four-segment Shopping overview,
creating a planned-date list and confirming it lands in Planned not Active,
"Start Shopping"/"Mark Completed"/"Archive"/"Reopen" from the context menu,
and Optimize All against real price data. Once confirmed, Phase 3 (Shopping:
list detail redesign) is next — trip summary band, real optimization
controls, per-store subtotals, move-to-store/substitute item actions, and a
dedicated Needs Price Data section, per
`SHOPPING_PRICES_RECIPES_PHASE_PLAN.md`.

---

## 2026-08-25 — Phase 1 (Shopping: data model foundation) implemented

All of the phase plan's Phase 1 tasks done. `xcodebuild -project
PrisPilot.xcodeproj -scheme PrisPilot -sdk iphonesimulator build` →
**BUILD SUCCEEDED**. No UI changed — this phase is pure data-layer, exactly
as scoped.

**`Models/AppModels.swift`:**
- `ListStatus` gained `.planned = "Planned"`.
- `ShoppingList` gained `completedAt: Date?`, `archivedAt: Date?`,
  `optimizationSnapshot: OptimizationSnapshot?` (new `Codable` struct:
  `chosenStores`, `estimatedOneStoreTotal`, `optimizedTotal`, `savings`,
  `unpricedItemCount`, `optimizationDate`).
- `ShoppingListItem` gained `selectedPriceObservationID: UUID?` and
  `substituteCandidateNames: [String]?`.
- All new fields are `Optional`. This was a deliberate choice beyond what
  the phase plan spelled out: Swift's compiler-synthesized `Decodable`
  calls `decodeIfPresent` for `Optional`-typed properties automatically, so
  old persisted JSON (missing these keys entirely) decodes cleanly with
  `nil` — no custom `init(from:)` needed, and critically, no risk of
  `loadSnapshot()` failing and silently wiping Josh's existing saved data
  on next launch (that failure mode was flagged as a risk in the phase plan
  itself, for the *next* phase that adds new top-level arrays — turns out
  it also applied here as a nested-type-decoding gotcha, just avoided by
  keeping every new field Optional rather than giving
  `substituteCandidateNames` a non-optional `[String] = []` default as the
  phase plan's prose literally described).
- Confirmed no change was needed in `Store/SwiftDataPersistence.swift`:
  `AppStoreSnapshot` decodes `[ShoppingList]` as one field via
  `container.decode([ShoppingList].self, forKey: .shoppingLists)`, which
  defers to `ShoppingList`'s own `Decodable` conformance per element — so
  the snapshot-level `decodeIfPresent(...) ??` pattern called out in the
  phase plan's "Current foundation" section only actually applies when a
  *new top-level array* is added directly to `AppStoreSnapshot` (that's
  Phase 10, adding `mealPlans`/`matkasseBoxes`), not when new fields are
  added to a type already nested inside an existing array.

**`Store/AppStore.swift`:**
- Added `plannedLists`, `completedLists`, `archivedLists` computed
  properties next to the existing `activeLists`.
- Added a new `// MARK: - Shopping List Status` section:
  `completeShoppingList(_:)`, `archiveShoppingList(_:)` (each sets status +
  the matching timestamp, persists), `reopenList(_:)` (sets status back to
  `.active`, clears both timestamps, persists).
- `optimizeShoppingList(_:)`: now writes `optimizationSnapshot` onto the
  list after computing assignments (moved `persistNow()` to after the
  snapshot write so it's included in the same save). Also went one step
  further than the phase plan's literal text: `ItemAssignment` (the
  optimizer's internal struct) gained an `observationID: UUID` field
  threaded through both the baseline and the greedy-improvement candidate
  loop, and Step 5 (writing assignments back to items) now sets each
  item's `selectedPriceObservationID` alongside the existing
  `assignedStoreBranch`/`estimatedPrice` writes (clearing it to `nil` in
  the unassigned branch too). The phase plan had deferred wiring that field
  to Phase 3 ("manual reassignment"), but `bestObservation(...)` already
  hands back the exact `PriceObservation` at the point the optimizer picks
  a price — threading its `id` through cost nothing extra and means the
  field is never in a half-populated state (set by manual reassignment
  later, but blank for every item the *optimizer* touches) once Phase 3
  starts reading it.

**Not committed** — per standing instruction, only committing when asked.
Changed files: `Models/AppModels.swift`, `Store/AppStore.swift`.

### What's next

Phase 2 (Shopping: overview screen redesign) — rebuild `ShoppingView`'s root
screen with the header summary band, the Active/Planned/Completed/Archived
segmented control (now backed by real data from this phase), and extend
`ShoppingListCard` with the stores-required/savings/warning badges sourced
from `optimizationSnapshot`. Also needs `plannedDate` exposed as an editable
field in `AddShoppingListSheet` (`Features/Shopping/ManualEntrySheets.swift`),
which currently only sets `name`/`scope`.

---

## 2026-08-25 — Plan created, no implementation yet

Read `SHOPPING_PRICES_RECIPES_REDESIGN_PLAN.md` (the product plan, already
existing in the repo) and audited the current codebase against it: models
(`Models/AppModels.swift`), persistence (`Store/SwiftDataPersistence.swift`),
store logic (`Store/AppStore.swift`), action system
(`Models/ProposedAction.swift`), and the three existing feature views
(`Features/Shopping/ShoppingView.swift`, `Features/Prices/PricesView.swift`,
`Features/Recipes/RecipesView.swift`, plus their sheets in
`ManualEntrySheets.swift` and `PriceComparisonView.swift`).

Wrote `SHOPPING_PRICES_RECIPES_PHASE_PLAN.md`: 13 numbered phases
(Shopping: data model → overview → detail → in-store mode → AI actions;
Prices: data tweaks → overview → product/store detail → AI actions; Meals:
rename+data model → week planner → shopping-list generation+matkasse → AI
actions), each with concrete files, tasks, and a definition of done. Also
recorded explicit default answers to the product plan's open questions (e.g.
Shopping defaults to Active view, one list = one trip, 60-day stale
threshold, matkasse ingredients stored but excluded from shopping-list
generation by default) so implementation doesn't stall waiting for product
decisions that weren't actually blocking. A Backlog section captures the
product plan's "nice-to-have"/"ambitious" items that are explicitly *not*
scheduled into a phase yet.

Key things this pass surfaced that aren't obvious from the plan doc alone:
- `AppStoreSnapshot` (`Store/SwiftDataPersistence.swift`) is a hand-written
  `Codable` with `decodeIfPresent(...) ?? default` per field — every phase
  that adds a new top-level array/type to `AppStore` must also update this
  file's `CodingKeys` and decoder, or the new data silently doesn't persist
  across launches. Called out explicitly in the phase plan's "Current
  foundation" section since it's easy to forget mid-phase.
- `ProposedActionType` (`Models/ProposedAction.swift`) already lists many
  action types (update/delete recipe, update/delete price observation, etc.)
  that have no corresponding `ProposedActionPayload` case and no
  implementation in `AppStore.execute(_:)` — the enum is ahead of the
  implementation. Each tab's AI-actions phase closes that specific gap
  rather than inventing new action types from scratch.
- `RecipesView.swift`'s `RecipeCostEstimate` already has real ingredient
  name-matching and unit-conversion logic (`namesMatch`, `baseQuantity`,
  `unitFamily`) that Prices Phase 7/8 and Meals Phase 12 should reuse/
  generalize rather than re-implement a second or third time.
- `AppSettings` already has `travelCostPerKilometer` and
  `fixedStoreVisitCost` fields, but `optimizeShoppingList(_:)` in
  `Store/AppStore.swift` never reads them — flagged as a known gap, pushed
  to Backlog rather than silently left implicit.

**Nothing has been built yet.** No Swift files changed. Working tree is
still whatever it was before this session (Liquid Glass Phase 6 changes per
`LIQUID_GLASS_REDESIGN_LOG.md`, uncommitted).

### What's next

Start Phase 1 (Shopping: data model foundation) from
`SHOPPING_PRICES_RECIPES_PHASE_PLAN.md`: add `ListStatus.planned`,
`ShoppingList.completedAt`/`archivedAt`/`optimizationSnapshot`,
`ShoppingListItem.selectedPriceObservationID`/`substituteCandidateNames`,
the corresponding `AppStore` computed properties/methods, and the
`AppStoreSnapshot` persistence updates — no UI changes in that phase, just
the foundation Phase 2/3 will bind to.

---
