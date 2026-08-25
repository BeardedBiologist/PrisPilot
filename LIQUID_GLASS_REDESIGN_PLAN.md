# PrisPilot — Liquid Glass Redesign Plan

Status: proposed, not started
Deployment target: iOS 26.5 (confirmed in `PrisPilot.xcodeproj/project.pbxproj`) — every iOS 26 API below is **unconditionally available**, no `#available` gating required anywhere in this app.
Skills driving this plan: `swiftui-liquid-glass`, `swiftui-animation`, `swiftui-gestures`, `swiftui-layout-components`, `swiftui-navigation`, `swiftui-patterns`, `swiftui-performance`.

## 1. Goals

- Give the app a coherent Liquid Glass design language: floating glass controls and navigation surfaces, not glass smeared over everything.
- Replace static, instant UI state changes with real motion: springs, matched-geometry hero transitions, symbol effects, content transitions.
- Add gesture-driven interactions where they remove friction (swipe-to-complete, swipe-to-delete, long-press context actions, pinch-to-zoom on camera/receipt scanning).
- Do this without regressing correctness, accessibility (Reduce Motion / Reduce Transparency / VoiceOver / Dynamic Type), or performance.
- Fix the one architectural gap that blocks safe, predictable animation-driven UI: `AppStore` is `@Observable` but **not** `@MainActor` (unlike `AuthStore`, which is correctly isolated).

## 2. Current State (audit)

| Area | File(s) | Current pattern |
|---|---|---|
| Root shell | `App/RootTabView.swift` | Hand-rolled `HStack` tab bar, `.background(.regularMaterial)`, manual `selectedTab` switch — no `TabView`/`Tab` API, no glass |
| Chat | `Features/Chat/ChatView.swift`, `ChatViewModel.swift`, `MessageBubbleView.swift`, `ActionProposalView.swift`, `ActivityTagView.swift` | `NavigationStack` + `ScrollViewReader`/`LazyVStack`, `.thinMaterial` header, no message-insertion transitions, no typing-indicator choreography beyond a basic view |
| Shopping | `Features/Shopping/ShoppingView.swift`, `ManualEntrySheets.swift` | `ScrollView` + `LazyVStack` + `NavigationLink(destination:)`, `.contextMenu`, plain `ShoppingListCard`, no swipe actions, no hero transition into detail |
| Prices | `Features/Prices/PricesView.swift`, `PriceComparisonView.swift` | `List` with sections, segmented product/store picker, `.sheet(isPresented:)` for add/scan flows, no numeric content transitions |
| Recipes | `Features/Recipes/RecipesView.swift` | `List` with sections, plain `NavigationLink`, no swipe actions, no favorite animation |
| Scanner | `Features/Scanner/BarcodeScannerView.swift`, `ReceiptScannerView.swift` | Camera capture UI, presumed standard buttons — no glass viewfinder chrome, no scan choreography |
| Settings | `Features/Settings/SettingsView.swift`, `AccountView.swift` | `List` (correct container choice already), plain rows, static AI-status dot |
| Onboarding | `Features/Onboarding/OnboardingView.swift`, `OnboardingFlow.swift` | `switch step` with instant swap, `.borderedProminent`/`.bordered` buttons, one `symbolEffect(.bounce)` on the hero icon already |
| State | `Store/AppStore.swift` | `@Observable class AppStore` — **missing `@MainActor`** (contrast with `Store/AuthStore.swift`, which is `@MainActor @Observable final class`) |

## 3. Design Principle: Glass Is For Controls, Not Content

This is the single most important rule from `swiftui-liquid-glass` and it will be violated by instinct if we're not deliberate: **`.glassEffect()` belongs on functional controls and navigation surfaces — floating buttons, toolbars, tab bars, viewfinder chrome — not on list rows, cards, or message bubbles.** Content surfaces get refined materials, tints, and shadows; only *controls* get real glass.

Concretely, in this app:

**Gets real `.glassEffect()` / `.buttonStyle(.glass*)`:**
- Root tab bar (`RootTabView`)
- Chat header icon buttons, composer/send button, Approve/Reject action buttons
- Shopping/Prices/Recipes toolbar buttons (add, scan, receipt)
- Floating "+" / FAB-style buttons
- Camera viewfinder chrome in `BarcodeScannerView` / `ReceiptScannerView` (capture button, torch toggle)
- Onboarding primary/secondary CTA buttons (replacing `.borderedProminent`/`.bordered`)

