# Shopping, Prices, and Meals — Handoff Log

Companion to `SHOPPING_PRICES_RECIPES_PHASE_PLAN.md` (which is itself built
on `SHOPPING_PRICES_RECIPES_REDESIGN_PLAN.md`). Append an entry per work
session/phase so any agent (or Josh) can pick this up cold. Newest entry at
the top. Each entry: what changed, why, how it was verified, what's next.

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
