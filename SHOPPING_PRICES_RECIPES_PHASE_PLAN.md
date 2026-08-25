# Shopping, Prices, and Meals — Implementation Phase Plan

Companion to `SHOPPING_PRICES_RECIPES_REDESIGN_PLAN.md` (the product plan). That
document says *what* and *why*. This document says *in what order, in what
slices, touching which files*, so the work can be built and shipped
incrementally instead of as one giant change.

Progress and handoff notes go in `SHOPPING_PRICES_RECIPES_PHASE_LOG.md` —
update it at the end of every phase (see that file for the required format).

## How to use this plan

- Work top to bottom. Each phase should compile (`xcodebuild build`) and be
  manually testable in the simulator/device before moving to the next.
- A phase is small enough to land as one focused diff. If a phase starts
  sprawling, stop and split it rather than quietly growing scope.
- "Definition of done" per phase is the bar for calling it finished — not
  aspirational, just: does it build, does it work, is old functionality
  intact.
- Order follows the product plan's own Build Strategy: **Shopping first,
  Prices second, Meals third**, with AI-action expansion for each tab done
  right after that tab's data/UI lands (per the product plan's Phase Order
  item 5) rather than saved for one big action phase at the end.
- Ambitious/nice-to-have feature-bank items are **not** phases here. They're
  listed in the Backlog section at the bottom and only get promoted into a
  numbered phase when explicitly requested.

## Assumed answers to the product plan's open questions

The product plan left several open questions per tab. Building requires picking
something. These are the defaults this plan builds against — flag any of them
before starting the phase that depends on it if they're wrong:

- **Shopping default view:** Active lists (not "next planned trip"). Matches
  current behavior; revisit once Planned lists are common.
- **One list = one trip.** No multi-trip lists. Matches the current data
  model (`ShoppingList` has one `plannedDate`, one item set).
- **Stale price handling in optimization:** warning only, no exclusion.
  Optimizer already excludes expired promotions; extending it to exclude
  stale prices outright is a later, separate decision once the 60-day
  threshold has been live for a while.
- **Travel cost / store-visit effort in optimization:** deferred past the
  first Shopping rebuild. `travelCostPerKilometer` and `fixedStoreVisitCost`
  already exist in `AppSettings` but the optimizer doesn't read them yet —
  noted as a Backlog item, not blocking Phase 1–5.
- **Completed vs. archived lists:** stay separate, no auto-archive delay.
  Matches the current `ListStatus` split.
- **List templates:** not in the first build. Backlog item.
- **Product-name matching strictness (Prices):** keep the existing
  normalized-word-overlap matcher (already used by recipe costing); no new
  fuzzy-matching system in the first pass.
- **Package-size-normalized comparisons (kr/kg etc.):** build the unit-price
  helper as part of Phase 8 (Prices product detail), not before.
- **Price trend charts:** deferred. Backlog item.
- **"Needs prices for next shop" queue:** in scope for Phase 7 (Prices
  overview), sourced from active + planned shopping lists.
- **Receipt image attachment:** deferred. Backlog item.
- **Meal plan default view:** weekly. Fortnight/month are view-mode toggles
  added later if weekly proves out.
- **Matkasse meals storing ingredients:** store them, but exclude from normal
  shopping-list generation by default (per the product plan's confirmed
  decision) — a box can still have ingredients recorded for cost tracking.
- **Matkasse cost tracked separately from grocery spend:** yes — `MatkasseBox`
  gets its own price field, not merged into shopping totals.
- **"Already have at home" pantry flag:** not in the first Meals build.
  Backlog item.
- **Recipe photos:** not in the first Meals build. Backlog item.
- **AI-generated recipes saved immediately vs. drafted:** drafted first,
  approved via the existing `ProposedAction` flow (consistent with how every
  other AI-created record already works in this app).

## Current foundation (verified against the code, 2026-08-25)

So phases don't re-derive this from scratch:

- **Models** (`Models/AppModels.swift`): `ShoppingList`/`ShoppingListItem`
  (status: active/completed/archived only — no `planned`), `PriceObservation`
  (stale = >30 days, not the product plan's 60), `Product`, `Recipe`/
  `RecipeIngredient` (no meal-plan/matkasse types at all yet), `StoreBranch`/
  `SupermarketChain`, `CommunityContribution`, `AppSettings` (already has
  `maxSupermarketCount`, `minimumAdditionalStoreSavings`,
  `travelCostPerKilometer`, `fixedStoreVisitCost`, `cheapestDefinition`,
  `participatesInCommunityPricing`).
- **Persistence** (`Store/SwiftDataPersistence.swift`): `AppStoreSnapshot` is
  a hand-written `Codable` struct with a custom `init(from:)` that uses
  `decodeIfPresent(...) ?? default` for every field added after v1. **Any new
  top-level array/type added to `AppStore` (mealPlans, matkasseBoxes, etc.)
  must be added here too** — both the `CodingKeys` case and the
  `decodeIfPresent` fallback — or persistence silently drops it on next
  launch. This is the single easiest thing to forget across every phase
  below that touches the data model.
- **Store** (`Store/AppStore.swift`): `optimizeShoppingList(_:)` does
  baseline + greedy multi-store optimization already (doesn't yet use
  travel/visit cost settings). `communityConfidence(for:)` and `isOutlier`
  already implement basic community trust tiering. `execute(_:)` is a single
  switch over `ProposedActionPayload` — every new payload case needs a case
  added there too, plus a `permissionTarget(for:)` mapping.
- **Actions** (`Models/ProposedAction.swift`): `ProposedActionType` and
  `ProposedActionPayload` currently cover create-only for most entities (no
  update/delete for shopping lists, price observations, or recipes yet, even
  though the type enum lists them — payload cases don't exist for them).
  `isDestructive` already gates delete-type actions for confirmation.
- **Views:** `ShoppingView.swift` already has list overview (flat, no
  status segmentation), list detail with store grouping + optimization
  banner + barcode scan + actual-price capture. `PricesView.swift` already
  has Product/Store view-mode segmented control, a horizontal stat strip,
  community confidence display, and `ProductPriceHistoryView`. No Store
  detail screen exists yet. `RecipesView.swift` is a flat list + detail with
  cost-per-ingredient and cost-by-store estimation (`RecipeCostEstimate`) —
  no meal planning at all.
- **Tab bar** (`App/RootTabView.swift`): tab titled "Recipes", icon
  `fork.knife`, routes to `RecipesView()`.

---

## Phase 1 — Shopping: data model foundation

**Goal:** add the fields the redesigned Shopping UI needs, without touching
UI yet, so Phase 2/3 have real state to bind to.

**Files:** `Models/AppModels.swift`, `Store/AppStore.swift`,
`Store/SwiftDataPersistence.swift`.

**Tasks:**
- `ListStatus`: add `.planned` case.
- `ShoppingList`: add `completedAt: Date?`, `archivedAt: Date?`, and an
  `optimizationSnapshot: OptimizationSnapshot?` struct (chosenStores:
  `[String]`, estimatedOneStoreTotal: `Decimal`, optimizedTotal: `Decimal`,
  savings: `Decimal`, unpricedItemCount: `Int`, optimizationDate: `Date`).
- `ShoppingListItem`: add `selectedPriceObservationID: UUID?` (replaces
  relying on `assignedStoreBranch` string-matching alone for "which exact
  price did we use") and `substituteCandidateNames: [String]`.
- `AppStore`: add `plannedLists`, `completedLists`, `archivedLists` computed
  properties (mirroring `activeLists`); add `completeShoppingList(_:)`,
  `archiveShoppingList(_:)`, `reopenList(_:)` methods that set status +
  timestamp and call `persistNow()`.
- Update `optimizeShoppingList(_:)` to also populate `optimizationSnapshot`
  on the list (keep writing the existing `estimatedTotal` field too — don't
  break current UI mid-phase).
- `AppStoreSnapshot`: add the new fields with `decodeIfPresent(...) ??`
  fallbacks per the persistence note above.

**Definition of done:** builds clean; existing Shopping tab behavior
unchanged (nothing reads the new fields yet); a quick scratch test (e.g. a
temporary print or breakpoint) confirms `optimizationSnapshot` populates
after calling `optimizeShoppingList`.

---

## Phase 2 — Shopping: overview screen redesign

**Goal:** rebuild `ShoppingView`'s root screen per the product plan's
"Top-Level Structure" / "Recommended first screen" section.

**Files:** `Features/Shopping/ShoppingView.swift` (root view + card), new
`Features/Shopping/ShoppingOverviewComponents.swift` for the header stat band
and segmented status control if it doesn't fit cleanly inline.

**Depends on:** Phase 1 (`.planned` status, `optimizationSnapshot` for
per-card savings/store count).

**Tasks:**
- Header summary band: active list count, next planned shop date (min
  `plannedDate` across planned/active lists), estimated spend across active
  lists, missing-price count across active lists.
- Segmented control: Active / Planned / Completed / Archived, replacing the
  current flat "all active lists" view.
- `ShoppingListCard`: extend with stores-required chip(s), savings-vs-one-store
  badge (from `optimizationSnapshot`), and a stale/missing-price warning
  badge — keep the existing progress ring + estimated total.
- Primary actions row: New list (existing sheet), "Optimize all active
  lists" (loop `optimizeShoppingList` over `activeLists`), "Ask AI" (jump to
  Chat tab — check how `RootTabView` exposes tab switching, or post a
  starter chat message).
- Planned-date editing: surface `plannedDate` as an editable field in
  `AddShoppingListSheet` (currently only sets `name`/`scope` — check
  `ManualEntrySheets.swift`).

**Definition of done:** all four status segments show the right lists;
completing/archiving a list moves it between segments; header stats compute
correctly with zero, one, and many lists.

---

## Phase 3 — Shopping: list detail redesign

**Goal:** rebuild `ShoppingListDetailView` per the product plan's "Shopping
List Detail" section — trip summary band, real optimization controls, store
sections with subtotals, a dedicated Needs Price Data section, and a
collapsible completed section with undo.

**Files:** `Features/Shopping/ShoppingView.swift` — likely worth splitting
into `ShoppingListDetailView.swift` + `ShoppingItemRow.swift` at this point,
the current file is already 700 lines before this redesign lands.

**Depends on:** Phase 1.

**Tasks:**
- Trip summary band: estimated total, actual total so far, savings, store
  count, priced/unpriced item counts, one-line optimization explanation
  (mostly exists already — reorganize into the spec'd layout).
- Optimization controls: keep the existing Optimize button; add a one-store
  toggle (forces `maxSupermarketCount` = 1 for this run only, doesn't touch
  settings) and small text readouts of the current max-stores /
  minimum-savings settings values (read-only link to Settings, not editable
  here).
- Store sections: add per-store subtotal + item count to each section
  header (currently just the store name).
- Item row actions: "move to another store" (reassign
  `assignedStoreBranch`/`selectedPriceObservationID` manually, override
  optimizer for that item), "substitute" (pick from
  `substituteCandidateNames` or type a new one) — both as swipe actions or a
  context menu, matching existing interaction patterns in this file.
- Needs Price Data section: pending items with no `estimatedPrice`, each
  with CTAs — "Add price manually" (existing `AddPriceObservationSheet`,
  prefilled product name), "Use community price" (only if one exists for
  that product+any store), "Scan barcode" (existing
  `BarcodeScannerView(mode: .addToList)`).
- Completed section: make it collapsible (`DisclosureGroup` or a simple
  expand toggle), add "Undo" per completed item (flip `isCompleted` back,
  clear `actualPrice` if it was auto-set) — there's no undo path today,
  `toggle(item:)` in the current file doubles as both directions but nothing
  in the UI drives it backward except tapping the row again.

**Definition of done:** manual walkthrough with a seeded list against 2+
stores' worth of prices — optimization banner, store sections, needs-price
section, and completed/undo all behave correctly; barcode scan and manual
add-item flows still work unchanged.

---

## Phase 4 — Shopping: in-store mode (stretch)

**Goal:** the product plan's in-store mode — large checkboxes, fewer
controls, one store's items at a time.

**Files:** new `Features/Shopping/InStoreModeView.swift`, entry point added
to `ShoppingListDetailView`'s toolbar.

**Depends on:** Phase 3 (needs store sections to exist first).

**Tasks:**
- Full-screen (or sheet) mode scoped to one selected store's pending items.
- Large tap targets, checkbox-only interaction, running subtotal for that
  store, "next item" focus state.
- On completing the last item in the current store, prompt to switch to the
  next store in the trip plan.
- Feeds into existing `captureActualPrice`/`toggle` logic — no new AppStore
  methods needed, this is a focused view over existing state.

**Definition of done:** can complete an entire multi-store list from
in-store mode alone, prices captured correctly, exits cleanly back to the
normal detail view.

This phase is explicitly optional/cuttable if time is tight — Phases 1–3
are the real "Shopping is rebuilt" milestone per the product plan.

---

## Phase 5 — Shopping: AI actions expansion

**Goal:** give Chat the CRUD surface the product plan's "AI Chat
Integration" section promises for shopping lists, now that the data/UI shape
from Phases 1–3 exists.

**Files:** `Models/ProposedAction.swift`, `Store/AppStore.swift`
(`execute(_:)` + `permissionTarget(for:)`), `Features/Chat/*` only if the AI
service's tool/function schema needs new entries (check `GeminiAPITypes.swift`
and wherever tool definitions are declared for the live AI service).

**Tasks:**
- Add payload cases: `updateShoppingList`, `deleteShoppingList`,
  `updateShoppingListItem`, `completeShoppingListItem`,
  `removeShoppingListItem`, `addRecipeToShoppingList` (types already exist in
  `ProposedActionType`, payload cases don't).
- Implement each in `AppStore.execute(_:)`; extend `undoActivityTag`/
  `canUndoActivityTag` for the new mutating cases where undo makes sense.
- Wire the AI service's function-calling schema (wherever the Gemini tool
  definitions live) to expose the new actions, matching the existing
  pattern for `createShoppingList`/`addShoppingListItem`.
- Test via Chat: "mark milk as bought", "remove bread from the list",
  "add my taco recipe to Weekly Shop".

**Definition of done:** each new action round-trips through `ActionProposalView`
approval → `execute` → visible change in the Shopping tab; destructive ones
(delete list, remove item) require confirmation per `isDestructive`.

---

## Phase 6 — Prices: data model tweaks

**Goal:** land the small, high-leverage model changes the product plan's
"Confirmed Product Decisions" call for, before touching the Prices UI.

**Files:** `Models/AppModels.swift`, `Store/AppStore.swift`.

**Tasks:**
- `PriceObservation.isStale`: change threshold from `> 30` to `> 60` days to
  match the product plan ("Prices become stale after 60 days by default").
  Rework `freshnessAdjustedConfidence`'s bands to decay smoothly against the
  new threshold (e.g. 0–60 full, 61–120 reduced once, 121+ reduced twice)
  rather than leaving the old 30/60/90 cutoffs half-matching the new stale
  line.
- Add a small unit-price normalization helper (kr/kg, kr/l, kr/stk) as a
  computed property or free function — `RecipesView.swift`'s
  `RecipeCostEstimate` already has ad hoc unit-conversion logic
  (`baseQuantity`, `unitFamily`); extract/generalize that into something
  `Store/AppStore.swift` or a shared `Models/` file can reuse for Prices
  Phase 8, instead of writing a second copy.

**Definition of done:** stale badges in the existing `PriceObservationRow`/
`StoreModeRow` reflect the new 60-day line; recipe costing (Phase-6-agnostic,
already shipped) still computes the same way since it filters on `isStale`
too — confirm nothing regresses there.

---

## Phase 7 — Prices: overview redesign

**Goal:** make Products / Stores / Needs Prices / Community genuinely
top-level modes, per the product plan.

**Files:** `Features/Prices/PricesView.swift` (extend `PriceViewMode` and the
mode switch), new `Features/Prices/NeedsPricesView.swift`,
`Features/Prices/CommunityPricesView.swift` if the sections are large enough
to warrant separate files.

**Depends on:** Phase 6 (stale threshold), Phase 1 (Needs Prices reads
active + planned shopping lists).

**Tasks:**
- `PriceViewMode`: add `.needsPrices`, `.community` cases alongside existing
  `.byProduct`/`.byStore`.
- Needs Prices queue: union of (a) pending shopping-list items with no
  `estimatedPrice` across active + planned lists, (b) recipe ingredients
  with no cost match (reuse the ingredient-matching logic factored in Phase
  6, don't reimplement `RecipeCostEstimate`'s matcher a third time). Each row
  links to "add price" prefilled.
- Community mode: list community contributions with trust indicators
  (reuse `communityConfidence(for:)`), show matching-vs-personal-price
  callouts where a personal observation exists for the same product+store
  (the product plan's "community confirms the price" case).
- Extend the existing stat-tile row with a "community prices available"
  tile.

**Definition of done:** all four modes render correctly with realistic
mixed data (some priced, some not, some community, some personal); Needs
Prices queue updates live as list items or recipes change.

---

## Phase 8 — Prices: product/store detail & trust model

**Goal:** flesh out `ProductPriceHistoryView` and add the Store detail
screen the product plan calls for but doesn't exist yet.

**Files:** `Features/Prices/PricesView.swift` (extend
`ProductPriceHistoryView`), new `Features/Prices/StoreDetailView.swift`, new
`Features/Prices/ProductMergeView.swift` (or a sheet folded into product
detail).

**Depends on:** Phase 6 (unit-price helper), Phase 7 (navigation from Store
mode into a real store detail screen instead of nothing).

**Tasks:**
- Product detail: unit-price comparison row using the Phase 6 helper,
  clearer community-vs-personal field separation (product plan: "if values
  match, show that the community confirms the price" — already partly done
  via `communityConfidence`, extend the visual treatment), aliases/barcode
  management (edit `Product.aliases`/`barcode` inline).
- Duplicate product merge tool: pick a source and target `Product`, reassign
  all `PriceObservation.productID`/`productName` and any
  `ShoppingListItem.productID` references, delete the source `Product`. Add
  `AppStore.mergeProducts(sourceID:targetID:)`.
- Store detail screen: all products priced at that branch, stale-price
  count, a "confirm this price" prompt list for stale-but-important
  (referenced by an active list or recipe) observations. Wire from
  `.byStore` mode's store rows.

**Definition of done:** can navigate Store mode → store detail → a product
→ product detail and back; merge tool correctly consolidates two duplicate
products without orphaning any price observations.

---

## Phase 9 — Prices: AI actions expansion

**Goal:** close the gap between what `ProposedActionType` already lists for
Prices and what `execute(_:)` actually implements.

**Files:** `Models/ProposedAction.swift`, `Store/AppStore.swift`.

**Tasks:**
- Add payload cases: `updateProduct`, `deleteProduct`,
  `updatePriceObservation`, `deletePriceObservation`.
- Implement in `execute(_:)`, extend undo support.
- Add a "merge products" action type/payload wired to the Phase 8
  `mergeProducts` method, so Chat can propose a merge (e.g. user says
  "tomatoes and tomato are the same product").
- Wire into the AI service's tool schema.

**Definition of done:** "update the price I logged for milk to 32 kr",
"delete that duplicate Rema entry", "merge tomato and tomatoes" all work
through Chat's approval flow.

---

## Phase 10 — Meals: rename + data model

**Goal:** stand up the data layer for meal planning and matkasse before any
new UI, and rename the tab.

**Files:** `Models/AppModels.swift`, `Store/AppStore.swift`,
`Store/SwiftDataPersistence.swift`, `App/RootTabView.swift`,
`Features/Recipes/RecipesView.swift`.

**Tasks:**
- Rename tab label "Recipes" → "Meals" in `RootTabView.swift`
  (`tabButton(.recipes, title: "Recipes", ...)` → `"Meals"`). Leave the enum
  case name (`.recipes`) and file/struct names as-is for this phase to keep
  the diff small — a pure rename pass across files is a fine follow-up but
  shouldn't block landing the data model.
- New model types in `Models/AppModels.swift`:
  - `MealType` enum: breakfast, lunch, dinner, snack, custom(String) — or a
    simpler `String` with a curated default set plus user-added ones, matching
    how `MeasurementUnit` vs. free-text is handled elsewhere.
  - `MealPlan`: id, date range or explicit week-start date, scope
    (personal/household), slots: `[MealPlanSlot]`.
  - `MealPlanSlot`: id, date, mealType, and one of — recipeID, freeform
    meal text, or matkasseMealID (mirror the existing `enum` + associated
    value pattern used by `ChatMessageContent` rather than three optional
    fields).
  - `MatkasseBox`: id, provider (free text, not branded), deliveryWeek,
    numberOfMeals, price, servings, notes, includedMeals:
    `[MatkasseMeal]`.
  - `MatkasseMeal`: id, title, optional ingredients (`[RecipeIngredient]`,
    reuse the existing type), whether it generates shopping-list items by
    default (`false` per the confirmed decision).
- `AppStore`: add `mealPlans: [MealPlan]`, `matkasseBoxes: [MatkasseBox]`
  observed arrays with `didSet { persistIfReady() }`, matching every other
  array in the class.
- `AppStoreSnapshot`: add both new arrays with `decodeIfPresent(...) ?? []`
  fallbacks — this is the persistence trap called out in "Current
  foundation" above.

**Definition of done:** builds clean, tab reads "Meals", app launches and
persists/restores with the new empty arrays present, existing Recipes
functionality (browsing, detail, cost estimate) completely unchanged.

---

## Phase 11 — Meals: week planner UI

**Goal:** the calendar/planner screen from the product plan's "Top-Level
Structure" and week-summary sections.

**Files:** new `Features/Recipes/MealPlanView.swift` (or
`Features/Meals/MealPlanView.swift` if the folder gets renamed alongside),
`Features/Recipes/RecipesView.swift` (add planner as the first screen /
segmented section, recipe browser becomes a sub-section).

**Depends on:** Phase 10.

**Tasks:**
- Week view: 7-day strip, meal-type rows per day (breakfast/lunch/dinner/
  custom per user selection), tap a slot to assign a recipe, a freeform
  meal, or a matkasse meal.
- Week summary band: planned meal count, matkasse-covered count, open slots,
  estimated grocery cost outside matkasse (sum recipe cost estimates for
  planned, non-matkasse slots using the existing `RecipeCostEstimate`
  machinery), missing-ingredient-price count.
- Recipe browser: keep existing flat list, add Favorites/Recent/Tags
  filtering (favorite already exists as a field; "recent" needs a
  `lastCookedAt`-style field or can be inferred from meal-plan history once
  Phase 11 data exists).
- "Eating out / takeaway" as a special freeform slot value, not a full
  recipe — keeps the week plan honest per the product plan.
- Fortnight/month toggle: **not** in this phase — ship weekly first, add the
  toggle only if it's requested after weekly is live (matches the "Assumed
  answers" section above).

**Definition of done:** can plan a full week with a mix of recipes,
freeform meals, and an eating-out slot; week summary numbers match manual
calculation; existing recipe list/detail/cost views still work.

---

## Phase 12 — Meals: shopping list generation + matkasse UI

**Goal:** close the loop from meal plan → shopping list, and give matkasse
boxes a real UI.

**Files:** `Features/Recipes/MealPlanView.swift`, new
`Features/Recipes/MatkasseView.swift`, `Store/AppStore.swift`.

**Depends on:** Phase 11.

**Tasks:**
- "Build shopping list" action on the week planner: ask one weekly list vs.
  one list per shopping trip (per the product plan's confirmed decision),
  then generate a `ShoppingList` from all non-matkasse recipe ingredients
  across the selected slots, merging duplicate ingredients (reuse the
  ingredient name-matching helper generalized in Phase 6/7 rather than a
  fourth copy).
- "Exclude already have" toggle at generation time — a lightweight one-off
  exclusion list for this generation, not a persistent pantry feature (that
  stays in the Backlog per the open-questions defaults).
- Matkasse UI: list of `MatkasseBox`es, add/edit box (provider, delivery
  week, meals, servings, price), add individual `MatkasseMeal` entries,
  place matkasse meals onto planner slots — visually distinct from recipe
  slots ("covered by matkasse" badge).
- `AppStore.generateShoppingList(fromMealPlan:oneListPerTrip:excluding:)`.

**Definition of done:** planning a week with 2 matkasse dinners + 3 recipe
dinners and generating a shopping list produces a list with only the
non-matkasse recipes' ingredients, correctly merged; matkasse box cost
never bleeds into the generated list's estimated total.

---

## Phase 13 — Meals: AI actions expansion

**Goal:** close the Chat integration gap for recipes/meal plans/matkasse.

**Files:** `Models/ProposedAction.swift`, `Store/AppStore.swift`.

**Tasks:**
- Add payload cases: `updateRecipe`, `deleteRecipe` (types already listed,
  payloads missing), plus new ones for meal plans and matkasse:
  `createMealPlanSlot`, `updateMealPlanSlot`, `removeMealPlanSlot`,
  `createMatkasseBox`, `addMatkasseMeal`.
- Implement in `execute(_:)`, extend undo support, wire AI tool schema.
- Test via Chat: "plan spaghetti for Tuesday dinner", "add this week's
  HelloFresh box with 4 meals" (provider name comes from the user's own
  words — the app itself stays unbranded per the product plan), "build a
  shopping list for this week, one list please".

**Definition of done:** full loop works — Chat creates a meal plan slot,
it shows up in the Phase 11 planner, "build shopping list" produces a
correct Shopping-tab list.

---

## Backlog (explicitly not phased yet)

Everything in the product plan's "Nice-to-have later" and "Ambitious later"
sections per tab, plus the cross-tab "Ambitious Cross-Tab Ideas" section,
stays unscheduled until pulled forward on request. Notable ones surfaced
during this planning pass:

- Travel cost / fixed store-visit cost actually used by the optimizer
  (settings fields exist, optimizer ignores them today).
- Pantry / "already have" as a persistent feature (Phase 12 only does a
  one-off exclusion at generation time).
- Recipe photos, price trend charts, receipt image attachment.
- Household savings dashboard, "food command center" home summary, grocery
  inflation tracker, budget forecast — all cross-tab aggregation views that
  make more sense once Shopping/Prices/Meals are individually solid.
- List templates ("Weekly Basics", "Taco Night").
- Location-based nudges, route ordering, Siri/App Intents, widgets, share
  extension — all require capabilities (location, intents, share sheet)
  not yet wired into the app at all.