**Stays material/tint/shadow, NOT glass:**
- `ShoppingListCard`, `RecipeRow`, price observation rows — these are content, they get a refined `.background(.thinMaterial)`/tint treatment and better shadow, not `.glassEffect()`
- Chat message bubbles (`TextBubble`) — already has a nice gradient identity; keep it, don't glass it
- Settings `List` rows — `List` + `.insetGrouped` is already the correct native container per `swiftui-layout-components`; leave rows native, just polish the hero account area at the top

## 4. Phase 0 — Foundations

1. **Fix `AppStore` actor isolation.** Add `@MainActor` to `Store/AppStore.swift:11-12` so it matches `AuthStore`. This is required before layering animation-driven UI on top of it under Swift 6 concurrency — per `swiftui-patterns`: "Isolate UI-bound `@Observable` stores... on `@MainActor`." Verify `ChatViewModel` (`Features/Chat/ChatViewModel.swift`) is `@MainActor` too.
2. **Create a `DesignSystem/` group** (new files, e.g. `DesignSystem/GlassTheme.swift`):
   - Shared spacing/corner-radius tokens (avoid re-deriving "24pt glass container spacing" in five places).
   - A tint palette (the existing accent is `.blue` — keep it as the interactive-glass tint throughout for consistency).
   - A small `ReduceMotionEnvironment` convenience or just a documented pattern: every new `symbolEffect`/`PhaseAnimator`/large-motion transition reads `@Environment(\.accessibilityReduceMotion)` and short-circuits.
3. **Decide the `@Namespace` strategy for hero transitions.** Each tab's `NavigationStack` needs its own `@Namespace` (list source + pushed detail must share one namespace, and only one source per ID can be visible — per `swiftui-animation`). Plan: one `@Namespace private var heroSpace` owned by each top-level feature view (`ShoppingView`, `PricesView`, `RecipesView`), not a single app-wide namespace.
4. **Audit for `DateFormatter()`/`NumberFormatter()` allocations inside `body`** in `PricesView.swift`, `PriceComparisonView.swift`, `ShoppingView.swift` (price/date formatting is central to this app) and hoist any found to `static let` per `swiftui-performance`.

## 5. Phase 1 — Root Navigation Shell (`App/RootTabView.swift`)

This is the highest-visibility surface and the best Liquid Glass showcase. Rebuild the custom tab bar rather than switching to the native `Tab`/`TabView` API — the bespoke raised center "Chat" bubble (`MainChatTabIcon`) is a real brand element worth preserving, and `swiftui-navigation` explicitly supports a manual approach when you need a non-standard layout.

- Wrap the tab buttons in a single `GlassEffectContainer(spacing: 24)` so they blend/morph as one glass system instead of five independent flat buttons.
- Give the bar itself a floating-pill treatment: pull it off the bottom edge with padding, round it into a `Capsule`, apply `.glassEffect(.regular)` to the container background instead of the current flat `.background(.regularMaterial)` band. (Fallback if this fights the existing `.ignoresSafeArea(.keyboard, edges: .bottom)` layout: keep it edge-anchored but still swap the material for real glass.)
- Selected-tab indicator: a `Capsule` behind the active icon, moved with `.matchedGeometryEffect(id: "tabSelection", in: ns)` or `glassEffectID`-driven morphing, animated with `.spring(duration: 0.4, bounce: 0.2)` on `selectedTab` change.
- `MainChatTabIcon`: apply `.glassEffect(.regular.tint(.blue).interactive())`, keep its raised/shadowed look. Add `.symbolEffect(.bounce)` triggered when a new assistant message arrives while Chat isn't the active tab (needs a small "unread" signal from `AppStore`/`ChatViewModel` — check whether one exists before wiring this).
- Tab icons: swap with `.contentTransition(.symbolEffect(.replace))` between selected/unselected symbol variants (e.g. `cart` → `cart.fill`) instead of a hard color flip only.
- Add a light haptic (`UIImpactFeedbackGenerator(.light)`) on tab change — not a skill API, but pairs naturally with the new spring motion.
- Replace the raw `Button` + manual styling in `tabButton(_:title:systemImage:)` with `.buttonStyle(.glass)` where it doesn't conflict with the custom selection capsule.

```swift
// Illustrative shape, not final code
GlassEffectContainer(spacing: 24) {
    HStack(spacing: 0) {
        ForEach(RootTab.allCases) { tab in
            tabButton(tab)
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID(tab, in: tabBarNamespace)
        }
    }
}
```

## 6. Phase 2 — Chat (`Features/Chat/*`)

Chat is the primary surface (center tab, AI-driven) — invest the most polish here.

