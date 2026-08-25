# Liquid Glass Redesign — Handoff Log

Companion to `LIQUID_GLASS_REDESIGN_PLAN.md`. Append an entry per work session/phase so any agent (or Josh) can pick this up cold. Newest entry at the top. Each entry: what changed, why, how it was verified, what's next.

---

## 2026-08-25 16:15 CEST — Phase 2 (Chat) implemented

All of `LIQUID_GLASS_REDESIGN_PLAN.md` §6 done in one pass. Compiles clean after every step (`xcodebuild build`, compile-only). **Not yet verified on-device.**

**`Features/Chat/ChatView.swift`:**
- `chatHeader`: history button and the new-chat/memory button pair each wrapped in their own `GlassEffectContainer`; `HeaderIconButton` itself switched from a flat `.background(Color(.secondarySystemBackground), in: Circle())` to real `.glassEffect(.regular.interactive(), in: Circle())`. Header bar's own background stays `.thinMaterial` — it carries the session title/status text, which is content, not a control, so it stays off the "real glass" list per the plan's glass-is-for-controls principle.
- Message list: each `MessageBubbleView` and `TypingIndicatorView` now carries a `.transition(messageTransition)` (push-from-bottom + opacity, or a plain `.opacity` cross-fade under Reduce Motion), driven by two value-bound `.animation(.snappy, value:)` modifiers on `viewModel.messages.count` and `viewModel.isTyping` — deliberately not threaded through `ChatViewModel`, which has ~8 separate call sites that mutate the message list (`sendMessage`, `handleAIOnboardingAnswer`, `approveAll`, `approve`, `reject`, `rejectAll`, `handleResponse`, `collapseIfAllTerminal` via `AppStore.appendMessage`/`replaceMessage`); a value-bound animation on the view side covers all of them without touching the view model.
- `TypingIndicatorView` rebuilt on `PhaseAnimator` (three phases, one active dot at a time) instead of a manual `@State phase` + `sin()` + `.repeatForever` animation — falls back to static (non-animated) dots under Reduce Motion.
- Composer send button: `.buttonStyle(.glassProminent)` + `.tint(GlassTheme.tint)` replacing the manual `Circle()` background fill; disabled-state dimming now comes from the system's own `.disabled()` handling instead of manual color branching. Added a `sendBounce` trigger (`@State`, toggled on tap) driving `.symbolEffect(.bounce, value: sendBounce)` on the arrow icon.

**`Features/Chat/ActionProposalView.swift`:**
- Reject-All → `.buttonStyle(.glass).tint(.red)`; Approve-All → `.buttonStyle(.glassProminent)` (replacing `.bordered`/`.borderedProminent`).
- Per-row mini approve/reject circles in `ActionRow` left as plain colored circles, deliberately — these repeat once per action inside a scrolling list, and the plan calls out glass specifically for the card-level All buttons, not every repeated row control (also keeps glass-surface count bounded per the performance checklist item "glass effects are limited in number").
- `cardHeader`'s item-count text gets `.contentTransition(.numericText())` + `.animation(.snappy, value:)`.
- The `.completed` checkmark in `actionStatus` gets `.symbolEffect(.bounce, value: action.status)`.

**`Features/Chat/ActivityTagView.swift`:**
- `ActivityTagsView` wraps its tag rows in one `GlassEffectContainer`.
- `ActivityTagRow` swapped its flat `.background(color.opacity(...), in: RoundedRectangle...)` + `.overlay(stroke)` combo for `.glassEffect(_, in: RoundedRectangle(cornerRadius: 10, style: .continuous))`, tinted with the row's existing semantic color (green for actions, purple for memories) so that color coding survives the glass conversion. `.interactive()` applied conditionally — only when `hasTappableRecord` is true — per the skill's "interactivity only where interaction exists" rule, since untappable rows are a no-op tap target (`guard hasTappableRecord else { return }`).
- Did **not** use `glassEffectUnion` here despite the plan text suggesting it: these rows are a vertical stack of distinct, individually-tappable action records (each may navigate to a different detail sheet), not a horizontal run of decorative chips — unioning them into one merged glass shape would visually imply they're one control when they're not. Shared `GlassEffectContainer` still lets them blend at the edges without misrepresenting them as a single control.
- Removed `backgroundOpacity` (dead code once the manual background was replaced).

