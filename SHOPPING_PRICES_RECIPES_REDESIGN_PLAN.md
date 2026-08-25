# Shopping, Prices, and Meals Redesign Plan

## Purpose

This document captures the redesign direction for the three non-chat work tabs:

- Shopping
- Prices
- Meals

The Chat tab remains the intelligence layer over all three areas. Users should be able to inspect and manually manage everything in these tabs, while the AI can propose and execute controlled CRUD actions through the existing app action system.

The redesign should make the app feel like a practical grocery command center, not a set of simple lists.

## Product Model

PrisPilot is built around this loop:

1. The user records product prices from stores, receipts, barcode scans, manual entry, chat, or community data.
2. The app keeps price observations fresh, trustworthy, and comparable across stores.
3. Shopping lists are optimized against those prices using user settings.
4. Recipes, meal plans, and matkasse boxes generate future shopping demand.
5. Chat can create, update, explain, and optimize all of this through approved app actions.

## Shared Principles

- AI is helpful, but the tabs must work without chat.
- Prices are evidence, not just labels. Each price needs source, freshness, store, confidence, and unit context.
- Shopping lists are trip plans. A list should answer where to buy each item, why, and what the total trip should cost.
- Meals are planning objects. A recipe should connect to ingredient prices, shopping lists, and meal-plan slots.
- Community data should be visible as community data, with trust indicators.
- All destructive changes need clear confirmation or undo.
- Screens should be dense, scannable, and iPhone-friendly.

## Current Foundation

Already present in the app:

- `ShoppingList` has active, completed, and archived status.
- `ShoppingListItem` can store assigned supermarket, estimated price, actual price, notes, and completion state.
- `PriceObservation` supports source, scope, confidence, freshness, promotion state, quantity, unit, and store branch.
- Community price observations already exist as a source.
- Settings already include max supermarket count, minimum savings threshold, travel cost, fixed store visit cost, and cheapest strategy.
- `AppStore.optimizeShoppingList(_:)` already assigns pending items to stores using saved prices and the user's thresholds.
- Recipes already have ingredients, steps, tags, favorite state, scope, and cost estimates.

## Confirmed Product Decisions

Shopping:

- Store assignment should work both ways: automatic optimization after list changes, plus a manual Optimize action when the user wants explicit control.
- If an item has no price data, chat should ask whether to use a preferred store or a default store. Manual entry should expose a default store picker.
- Community pricing should ship opt-in enabled by default so the app can build useful store and area coverage quickly.
- Shopping needs an in-store mode with larger checkboxes and fewer controls.

Prices:

- Prices should expose Products, Stores, Needs Prices, and Community as top-level modes.
- Community and personal prices can share the same product surface, but they need separate fields/labels. If values match, show that the community confirms the price.
- Prices become stale after 60 days by default.
- Promotion and member prices can be used in optimization by default, but the app must clearly label that the selected price is promotion/member-only.

Meals:

- Rename the Recipes tab to Meals.
- Meal planning should support breakfast, lunch, dinner, and other user-selected meal types.
- Matkasse support should not be branded to HelloFresh. Store both weekly boxes and individual meals.
- Meal-plan-to-shopping-list generation should ask whether the user wants one weekly list or separate lists per shopping trip.

## Phase Order

1. Plan all three tabs at product level.
2. Build Shopping first.
3. Build Prices second.
4. Build Meals third.
5. Expand AI actions after each tab has the data and UI shape needed.

## Cross-Tab Feature Bank

Features that connect all three tabs:

- Price coverage score for every list and meal plan.
- "Needs attention" queue shared across Shopping, Prices, and Meals.
- Confidence labels for every optimized recommendation.
- "Why this store?" explanations using price, freshness, travel settings, and savings threshold.
- Community confirmation badges when local and community prices agree.
- Duplicate product detection across manual entry, receipt scans, chat, and community prices.
- Store preference memory, so the app knows which stores the user likes, avoids, or only visits for meaningful savings.
- Household mode with personal versus shared lists, prices, recipes, and meal plans.
- Offline-first manual editing with later sync/community upload.
- Audit trail for AI changes, manual changes, receipt imports, and community-sourced suggestions.
- Undo for AI and bulk actions wherever practical.

## Feature Priority Rubric