- **Header** (`chatHeader` in `ChatView.swift`): replace the three `HeaderIconButton`s' ad-hoc styling with `.buttonStyle(.glass)` inside a `GlassEffectContainer(spacing: 16)`, so history/new-chat/memory buttons blend as one glass cluster. Keep `.thinMaterial` on the header bar itself only if glass-ifying the whole bar reads as too busy — try `.glassEffect()` on the bar first since it's a navigation surface, not content.
- **Message list**: wrap each inserted `MessageBubbleView` in `.transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .opacity))`, driven by `withAnimation(.snappy)` around the point where `viewModel.messages` is mutated (in `ChatViewModel`). Modernize scroll-to-bottom: consider `ScrollPosition` + `.scrollTargetLayout()` (per `swiftui-layout-components`) as a declarative alternative to the current manual `ScrollViewReader.scrollTo`, if it simplifies `scrollToBottom(proxy:)`.
- **Typing indicator**: rebuild `TypingIndicatorView` with `PhaseAnimator` (three-phase dot bounce, staggered per dot) or `KeyframeAnimator` if per-dot offset+scale choreography is wanted. This is exactly the "multi-phase sequenced animation" use case the animation skill calls out.
- **`ActionProposalView`**: Approve/Approve-All → `.buttonStyle(.glassProminent)`; Reject/Reject-All → `.buttonStyle(.glass)`. Add `.symbolEffect(.bounce, value: <approved>)` on the checkmark when an action is approved, and pair any `Text` count changes with `.contentTransition(.numericText())`.
- **`ActivityTagView`**: group tag pills in a `GlassEffectContainer` and use `.glassEffectUnion(id:namespace:)` for tags that belong to the same activity group, so they visually merge instead of sitting as isolated capsules.
- **Composer/input bar**: pin with `.safeAreaInset(edge: .bottom)` (if not already), give the send button `.buttonStyle(.glassProminent)` with a `.symbolEffect(.bounce)` on send, disable/enable via opacity+scale `.animation(.snappy, value: canSend)`.

## 7. Phase 3 — Shopping & Prices