### What's next
- Josh to test Chat on-device: header buttons, message send/receive motion, typing indicator, action approve/reject cards, activity tag rows.
- Phase 3 (Shopping & Prices) is next per the plan — swipe actions, numeric price content transitions, zoom navigation transitions into detail views, camera viewfinder glass chrome.

---

## 2026-08-25 16:10 CEST — Phase 1 confirmed on-device; starting Phase 2 (Chat)

Josh confirmed on his phone: glass tab bar looks right, Chat bubble is bigger/raised without the stray caption, Prices search field is back in the nav bar. **Phase 1 is done and closed.** Moving on to Phase 2 per `LIQUID_GLASS_REDESIGN_PLAN.md` §6 — see the entry below for what's in scope.

---

## 2026-08-25 16:09 CEST — Polish pass: fake search-bar chrome, full bottom-clearance audit, Chat tab caption, search placement

Four separate reports/requests from Josh, addressed in sequence:

**1. "Search bar underneath the tab on Prices"** — the previous fix (#4) used `.safeAreaInset(edge: .bottom) { Color.clear... }` inside `reservesFloatingTabBarSpace()`. `List` in iOS 26 apparently draws its own background/edge-effect chrome behind *any* safe-area accessory region, even one whose content is `Color.clear` — that stray bar-shaped surface is what looked like a search bar. Swapped the modifier's implementation to `.safeAreaPadding(.bottom, inset)` (`DesignSystem/GlassTheme.swift`) — this reserves the same space as inert padding with no accessory slot for `List` to decorate.

**2. "Check all tabs for anything else falling behind the bar"** — audited every reachable screen in the app (not just the 5 tab roots), by grepping every `NavigationLink`/`.navigationDestination` in the codebase and tracing which destinations stay inside a tab's own `NavigationStack` (and are therefore still covered by the floating bar) versus which are `.sheet`-presented (full-screen, bar not visible, out of scope). Added `.reservesFloatingTabBarSpace()` to every in-stack destination that was missing it:
   - `Features/Shopping/ShoppingView.swift`: `ShoppingListDetailView`
   - `Features/Prices/PriceComparisonView.swift`: `PriceComparisonView` (reached via `.navigationDestination(isPresented:)` from Shopping, not obvious from a struct-name search alone)
   - `Features/Recipes/RecipesView.swift`: `RecipeDetailView`
   - `Features/Chat/ChatView.swift`: `ChatHistoryView`, `MemoryListView`
   - `Features/Settings/SettingsView.swift`: `CommunityPricingSettingsView`, `ShoppingOptimisationSettingsView`, `AIPermissionsView`, `StoreSettingsView`
   - `Features/Settings/AccountView.swift`: `AccountManagementView`

   None of these had a genuinely *fixed* (non-scrolling) bottom control — they're all plain `List`/`Form`. Confirmed scanner sheets (`BarcodeScannerView`, `ReceiptScannerView`) are always `.sheet`-presented, never pushed, so they're out of scope (a sheet covers the bar entirely). ChatView's composer was already fixed in the previous session (fix #4).

**3. "Chat caption sits way down, looks silly"** — root cause: `.offset(y: -14)` on `MainChatTabIcon` is a pure render-time transform, it doesn't participate in layout. The `VStack` computing where to place the "Chat" label below it still measured the icon's *un-offset* position, so the label ended up 14pt further from the icon than intended, reading as a stray floating word. Fix: dropped the "Chat" caption entirely (`chatTabButton` in `App/RootTabView.swift`) rather than fight the offset/layout mismatch — the bubble is already bigger and visibly raised, which reads as "the main tab" without needing a label. `accessibilityLabel("Chat")` stays on the button itself, so VoiceOver is unaffected. Also dropped `chatTabButton`'s frame height back to 58 (matching every other tab button) now that there's no caption needing extra vertical room — the bubble simply overflows above that 58pt slot on its own (native 64pt size + the offset), which is the intended raised-bubble look, and it no longer forces the whole bar taller than necessary.

**4. "Prices search bar still under the tab menu" (after fix 1 above)** — separate issue from the fake-chrome bug: `.searchable(text:prompt:)` was using `placement: .automatic`, which lets the system choose where the field renders; explicitly pinned it to `.navigationBarDrawer(displayMode: .always)` in `Features/Prices/PricesView.swift` so it's unambiguously in the top nav bar, never resolved elsewhere.

**Verification:** `xcodebuild build` after each change, all green (SourceKit's stale-index noise — "Cannot find AppStore/PriceObservation/etc. in scope" — continues to appear across every touched file and continues to be confirmed noise, not a real error; not calling this out per-fix anymore, it's a consistent known artifact of this session's SourceKit state). **None of today's fixes have been visually confirmed on-device yet** — all reasoning is from Josh's descriptions.

### What's next
- Josh to re-test on-device: glass look, Chat tab bubble (no caption, raised, bigger), Prices search field position, and spot-check a couple of the newly-audited pushed screens (e.g. Shopping → a list → still scrolls fully above the bar).
- Once the tab bar is confirmed stable and correct, resume Phase 2 (Chat) — this session has been entirely tab-bar stabilization so far, no forward progress on the phase plan.

---

## 2026-08-25 15:59 CEST — Fix #4: floating overlay again, done explicitly this time

**Reported by Josh:** flow layout (fix #3) works correctly — content no longer hides behind the bar, everything's reachable. But it doesn't look like glass at all.

**Why:** this is expected, not a bug. Liquid Glass renders by refracting/blurring whatever's *behind* it. In flow layout the bar sits in its own dedicated strip with flat app background behind it — nothing there to distort, so `.glassEffect()` reads as barely different from a flat material. Every real Apple Liquid Glass surface (Camera, Music, Safari) floats *over* content for exactly this reason. Confirmed this tradeoff with Josh directly (via AskUserQuestion) before touching more files, since we'd already burned three attempts: chose "floating overlay, done explicitly" over "keep flow layout, fake the depth with a backdrop."

**Fix (more invasive — touches 6 files):**
- `DesignSystem/GlassTheme.swift`: added `EnvironmentValues.floatingTabBarInset` (`@Entry`, default 0) and a `View.reservesFloatingTabBarSpace()` modifier (wraps `.safeAreaInset(edge: .bottom) { Color.clear.frame(height: inset) }`, reading the environment value internally).
- `App/RootTabView.swift`: back to `ZStack(alignment: .bottom)` with `currentTab` filling the full screen and `customTabBar` floating on top. Critically different from fix #1/#2: the bar's height is **measured live** via `.onGeometryChange(for: CGFloat.self)` into `@State private var measuredTabBarHeight`, then handed down through `.environment(\.floatingTabBarInset, measuredTabBarHeight)` on `currentTab`. No hand-maintained height constant, no reliance on an ancestor `.safeAreaInset` crossing into each tab's `NavigationStack` — each tab is responsible for consuming the environment value itself, at the point where it actually needs the clearance.
- `Features/Shopping/ShoppingView.swift`, `Features/Prices/PricesView.swift`, `Features/Recipes/RecipesView.swift`, `Features/Settings/SettingsView.swift`: added `.reservesFloatingTabBarSpace()` directly on each `List`/`Group` — applied at the *same* view that owns the scrollable content, not on an ancestor, so there's no `NavigationStack` boundary for the reservation to fail to cross (that boundary-crossing is exactly what broke fix #1/#2 for Shopping).
- `Features/Chat/ChatView.swift`: added `@Environment(\.floatingTabBarInset)`, applied `.padding(.bottom, floatingTabBarInset)` directly to `inputBar` (the composer isn't a scroll container, so the `reservesFloatingTabBarSpace()` scroll-inset modifier doesn't apply to it — it needs a plain trailing padding push instead).

**Verification:** `xcodebuild build`, compile-only, green (SourceKit threw its now-familiar batch of stale "Cannot find AppStore/PriceObservation/etc. in scope" index errors across every file touched this session — consistently proven to be index desync, not real; the actual compiler succeeds every time). **Not yet verified on-device.**

### What's next
- Josh to re-test on-device: (1) does it now visually read as glass, (2) is every tab's bottom content still fully reachable (re-check Shopping's last list item and Chat's composer specifically, since those were the two that broke before).
- If the glass look is confirmed and stable, resume Phase 2 (Chat) — this tab bar saga has consumed the entire session so far.
- If content-hiding regresses on any tab, check whether `.reservesFloatingTabBarSpace()` was applied to the right node (must be the actual `List`/`ScrollView`, not a parent `NavigationStack` — attaching it to `NavigationStack` itself was never tried and might behave differently since `NavigationStack` is exactly the boundary type this fix is designed to avoid crossing).

---

## 2026-08-25 15:50 CEST — Fix #3 (the real fix): dropped the floating-overlay architecture entirely

**Reported by Josh:** still janky, and crucially — **the "grey mark in the bottom-right corner" is not a glass rendering artifact at all. It's the Chat composer (the message input box) rendering underneath the tab bar.** Container still missing on Shopping, still fine on Prices.

**This corrects the diagnosis from both prior entries.** Fix attempts #1 and #2 were reasoned around `GlassEffectContainer`/backdrop-sampling instability theories that were never actually confirmed — I don't have a way to see the device screen and was inferring a rendering-engine cause from a symptom that was actually a plain layout bug. With the composer identified as literally mispositioned (not a rendering glitch), the real story is simpler and more boring:

Attempts #1/#2 tried to make the tab bar *float* above content (an overlay, or a `.safeAreaInset` accessory) and hand-reserve its height so scrollable content stops short of it. That reservation has to propagate from `RootTabView` down through each tab's own `NavigationStack` to that tab's content. It evidently does for `List`-based tabs (Prices, and presumably Recipes/Settings) — `List` computes its own content insets from the ambient safe-area environment reliably. It evidently does **not** for `ShoppingView`'s plain `ScrollView`+`LazyVStack`, and it does **not** reach `ChatView`'s `inputBar`, which is just a plain `VStack` row with no safe-area awareness of its own — it simply sits at the bottom of whatever height `ChatView` gets proposed, and that height wasn't being reliably reduced by the ancestor reservation. Rather than chase exactly which SwiftUI safe-area-propagation rule is or isn't crossing each `NavigationStack` boundary (three attempts already burned on theories I couldn't verify on-device), the fix removes the need to coordinate this at all.

**Fix:** reverted `RootTabView.body` to the same structural shape as the pre-redesign code — `VStack(spacing: 0) { currentTab; customTabBar }`, a plain flow layout where the tab bar is a normal sibling occupying real vertical space, not an overlay. No `.safeAreaInset` accessory, no reserved-height constant, no `ZStack`. Every tab's content is given a proposed height that already excludes the bar, by construction — there is nothing left to coordinate, so the whole bug class (content rendering under the bar) is now structurally impossible regardless of whether a given tab uses `List`, `ScrollView`, or a custom `VStack`. `customTabBar`'s internals (the `GlassEffectContainer` + `.glassEffect(.regular, in: Capsule())` pill, the tinted `matchedGeometryEffect` selection capsule, the chat bubble's own glass circle) are unchanged — only the outer layout strategy changed.

No changes were needed in `ChatView.swift` or `ShoppingView.swift` — this was fixed entirely at the `RootTabView` layout level.

**Verification:** `xcodebuild build`, compile-only, green. **Still not verified on-device.**

### What's next
- Josh to re-test on-device. This should be the most reliable fix yet since it removes an entire mechanism (floating overlay + hand-reserved safe area) rather than patching it further.
- If the composer/content-under-bar issue is gone but the glass container itself still looks visually broken (doesn't render, wrong shape, etc.) on Shopping specifically even in this flow-layout structure, that would newly (and more credibly) implicate `GlassEffectContainer`/`.glassEffect()` rendering itself rather than layout — worth testing Shopping specifically once this lands, since it's the one tab that's been reported bad across all three attempts.
- Resume Phase 2 (Chat) once the bar is confirmed stable.

---

## 2026-08-25 15:44 CEST — Fix attempt #2: bar moved out of `.safeAreaInset` accessory

**Reported by Josh:** the previous fix didn't help. New detail that disproves the identity-rebuild theory: behavior is *per-tab*, not just "on every switch" — the glass container disappears specifically when landing on Shopping, is visible on Prices, and shows a grey artifact in the bottom-right corner specifically on Chat. That's deterministic per-tab, not a generic rebuild race.

**Revised theory:** each tab owns its own `NavigationStack` with its own `List`/`ScrollView`, and iOS 26 scroll views automatically pick up a scroll-edge glass/blur effect near a bottom safe-area accessory. Rendering our custom `GlassEffectContainer` *as* the `.safeAreaInset(edge: .bottom)` accessory content puts it in the same compositing slot the system is also trying to manage per-tab (differently, depending on that tab's scroll state/content), which plausibly explains why the result differs by tab.

**Fix:** stopped rendering the glass bar as the `.safeAreaInset` accessory itself. Now `.safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarReservedHeight) }` only reserves scroll space (a plain transparent spacer, nothing glass, nothing for the system to fight over), and `customTabBar` renders as an ordinary `.overlay`-style sibling in an outer `ZStack(alignment: .bottom)` instead — outside the accessory system entirely. `tabBarReservedHeight` is a hand-computed constant (100pt) matching the bar's actual rendered height (72pt tallest child + 16pt capsule padding + 8pt outer bottom padding); if the bar's visual size changes later, this constant needs updating alongside it.

**Verification:** `xcodebuild build`, compile-only, green. **Still not verified on-device** — I do not have a way to see the actual glass rendering myself; every fix so far has been reasoned from Josh's on-device description, not observed directly.

### What's next
- Josh to re-test on-device.
- **If this still doesn't fix it**, stop iterating blind on the compositing theory and fall back to something guaranteed stable: drop `GlassEffectContainer` and render `customTabBar` with a single flat `.glassEffect(.regular, in: Capsule())` with no container (simplest possible glass call, no nested/sibling glass shapes at all — remove `MainChatTabIcon`'s own separate `.glassEffect()` too, replace it with the pre-redesign flat color fill). That isolates whether *any* custom glass in this position is unstable on Josh's device/OS build, versus specifically the container/multi-shape composition being the problem.
- Once the bar is confirmed stable, resume Phase 2 (Chat).

---

## 2026-08-25 15:38 CEST — Fix: tab bar identity-rebuild bug (on-device report)

**Reported by Josh after on-device testing:** the floating glass tab bar sometimes rendered without its glass container, and a "weird grey mark" intermittently appeared in the right corner. Overall janky.

**Root cause found:** in `App/RootTabView.swift`, the Phase 1 rewrite had chained `.safeAreaInset(edge: .bottom) { customTabBar }` directly onto `currentTab` — and `currentTab` is a `switch` over `selectedTab`, so it gets a **new view identity on every tab change**. That tore down and rebuilt the `GlassEffectContainer`-backed tab bar (which was living inside that `safeAreaInset` accessory) on every single tab switch, forcing its Metal-backed glass backdrop to reinitialize each time — the flicker and stray grey artifact are consistent with catching that backdrop mid-teardown/rebuild.

The pre-redesign code never had this problem because the tab bar was a plain, always-present sibling inside a stable outer `VStack`, never nested inside the switched content.

**Fix:** wrapped `currentTab` in a stable `VStack(spacing: 0)` and moved `.safeAreaInset(edge: .bottom) { customTabBar }` onto that `VStack` instead of directly onto `currentTab`. The `VStack`'s own identity never changes across tab switches (only its child does), so the glass bar attached to it now persists identity and never gets torn down. Added a code comment at the call site explaining why, so a future edit doesn't reintroduce this by moving the modifier back onto `currentTab` for convenience.

Ruled out (for the record, so it isn't re-investigated): the `MainChatTabIcon`'s 50pt circle vs. other buttons' 58pt row height. The bar's `Capsule` glass shape sizes to the HStack's full bounding box (which already accounts for the tallest child, the 72pt-tall chat button, plus padding), so the icon was never actually overflowing/overlapping the bar's bounds — that mismatch is not a contributing factor.

**Verification:** `xcodebuild build` (compile-only, no simulator launch, per Josh's standing instruction — he tests on his physical phone via Xcode) — green. **Not yet re-verified on-device** — that's the next step, on Josh's phone.

### What's next
- Josh to re-test the tab bar on-device to confirm the flicker/grey-artifact is gone.
- If still janky after this fix, the next suspect (in order) would be: (a) the two nested `.glassEffect()` calls in one `GlassEffectContainer` (bar capsule + chat bubble circle) — consider splitting them into separate containers or dropping the bubble's own glass in favor of a plain tinted circle if on-device blending looks unstable; (b) interaction between `.ignoresSafeArea(.keyboard, edges: .bottom)` and `.safeAreaInset` when the keyboard shows/hides on the Chat tab.
- Phase 2 (Chat) work is still queued behind confirming this fix lands clean.

---

## 2026-08-25 15:33 CEST — Phase 0 (Foundations) + Phase 1 (Tab Bar) complete

**Status:** Phases 0–1 of `LIQUID_GLASS_REDESIGN_PLAN.md` done and compile-clean. Phases 2–6 not started.

### What changed

**Phase 0 — Foundations**
- `Store/AppStore.swift`: added `@MainActor` to `class AppStore` (was `@Observable` only, unlike `AuthStore` which was already correctly isolated). This is a correctness prerequisite for animation-driven UI under Swift 6 concurrency, per the `swiftui-patterns` skill.
  - Fallout from that fix: `createChatSession(messages:)`'s default parameter `[AppStore.welcomeChatMessage()]` failed to compile ("call to main actor-isolated static method... in a synchronous nonisolated context") — default-argument expressions don't inherit the enclosing type's actor isolation the same way method bodies do. Fixed by marking `welcomeChatMessage()` and `aiOnboardingMessage()` (same shape, same risk) `nonisolated` — both are pure constructors with no actor-isolated state access, so this is safe.
  - Verified `ChatViewModel` was already `@MainActor` — no change needed there.
  - Audited `Features/*` and `Store/*` for `DateFormatter()`/`NumberFormatter()` allocations inside SwiftUI `body` (a `swiftui-performance` smell). Only hit was in `AppStore`'s model layer (not a view body) — no fix needed.
- Added `DesignSystem/GlassTheme.swift` — shared tokens (`GlassTheme.tint`, `.containerSpacing`, `.cornerRadius`, `.motionSpring`) and a `View.motionSensitive(reduceMotion:_:)` helper for gating large-motion additions behind Reduce Motion. Every subsequent glass/animation addition should reference these instead of hardcoding values.
- **Project file surgery**: this Xcode project references Swift files individually (`PBXFileReference`/`PBXBuildFile`/`PBXGroup`), it does *not* use folder-sync for source code — only the `PrisPilot/` assets folder was a `PBXFileSystemSynchronizedRootGroup`. Rather than hand-add a `PBXFileReference`/`PBXBuildFile` pair for every future design-system file, added `DesignSystem/` itself as a new synced root group (mirrors the assets-folder pattern) so any file dropped in there going forward is auto-included with zero further `project.pbxproj` edits. If you add files to `App/`, `Features/*`, `Models/`, `Services/`, or `Store/`, they still need manual `project.pbxproj` entries (or add them via Xcode's UI, which the user has open) — only `DesignSystem/` is on auto-include.

**Phase 1 — Root Navigation Shell**
- Rewrote `App/RootTabView.swift`:
  - Tab bar switched from `.background(.regularMaterial)` flat band to a real floating glass pill: `GlassEffectContainer(spacing: GlassTheme.containerSpacing)` wrapping the `HStack` of tab buttons, with `.glassEffect(.regular, in: Capsule())` applied after layout/appearance modifiers (per the skill's modifier-order rule), pulled off the bottom edge via `.safeAreaInset(edge: .bottom, spacing: 0)` (replacing the old plain `VStack` layout) so scrollable tab content gets correct bottom clearance without a manual `.background(.regularMaterial)` band.
  - `MainChatTabIcon` (the raised center "Chat" bubble) now uses `.glassEffect(.regular.tint(.blue).interactive(), in: Circle())` when selected, plain `.regular.interactive()` glass when not — replacing the old flat `Color.blue`/`Color(.secondarySystemBackground)` fill. It sits inside the *same* `GlassEffectContainer` as the bar background so the two glass shapes visually blend where they're close, rather than reading as two flat separate materials.
  - Selection indicator: a small tinted `Capsule` (not glass — it's decorative, not a control, per the "glass is for controls" principle) driven by `.matchedGeometryEffect(id: "tabSelection", in: tabBarNamespace)`, so it slides between tabs instead of popping.
  - Tab icons swap outline ↔ filled SF Symbol variant (`cart` ↔ `cart.fill`, etc.) via `.contentTransition(.symbolEffect(.replace))`.
  - Tab switching goes through a new `selectTab(_:)` that checks `@Environment(\.accessibilityReduceMotion)`: normal case fires a light `UIImpactFeedbackGenerator` haptic and wraps the state change in `withAnimation(GlassTheme.motionSpring)`; Reduce-Motion case sets `selectedTab` directly with no haptic/spring, which also implicitly suppresses the symbol-replace and matched-geometry animations since they ride on the same state change.
  - Added `.accessibilityAddTraits(.isSelected)` to the active tab button.

### How this was verified
- `xcodebuild -project PrisPilot.xcodeproj -scheme PrisPilot -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -configuration Debug build` — compile-only, **no simulator boot/launch** (the user asked not to load the simulator; they're testing on a physical device via Xcode themselves). Ran after each meaningful edit; all green, no errors.
- Not yet visually verified on-device — that's on the user via their own Xcode → physical phone workflow.
- One stale-index SourceKit diagnostic (`No such module 'UIKit'` in `RootTabView.swift`) appeared after edits — not a real error (the actual compiler build succeeded with `UIKit` imported and `UIImpactFeedbackGenerator` resolving fine); should clear on Xcode's own re-index.

### What's next (Phase 2 — Chat)

Per the plan, `Features/Chat/*` is next:
- `ChatView.swift` header buttons → `GlassEffectContainer` + `.buttonStyle(.glass)`, decide whether the header bar itself becomes `.glassEffect()` or stays `.thinMaterial`.
- Message-insertion transitions (`.transition(.asymmetric(...))` around `viewModel.messages` mutations in `ChatViewModel.swift`).
- Rebuild `TypingIndicatorView` with `PhaseAnimator`/`KeyframeAnimator`.
- `ActionProposalView.swift` Approve/Reject → `.buttonStyle(.glassProminent)` / `.buttonStyle(.glass)`.
- `ActivityTagView.swift` tag pills → `GlassEffectContainer` + `.glassEffectUnion`.
- Composer/send button → `.buttonStyle(.glassProminent)` + `.symbolEffect(.bounce)` on send.

Before starting Phase 2, run the Phase 6 accessibility checklist against what Phase 1 shipped (Reduce Transparency, Reduce Motion, VoiceOver on the tab bar) — not yet done, since it needs eyes on a real device/simulator, which this session deliberately avoided.

### Open questions / risks for the next session
- The floating pill vs. edge-anchored tab bar decision was made (went with floating pill, `.safeAreaInset`) — if the user dislikes the look on-device, the fallback noted in the plan is to keep it edge-anchored but still swap material for real glass.
- Haven't confirmed the new tab bar height/spacing doesn't clip on smaller devices (e.g. SE) — worth a look when testing on-device.