When choosing what to build first, prefer features that score well on these:

- Saves money immediately.
- Reduces repeated manual entry.
- Improves trust in recommendations.
- Makes shopping faster in the store.
- Feeds better AI suggestions later.
- Works with local data before cloud/community systems are complete.

Features that are cool but require cloud, location services, large data migrations, or external integrations should be planned, but not allowed to block the first useful redesign.

## Ambitious Cross-Tab Ideas

These are bigger ideas that could make PrisPilot feel much smarter once the core workflow is solid:

- Household savings dashboard showing monthly estimated savings from optimized shopping.
- "Food command center" home summary across Shopping, Prices, and Meals.
- Price intelligence score for each household: coverage, freshness, confidence, and community contribution.
- Personal grocery inflation tracker comparing this month against prior months.
- Budget forecast that combines meal plans, active lists, recurring staples, and matkasse costs.
- AI weekly planning review: "You have 4 dinners planned, 1 unpriced ingredient, and your shop is kr 82 over budget."
- Recommendation explanations that always cite the data used: price, date, source, confidence, and store.
- Smart notifications for stale important prices, but only for products tied to active lists or meal plans.
- Area-based community price pools, so the app learns what prices are relevant around the user rather than globally.
- Trust tiers for community prices: single report, multiple matching reports, verified by receipt, confirmed by you.
- Personal "do not buy" and "always buy" rules that apply across shopping, prices, and meals.
- Price-change alerts for staples and favorite products.
- Savings challenges, such as "keep this week's shop under kr 800."
- Monthly recap: top savings, most expensive categories, most-used stores, best community-confirmed prices.
- AI-generated cleanup tasks, such as merge duplicate tomatoes, confirm stale milk price, archive old taco list.
- Data export/import for backup and transparency.
- Widgets for next shopping trip, meal tonight, and prices needing confirmation.
- Siri/App Intents later: add item, log price, show next store, mark bought.
- Share extension later for recipe text or grocery offers from other apps.
- Privacy controls that clearly separate personal, household, and community data.

## Shopping Tab

### Goal

Shopping should show current shopping lists and make each list feel like an optimized store-by-store trip plan.

The main job is not merely "items to buy." It is:

- What lists are active now
- Which stores each list requires
- What to buy in each store
- What the estimated total is
- What is missing price data
- Whether splitting across stores is worth it
- What has been bought
- What should be archived

### Top-Level Structure

The Shopping tab should have:

- Active lists
- Planned / upcoming lists
- Completed lists
- Archived lists
- Quick create entry point
- AI prompt entry point for building or optimizing a list

Recommended first screen:

1. Header summary
   - Active list count
   - Next planned shop date
   - Estimated spend for active lists
   - Missing price count

2. Segmented control
   - Active
   - Planned
   - Completed
   - Archived

3. List cards
   - List name
   - Scope: personal or household
   - Planned date
   - Item progress
   - Estimated total
   - Stores required
   - Savings versus one-store shop
   - Warning if price data is missing or stale

4. Primary actions
   - New list
   - Optimize all active lists
   - Ask AI

### Shopping List Detail

The detail screen should be centered on store grouping.

Recommended layout:

1. Trip summary band
   - Estimated total
   - Actual total so far
   - Savings
   - Number of stores
   - Items priced / unpriced
   - Optimization explanation

2. Optimization controls
   - Optimize button
   - One-store toggle or mode picker
   - Max stores display from settings
   - Minimum savings display from settings
   - Reassign manually action

3. Store sections
   - Store name
   - Store subtotal
   - Item count
   - Distance or route note when available
   - Confidence summary
   - Items assigned to that store

4. Item rows
   - Product emoji or category icon
   - Product name
   - Quantity
   - Best known price
   - Price source and age
   - Checkmark for bought
   - Quick price correction
   - Move to another store
   - Substitute item

5. Unassigned / Needs Price Data section
   - Items without price data
   - CTA to add price manually
   - CTA to ask community / use community price
   - CTA to scan barcode or receipt

6. Completed section
   - Collapsible bought items
   - Actual price capture
   - Undo completion

### Shopping Workflows