### `Features/Shopping/ShoppingView.swift`
- Keep `ShoppingListCard` as a refined material card (not glass — it's content). Add subtle spring on the progress ring: `.animation(.snappy, value: progress)`.
- Add swipe actions for delete (currently only available via `.contextMenu`) — either migrate the `ScrollView`/`LazyVStack` list to a native `List` with `.listRowSeparator(.hidden)` + `.listRowBackground(.clear)` to get `.swipeActions` and row reuse "for free" while keeping the card look, or add a custom `DragGesture` with `@GestureState` for swipe-to-delete if the card visual can't tolerate `List`'s row chrome. Try the `List` migration first — it's the lower-risk path per `swiftui-layout-components`.
- Hero transition into `ShoppingListDetailView`: pair `.matchedTransitionSource(id: list.id, in: heroSpace)` on `ShoppingListCard` with `.navigationTransition(.zoom(sourceID: list.id, in: heroSpace))` on `ShoppingListDetailView`.
- Item completion checkbox (inside `ShoppingListDetailView`, not yet inspected in detail): `.contentTransition(.symbolEffect(.replace))` between `circle` and `checkmark.circle.fill`, plus a light `.symbolEffect(.bounce)` on completion.
- If item reordering is wanted, use `.onMove` with `EditButton` (still a valid, non-deprecated pattern per `swiftui-patterns`) rather than a hand-rolled drag gesture.

### `Features/Prices/PricesView.swift` + `PriceComparisonView.swift`
- Wrap price `Text` values in `.contentTransition(.numericText())` + `.animation(.snappy, value: price)` so price updates (new observations, currency changes) animate digit-by-digit instead of popping.
- Toolbar buttons (receipt scanner, barcode scanner, add price) → `GlassEffectContainer` + `.buttonStyle(.glass)`, matching the Chat header treatment for consistency.
- `modePickerRow` (Product/Store) stays `.segmented` — correct choice for a 2-option picker per `swiftui-layout-components`.
- `PriceComparisonView`'s optimisation result: consider a `symbolEffect(.variableColor.iterative)` loading state while the optimisation computes, and a `matchedGeometryEffect`-driven hero when a store row expands into "why this store" detail, if that interaction exists.

### `Features/Scanner/BarcodeScannerView.swift` + `ReceiptScannerView.swift`
- Viewfinder chrome (capture button, torch/flash toggle) is the textbook "clear glass action over bright/busy content" case from `swiftui-liquid-glass` — apply `.buttonStyle(.glass(.clear))` with a dimming layer behind if the camera feed is bright, `.glassProminent` for the primary capture button.
- Scan-line sweep animation: `KeyframeAnimator` moving a line top-to-bottom while scanning is active, gated by `.accessibilityReduceMotion` (fall back to a static "Scanning…" pulse text).
- If pinch-to-zoom on the camera preview is desired, add `MagnifyGesture()` with `@GestureState` per `swiftui-gestures` (this is the exact "replace deprecated `MagnificationGesture`" scenario the skill flags).

## 8. Phase 4 — Recipes (`Features/Recipes/RecipesView.swift`)

- Add `.swipeActions` to `recipeRows` for delete/favorite-toggle (currently `List` already — just needs the modifier).
- Favorite star: `.contentTransition(.symbolEffect(.replace))` between `star` and `star.fill`, `.symbolEffect(.bounce, value: recipe.isFavorite)`.
- Hero transition row → `RecipeDetailView`: same `matchedTransitionSource` + `.navigationTransition(.zoom(...))` pairing as Shopping, using the tab's own `@Namespace`.
- `AddRecipeSheet`: confirm it uses `Form` + `.formStyle(.grouped)`; add `.presentationSizing(.form)`.

## 9. Phase 5 — Settings & Onboarding

### `Features/Settings/SettingsView.swift` + `AccountView.swift`
- Leave the `List`/`.insetGrouped` structure alone — it's already the right container. Add one hero touch: a glass-free but visually elevated account header card at the top (avatar + name + sign-in status) above the plain `LabeledContent` rows, since that's the one place users will glance at often.
- AI status indicator (currently a static colored `Circle`): replace with `.symbolEffect(.pulse, isActive: store.isUsingLiveAI)` on a `wifi`-style or `bolt.fill` symbol, or keep the dot but animate its color transition with `.animation(.smooth, value: store.isUsingLiveAI)`.

### `Features/Onboarding/OnboardingView.swift` + `OnboardingFlow.swift`
- Replace `.buttonStyle(.borderedProminent)`/`.bordered)` on the welcome step's two CTAs with `.buttonStyle(.glassProminent)`/`.buttonStyle(.glass)` to match the app-wide button language established in Phase 2.
- Wrap the `switch step` body in a transition: `.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))`, driven by `withAnimation(.smooth)` at each `step =` assignment.
- If `manualQuestion(Int)` steps show a progress indicator, animate the active dot with `matchedGeometryEffect` so it slides between positions rather than jumping.
- Keep the existing `symbolEffect(.bounce, options: .nonRepeating)` on the hero icon — it's already correct.

## 10. Phase 6 — Accessibility, Performance & Verification Pass

Run this checklist once per phase, not just at the end, per `swiftui-liquid-glass` and `swiftui-animation` review checklists:

- [ ] Reduce Transparency ON: every `.glassEffect()` surface still reads clearly (dimming layer added where needed for `.clear` variants).
- [ ] Reduce Motion ON: every `symbolEffect`, `PhaseAnimator`/`KeyframeAnimator`, and large `matchedGeometryEffect`/zoom transition degrades to a simple cross-fade or no-op (`@Environment(\.accessibilityReduceMotion)` checked at each new call site).
- [ ] VoiceOver: all new icon-only glass buttons (tab bar, header buttons, capture button) have `.accessibilityLabel`.
- [ ] Dynamic Type: glass buttons/pills don't clip at largest accessibility sizes.
- [ ] `GlassEffectContainer` used everywhere 2+ glass siblings exist (tab bar, chat header, chat action buttons, price/prices toolbars).
- [ ] Only one visible `matchedGeometryEffect`/`matchedTransitionSource` per ID at any time (Shopping/Recipes hero transitions).
- [ ] Instruments SwiftUI template pass (Release build, real device) on: Chat message-list scroll with the new insertion transitions, Shopping list scroll after the `List` migration. Compare Long View Body Updates before/after per `swiftui-performance`.
- [ ] Build after each phase; fix compiler/isolation errors immediately (the `@MainActor` fix in Phase 0 is a prerequisite for this staying clean).
- [ ] Visually verify each phase in the simulator/device via the `run` skill before moving on — this is a visual redesign, type-checking alone doesn't confirm it looks right.

## 11. Suggested Sequencing

1. Phase 0 (foundations) — small, low-risk, unblocks everything else.
2. Phase 1 (tab bar) — highest visual impact, always on screen, good first proof point to show the user.
3. Phase 2 (Chat) — most-used feature.
4. Phase 3 (Shopping & Prices) — core utility loop.
5. Phase 4 (Recipes) — same patterns as Phase 3, should go faster.
6. Phase 5 (Settings & Onboarding) — lowest-frequency surfaces, do last.
7. Phase 6 folded in continuously, with a dedicated final pass.

Each phase should end with a build + on-device/simulator check before starting the next.
