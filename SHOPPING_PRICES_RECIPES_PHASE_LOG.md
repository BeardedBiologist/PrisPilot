# Shopping, Prices, and Meals — Handoff Log

Companion to `SHOPPING_PRICES_RECIPES_PHASE_PLAN.md` (which is itself built
on `SHOPPING_PRICES_RECIPES_REDESIGN_PLAN.md`). Append an entry per work
session/phase so any agent (or Josh) can pick this up cold. Newest entry at
the top. Each entry: what changed, why, how it was verified, what's next.

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