- Create a list manually.
- Create a list from chat.
- Create a list from recipe or meal plan.
- Add items manually.
- Add items by barcode scan.
- Add items from receipt history.
- Optimize a list against saved prices.
- Accept or change store assignments.
- Mark items as bought.
- Capture actual price while shopping.
- Re-optimize after adding items or correcting prices.
- Complete and archive a list.
- Reopen an archived list as a template.

### Shopping Data Gaps

Likely model additions:

- Shopping list planned date should become more visible and editable.
- Shopping list should track optimization snapshot:
  - chosen stores
  - estimated one-store total
  - optimized total
  - savings
  - unpriced item count
  - optimization date
- Shopping list item should track selected price observation ID, not only assigned store name.
- Shopping list item should support substitute candidates.
- Archived lists may need completed date and archive date.
- Actual in-store buying could benefit from quantity bought and actual unit price.

### Shopping Open Questions

- Should the Shopping tab default to Active lists, or should it default to the next planned shopping trip?
- Do you want one list to represent one shopping trip, or can one list span multiple trips?
- How should stale prices affect optimization after 60 days: warning only, lower confidence, or exclude unless no other price exists?
- Should the app calculate travel cost and store visit effort in the first Shopping rebuild, or keep that as a later phase?
- Should completed lists be separate from archived lists, or should completed lists auto-archive after a delay?
- Do you want list templates, such as Weekly Basics, Taco Night, or Breakfast Staples?

### Shopping Feature Bank

High-value features:

- Smart list overview with Active, Planned, Completed, and Archived filters.
- Next-shop dashboard that picks the most relevant upcoming list.
- Automatic background optimization when list items, settings, stores, or prices change.
- Manual Optimize button with before/after explanation.
- Store-by-store trip plan with subtotals, item counts, and savings.
- In-store mode with large checkboxes, store sections, "next item" focus, and fast actual-price entry.
- Unpriced item queue inside each list.
- Default store picker for unpriced manual items.
- Preferred store memory for chat-created unpriced items.
- Quick action to move one item to another store.
- Quick action to force whole list into one store.
- "Worth the extra stop?" comparison before adding another store.
- "At store now" mode that filters only the current store's items.
- Route-aware ordering later if store locations are configured.
- Item substitution suggestions based on cheaper products or user preferences.
- Pantry / already-have toggle to exclude items before shopping.
- Budget cap on a list, with warnings when estimated total exceeds it.
- Shared household list presence later, showing who added or completed an item.
- Reusable templates from past lists.
- Duplicate item merge when chat/manual entry adds the same product twice.
- Receipt reconciliation after shopping: compare estimated versus actual spend.
- Archive with summary: total spent, stores visited, savings, missing prices captured.

Nice-to-have later:

- Apple Watch style checklist later if the iPhone in-store mode proves useful.
- Location nudges when near a configured supermarket.
- Store aisle ordering if aisle data ever exists.
- Recurring lists for staples.
- "Buy now or wait" suggestions when a product is often discounted.

Ambitious later:

- Live trip progress: selected store, bought count, remaining subtotal, next store.
- "Checkout mode" that lets the user quickly enter actual totals and reconcile individual items later.
- Smart split-trip planner that estimates whether the extra stop is worth it after travel cost and time.
- Store visit history with actual spend and savings per store.
- Shopping route ordering once branch locations are known.
- "Skip this week" for recurring staple items.
- Household assignments: who is buying which store section.
- Shared live list updates for household shopping.
- Substitution approval rules: allow cheaper brand, avoid certain brands, require same package size.
- Budget-aware item ranking: show which items push the list over budget.
- Cheapest complete basket versus cheapest practical basket comparison.
- "Forgotten item" detector from repeated post-shop additions.
- Return-to-store reminder for skipped/unavailable items.
- Low-stock staple prompts based on normal purchase frequency.
- Voice-friendly in-store mode for hands-busy shopping later.
- List health score: priced coverage, stale coverage, confidence, budget fit, and optimization freshness.

## Prices Tab

### Goal

Prices should be the product and price intelligence database. It should make it easy to enter prices, inspect price history, compare stores, and understand whether a price is trustworthy.

This tab should answer:

- What prices do I know?
- Which store is cheapest for a product?
- Which prices are stale?
- Which products are missing prices for an upcoming shop?
- What did the community report?
- Which prices need confirmation?
- Where do promotions or loyalty prices apply?

### Top-Level Structure

Recommended first screen:

1. Header summary
   - Products tracked
   - Stores tracked
   - Prices logged this week
   - Stale prices
   - Community prices available

2. Search
   - Product
   - Store
   - Barcode
   - Category

3. Segmented control or tabs
   - Products
   - Stores
   - Needs Prices
   - Community

4. Quick actions
   - Add price
   - Scan receipt
   - Scan barcode
   - Add store
   - Import / sync later

### Product Price Detail

Each product should have a detail view:

- Current cheapest store
- Price range across stores
- Unit price comparison
- Last observed date per store
- Personal price observations
- Community price observations
- Price history chart
- Promotion history
- Confidence and freshness
- Add new price
- Flag community price
- Merge duplicate product names
- Aliases and barcode management

### Prices Workflows

- Manually enter a price.
- Scan receipt and approve parsed lines.
- Scan barcode and attach price.
- Compare one product across stores.
- Find stale prices.
- Fill missing prices for an upcoming shopping list.
- Accept or reject community price suggestions.
- Flag suspicious community prices.
- Convert package price to unit price.
- Track member or loyalty price separately from regular price.

### Prices Data Gaps

Likely model additions:

- Product category should become first-class and consistently used.
- Product aliases and barcode matching need management UI.
- Unit price normalization is needed for fair comparison.
- Price observation should keep optional selected product variant or package size.
- Community prices need aggregation and trust summary, not just individual rows.
- Promotions need end date, price type, and possibly member requirement.
- Store branch metadata should include location, distance, and preferred status.

### Prices Open Questions

- How strict should product matching be when names differ slightly between stores?
- Do you want package-size comparisons normalized automatically, such as kr per kg or kr per liter?
- Should the app show price trends and charts in the first redesign, or save charts for later?
- Do you want a "prices needed for next shop" queue generated from Shopping and Recipes?
- Should users be able to attach receipt images to price observations?
- Should the app support store loyalty/member prices as separate from regular shelf prices?

### Prices Feature Bank

High-value features:

- Top-level modes: Products, Stores, Needs Prices, Community.
- Product cards with cheapest known store, price range, source, and freshness.
- Store cards with coverage count, recent prices, stale prices, and likely best categories.
- Needs Prices queue generated from active shopping lists and meal plans.
- Community tab with nearby reports, confidence, matching personal prices, and suspicious outliers.
- Product detail with personal prices, community prices, trends, and current best option.
- Store detail with all products priced there and stale-price prompts.
- Unit-price normalization, such as kr/kg, kr/l, kr/stk, and package price.
- Package-size comparison warnings when one price is cheaper only because the pack is much bigger.
- Promotion/member labels in every row and optimization explanation.
- 60-day stale threshold with visible freshness labels.
- Receipt scan review queue where parsed prices can be approved, corrected, merged, or ignored.
- Barcode scan flow that links a barcode to an existing product or creates a new product.
- Duplicate product merge tool.
- Product aliases for store-specific names.
- Price confidence model that combines source, age, community agreement, and outlier detection.
- Price correction workflow from shopping list item rows.
- "Confirm this price" prompts for prices that are stale but important to active plans.
- Store/area community coverage map later if location support becomes important.

Nice-to-have later:

- Price trend charts per product.
- Category inflation view.
- Best time to buy predictions after enough history exists.
- Share/export price book.
- Import store campaign flyers if a reliable source exists.
- Watchlist for favorite products and staple price drops.
- Community reputation signals without exposing personal identity.

Ambitious later:

- Price graph per product with personal, household, and community lines.
- "Normal price" detection so promotions can be judged against a baseline.
- Automatic deal quality label: good, average, suspicious, likely promotion.
- Category dashboards: dairy, meat, produce, pantry, frozen, household.
- Store strength profile: which store is usually cheapest for which categories.
- Store comparison matrix for selected products.
- Nearby community heatmap for price freshness and store coverage.
- Receipt image attachment and OCR audit trail.
- Receipt total reconciliation against parsed line items.
- Barcode-to-product learning from community confirmations.
- Product variant management: size, brand, organic, lactose-free, gluten-free, etc.
- Unit conversion warnings when comparing incompatible products.
- Price anomaly alerts: price much higher/lower than usual.
- Community challenge queue: "Confirm these 5 high-impact prices near you."
- Campaign tracking with start/end dates and member requirements.
- Loyalty/member card notes by store chain.
- Product replacement suggestions based on price, preference, and dietary constraints.
- Historical lowest price badge.
- "Price needed before shop" push or in-app task.
- Store coverage leaderboard for the user's area.
- Confidence decay by category: produce changes faster than canned goods.

## Meals Tab

### Goal

Recipes should evolve into Meals. Recipes are still important, but the top-level job is planning what will be eaten and turning that plan into a priced shopping list.

This area should handle:

- Saved recipes
- Weekly, fortnightly, and monthly meal plans
- Matkasse meals from any provider
- Recipe costing
- Ingredients to shopping list
- Planned leftovers
- Household preferences and dietary requirements

### Top-Level Structure

Recommended first screen:

1. Meal plan calendar
   - Week view first
   - Switch to fortnight or month
   - Breakfast, lunch, dinner, snacks, or custom meal types
   - Dinner-first default can still be a setup preference

2. This week summary
   - Planned meals
   - Matkasse meals
   - Meals still open
   - Estimated grocery cost outside matkasse
   - Missing ingredient prices

3. Meal source sections
   - Planned recipes
   - Matkasse meals
   - Quick meals
   - Favorites
   - Recently cooked

4. Primary actions
   - Add meal
   - Create recipe
   - Generate meal plan
   - Build shopping list
   - Add matkasse box

### Recipe Detail

Recipe detail should include:

- Title, servings, tags, favorite
- Ingredients with quantities and emojis where useful
- Method
- Estimated cost
- Cost per serving
- Store-by-store ingredient availability
- Missing price warnings
- Scale servings
- Add to meal plan
- Add missing ingredients to shopping list
- Substitute ingredients
- Duplicate recipe

### Matkasse Support

Matkasse meals should be represented separately from normal recipes where needed.

Open design:

- A matkasse box can have provider, delivery week, number of meals, price, servings, and included recipes.
- Matkasse meals should appear on the meal plan but should not always generate grocery-list ingredients.
- Optional extras from matkasse meals can still become shopping-list items.
- The meal plan should show which meals are already covered by a matkasse box.

### Recipes / Meal Planning Workflows

- Browse saved recipes.
- Create recipe manually.
- Create recipe through AI conversation.
- Edit recipe ingredients and steps.
- Plan a week of meals.
- Add 3 or 4 matkasse meals to the week.
- Generate remaining meals around the matkasse plan.
- Build a shopping list from meal plan.
- Exclude ingredients already at home.
- Scale recipes by household size.
- Estimate total meal-plan cost.
- Reuse prior meal plans.

### Meals Data Gaps

Likely model additions:

- MealPlan model.
- MealPlanSlot model with date, meal type, recipe ID, freeform meal, or matkasse meal.
- MatkasseBox model.
- MatkasseMeal model.
- Pantry / already-have flag for ingredients.
- Recipe ingredient should support optional product ID and substitution group.
- Recipe should track prep time, cook time, cuisine, difficulty, nutrition later if desired.
- Meal plans need generated shopping-list linkage.

### Meals Open Questions

- Should the default meal plan view be weekly, fortnightly, or monthly?
- Should matkasse meals have ingredients stored, or just block out planned meals?
- Should the app track the cost of matkasse separately from grocery-store shopping?
- Should "already have at home" be part of meal planning now, or later as a pantry feature?
- Should recipes support photos, or keep the first version text-only?
- Should AI-generated recipes be saved immediately after approval, or drafted first for editing?

### Meals Feature Bank

High-value features:

- Rename tab label to Meals.
- Week, fortnight, and month planning modes.
- Meal-type picker for breakfast, lunch, dinner, snacks, or custom slots.
- Week dashboard with planned meals, open slots, matkasse coverage, and estimated grocery cost.
- Matkasse boxes with provider, delivery week, meals, servings, box price, and notes.
- Individual matkasse meal entries that can be placed on the planner.
- Option to store matkasse ingredients when useful, but avoid adding included ingredients to normal shopping lists by default.
- Recipe browser inside Meals with Favorites, Recent, Cheap, Quick, Household, and Tags.
- Recipe detail with cost per serving, missing prices, best store, scale servings, and add-to-plan.
- Meal-plan generator that respects budget, preferences, dietary needs, leftovers, matkasse meals, and time.
- Build shopping list from meal plan with choice: one weekly list or lists per shopping trip.
- Exclude "already have" ingredients before list generation.
- Leftovers planning: cook once, eat twice.
- Batch cooking marker.
- Freeform planned meals that are not full recipes.
- "Eating out / takeaway" slot so the week plan stays honest.
- Nutrition or macro fields later, not in first build unless explicitly needed.
- Seasonal and sale-aware meal suggestions once price history is strong enough.
- Recipe import from pasted text or chat.
- AI recipe drafting with approval before save.
- Household preference checks before adding a meal.

Nice-to-have later:

- Recipe photos.
- Calendar integration.
- Cooking reminders.
- Pantry-aware substitutions.
- Meal rating after cooking.
- "Use up these ingredients" generator.
- Monthly food budget forecast from meal plan plus staple lists.

Ambitious later:

- Drag-and-drop meal planner with reusable meal blocks.
- Meal plan templates: cheap week, high-protein week, vegetarian week, busy week.
- AI meal-plan negotiation: user rejects meals, AI swaps alternatives while keeping budget.
- Planned leftovers with serving carryover into future meal slots.
- Freezer inventory and freezer-friendly recipe tagging.
- Pantry integration with expiry-aware "use soon" suggestions.
- Matkasse cost comparison against buying the same ingredients manually.
- Matkasse provider history with cost per serving and meal ratings.
- "Covered by matkasse" versus "needs grocery shopping" visual split.
- Recipe versioning when the user tweaks ingredients or method.
- Household meal voting or preference collection.
- Cooking effort score: active time, dishes, complexity, kid-friendly, weekday-safe.
- Nutrition targets later, such as protein, calories, fibre, or allergens.
- Dietary rule engine tied to AI memory: allergies, dislikes, preferred cuisines, avoided brands.
- Seasonal meal suggestions based on price and availability.
- Batch-cook planner that creates two meals and one leftover lunch from one cook.
- Shopping-list generator that groups ingredients by store and excludes matkasse-included items.
- "What can I cook tonight?" from current ingredients and known prices.
- Recipe import from pasted text, camera/OCR, or web share later.
- Meal history: last cooked, rating, cost, who liked it.
- Monthly meal budget planner combining groceries, matkasse, takeaway, and eating out.

## AI Chat Integration

Chat should be able to operate all three tabs through controlled proposed actions.

Expected AI capabilities:

- Create, update, complete, archive, and delete shopping lists.
- Add, edit, complete, remove, substitute, and reassign shopping-list items.
- Optimize shopping lists and explain store assignments.
- Create, update, delete, and compare price observations.
- Parse receipt lines and propose price observations.
- Create, update, delete, and merge products.
- Create, update, delete, and plan meals and recipes.
- Create and update meal plans.
- Add recipes and meal plans to shopping lists.
- Add and manage matkasse boxes and meals.
- Update settings related to optimization.
- Read and update shopping preferences and AI memory with permission.

AI should not silently mutate data. It should propose typed actions, and native code should validate permissions and arguments before execution.

## Build Strategy

### Shopping First

The first implementation target should be Shopping because it is the visible payoff for price logging.

Recommended first build slice:

1. Redesign Shopping list overview with Active / Completed / Archived.
2. Redesign list detail around store sections.
3. Surface optimization result clearly.
4. Add missing-price section.
5. Keep manual add item, barcode, compare, and optimize flows working.
6. Avoid large data-model migrations unless the UI cannot work without them.

### Prices Second

Recommended first build slice:

1. Redesign overview around Products / Stores / Needs Prices / Community.
2. Add product detail surface with cheapest store and price history.
3. Improve stale/community/confidence display.
4. Keep add price, barcode scan, and receipt scan flows working.

### Meals Third

Recommended first build slice:

1. Rename Recipes to Meals.
2. Add week planner UI.
3. Keep recipe browsing and details.
4. Add simple matkasse entries.
5. Generate shopping list from meal plan.
