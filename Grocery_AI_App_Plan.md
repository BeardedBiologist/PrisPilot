# AI-First Grocery Price & Shopping Planner for iPhone

## Complete Product and Build Brief

This document is the source of truth for designing and building the application. It can be supplied directly to Claude in Xcode.

Before making a major architectural assumption that conflicts with this brief, explain the decision. Build incrementally, keep the project compiling, and use local or mock implementations when production services are not ready.

---

## 1. Product vision

Build a native iPhone application that helps individuals and households decide:

- What they need to buy
- Which specific supermarket location sells each item cheapest
- Whether visiting multiple supermarkets is worth the additional savings
- How much a shopping trip is expected to cost
- Whether the known prices are recent and trustworthy
- How recipes translate into shopping-list items
- Which products best fit the user's preferences, dietary requirements, habits, and budget

The main interface is an AI chatbot. During development and early testing, the chatbot will use the Gemini Developer API through a free-tier API key created in Google AI Studio.

The chatbot is not merely conversational. It has controlled CRUD access to the application's structured data through typed, validated app actions.

A user should eventually be able to operate the entire app through chat:

- Complete or resume onboarding
- Change settings
- Create, view, edit, and delete products
- Record, correct, and remove price observations
- Create, edit, delete, and complete shopping lists and items
- Create, edit, scale, and delete recipes
- Generate shopping lists from recipes
- Compare supermarkets and optimise shopping trips
- Create and manage a household
- Invite household members
- Manage AI permissions
- Save, update, inspect, and remove long-term AI memories

Traditional screens must also exist so users can inspect and manually manage everything without using AI.

---

## 2. Initial market and localisation

The initial market is Norway.

Initial defaults:

- Country: Norway
- Currency: NOK
- Norwegian supermarket chains and their specific physical branches
- Metric quantities such as grams, kilograms, millilitres, and litres
- Locale-aware currency, number, and date formatting

Country, currency, language, region, and measurement system must not be permanently hardcoded. Users can change them in Settings or through chat.

The architecture should support additional countries, currencies, languages, measurement systems, chains, and branches later.

---

## 3. Core product principles

### Chat first

Chat is the default home screen and primary interaction model.

### Structured data underneath

Important information must not exist only in free-form messages. Products, prices, stores, lists, recipes, settings, permissions, and memories must be structured records.

### Controlled AI actions

The AI must not alter the database invisibly. It proposes typed actions through an app-controlled action layer. Native code validates permissions and arguments before execution.

### Transparent and reversible

The app clearly shows what the AI changed. Actions should be inspectable and undoable where practical.

### Local-first and cloud-ready

Core features should work with local data where possible. Accounts, household sharing, community prices, and cross-device synchronisation will require a cloud backend. Use repository protocols so local implementations can later be replaced.

### Privacy by design

Personal memory, household data, receipts, and community information have distinct scopes and must never be mixed accidentally.

---

## 4. Main navigation

Use a native SwiftUI tab-based interface with five main areas:

1. **Chat**
2. **Shopping**
3. **Prices**
4. **Recipes**
5. **Profile / Settings**

The Chat tab opens by default.

AI Memory is not a main tab. It mostly operates behind the scenes, with an inspectable management area under Settings.

---

## 5. Chat experience

The chat supports natural language, action proposals, confirmations, system activity tags, explanations, and undo operations.

Example request:

> I paid 39.90 for 400 g of minced beef at Kiwi. Add two packs to my taco list.

The AI interprets this and proposes:

```text
Proposed changes

1. Add price observation
   Minced beef
   400 g
   kr 39.90
   Kiwi Majorstuen
   Observed today

2. Add shopping-list item
   Minced beef
   2 × 400 g
   Taco Night
```

The user can:

- Approve all actions
- Approve individual actions
- Edit an action before approval
- Reject actions
- Ask for an explanation

After execution, do not display the result as an ordinary assistant message. Show visually distinct activity tags or cards between messages:

```text
✓ Added price: Minced beef at Kiwi Majorstuen
✓ Added 2 × minced beef to Taco Night
```

Tapping an activity tag opens the affected record. Where practical, it also offers Undo.

Other expected requests include:

- “Create the cheapest shopping plan for tacos for four people.”
- “Move everything to one supermarket unless splitting the trip saves at least kr 100.”
- “What do you remember about my preferences?”
- “Forget that I dislike Q milk.”
- “Change my currency to euros.”
- “Add all missing ingredients from this recipe to the weekly list.”
- “Set up the app for Norway and only show Kiwi and Rema 1000.”

---

## 6. AI action and tool architecture

Do not give the language model arbitrary database or networking access.

Create a registry of typed app actions such as:

- `createProduct`
- `updateProduct`
- `deleteProduct`
- `createPriceObservation`
- `updatePriceObservation`
- `deletePriceObservation`
- `createShoppingList`
- `updateShoppingList`
- `deleteShoppingList`
- `addShoppingListItem`
- `updateShoppingListItem`
- `completeShoppingListItem`
- `removeShoppingListItem`
- `createRecipe`
- `updateRecipe`
- `deleteRecipe`
- `addRecipeToShoppingList`
- `createStore`
- `enableStore`
- `disableStore`
- `updateShoppingPreferences`
- `createMemory`
- `updateMemory`
- `deleteMemory`
- `createHousehold`
- `inviteHouseholdMember`
- `updateHouseholdMember`
- `changeAppSetting`

Each proposed action should contain:

- Unique ID
- Tool/action type
- Human-readable summary
- Structured arguments
- Target record and data scope
- Risk level
- Whether confirmation is required
- Validation result
- Execution status
- Resulting record IDs
- Undo information where available

All model-produced arguments must be validated in native code before execution.

---

## 7. AI permissions

Users control what the AI can view, create, edit, and delete.

Permission modes:

- Not allowed
- Always ask
- Automatically allow
- Automatically allow for this conversation

Permissions are configurable by operation and data area:

| Area | View | Create | Edit | Delete |
|---|---|---|---|---|
| Shopping lists | Configurable | Configurable | Configurable | Configurable |
| Products | Configurable | Configurable | Configurable | Configurable |
| Prices | Configurable | Configurable | Configurable | Configurable |
| Recipes | Configurable | Configurable | Configurable | Configurable |
| AI Memory | Configurable | Configurable | Configurable | Configurable |
| Household | Configurable | Configurable | Configurable | Configurable |
| Settings | Configurable | Configurable | Configurable | Configurable |

Recommended defaults:

- Viewing relevant app data: allowed
- Creating: ask first
- Editing: ask first
- Deleting: always ask
- Bulk actions: always ask
- Household membership changes: always ask
- Privacy changes: always ask
- Sensitive-memory changes: always ask

Never permit silent deletion, bulk destructive edits, household membership changes, or privacy changes.

---

## 8. Persistent AI brain

The chatbot must not start from scratch in every conversation.

Create a persistent, private memory system called **AI Memory** or **My Brain** in the UI. It represents what the app has learned about the user or household and grows over time.

This memory influences product selection, substitutions, recipes, list creation, and shopping optimisation.

Examples:

- Joshua prefers Tine milk.
- Q milk is acceptable if it saves at least kr 5.
- Avoid peanuts because of an allergy.
- Organic matters for eggs but not most other products.
- The household normally needs six dinner portions.
- Do not recommend more than two supermarkets.
- Pepsi Max is preferred over Coke Zero.
- Large packages are acceptable for non-perishable items.
- The household often already has rice.
- Friday tacos normally serve four people.

Do not implement every possible preference as a hardcoded toggle. Users express preferences naturally in conversation, and the AI translates them into structured memories.

Example:

> Add milk, but I don't like Q milk.

The AI proposes two separate operations:

```text
Shopping change
+ Add milk to Weekly Shop

Remember for later
+ Joshua prefers not to buy Q milk
```

After confirmation, show separate activity tags:

```text
✓ Added milk to Weekly Shop
🧠 Remembered: Avoid Q milk for Joshua
```

### Memory categories

#### Hard requirements

- Allergies
- Medical dietary restrictions
- Religious restrictions
- Ingredients or products that must never be substituted

#### Preferences

- Favourite brands
- Disliked brands
- Organic preferences
- Quality preferences
- Preferred package sizes
- Preferred variants

#### Habits

- Frequently purchased products
- Typical quantities
- Household serving sizes
- Usual shopping days
- Regular recipes

#### Decision patterns

- Savings versus convenience
- Maximum supermarket count
- Willingness to travel
- Brand loyalty
- Freshness priorities
- Bulk-buying tolerance

Hard requirements are constraints. Preferences influence rankings but are not absolute unless the user explicitly makes them absolute.

### Memory record

An AI memory should include:

- ID
- Natural-language summary
- Structured category and type
- Subject or product category
- Person or household it applies to
- Constraint strength
- Conditions and exceptions
- Personal, household, session, or temporary scope
- Source conversation/message
- Explicitly stated or inferred status
- Confidence
- Sensitivity classification
- Created date
- Last confirmed date
- Last used date
- Active/inactive state
- Superseded or conflicting memory reference

### Memory retrieval

Do not send the complete conversation history or memory database on every AI request. Retrieve only task-relevant memories.

```text
Request: Plan taco night

Relevant memory:
- Serve four people
- One household member avoids gluten
- Santa Maria seasoning is preferred
- Use no more than two supermarkets
```

### Memory controls

Support commands such as:

- “What do you remember about me?”
- “Why did you select this product?”
- “Forget that preference.”
- “I'm not vegetarian anymore.”
- “Don't learn from this conversation.”
- “Remember this only for this shopping trip.”
- “Forget everything related to my diet.”

Initial defaults:

- Suggest persistent memories and ask before saving.
- Ordinary memory autonomy can be enabled later.
- Sensitive memories always require explicit confirmation.
- Never infer an allergy solely from purchase behaviour.
- Repeated behaviour may generate a suggested preference, but not a silent hard constraint.
- Support session-only or trip-only memories.
- Let users disable learning for an entire conversation.

AI Memory is not a main navigation tab, but users can inspect and edit it through chat and Settings.

### Personal and household memory

Keep separate scopes:

```text
Personal memory
├── Individual dietary requirements
├── Individual likes and dislikes
└── Individual shopping habits

Household memory
├── Shared restrictions
├── Household staples
├── Typical household quantities
└── Shared shopping preferences
```

Every household member has a personal brain, and the household has a shared brain. A personal preference must not automatically become a household rule.

Community services must never access personal or household memories.

---

## 9. Onboarding

On first launch, offer:

- **Set up with AI**
- **Set up manually**
- **Skip for now**

Onboarding can be minimised, resumed later, or restarted from Settings. If incomplete, display an unobtrusive, dismissible setup-progress card.

Onboarding configures:

- Country
- Region/location
- Currency
- Language
- Measurement system
- Nearby or preferred supermarkets
- Enabled chains and specific branches
- Individual or household usage
- Community-pricing participation
- The user's definition of “cheapest”
- Maximum supermarket count
- Minimum savings needed to justify another store
- AI access and confirmation permissions
- Dietary requirements and allergies
- Favourite or disliked products and brands
- Frequently purchased products
- Typical household size and meal portions

The chatbot can complete and change all onboarding choices.

The catalogue begins empty. During onboarding, the AI may ask the user to describe products they buy regularly, then propose structured products and clarify only meaningful ambiguities.

---

## 10. Supermarkets and locations

Prices belong primarily to a specific physical branch because branches of the same chain may charge different prices.

```text
Country
└── Supermarket chain
    └── Specific branch
        ├── Name
        ├── Address and coordinates
        ├── Enabled status
        ├── Personal prices
        ├── Household prices
        └── Community prices
```

Users can enable or disable chains and individual branches to declutter shopping results. Both Settings and chat can change these choices.

When branch-specific information is unavailable, use clearly labelled fallbacks:

1. Selected branch observation
2. Nearby branch from the same chain
3. Regional chain estimate
4. National chain estimate
5. Unknown price

Never present a chain or regional estimate as a confirmed branch price.

---

## 11. Price observations

A price observation contains:

- Product or product variant
- Specific store branch
- Price and currency
- Package quantity and unit
- Normalised unit price
- Observation date
- Promotion status
- Promotion end date if known
- Membership requirement
- Source
- Personal, household, or community scope
- Contributor anonymity state
- Confidence
- Optional receipt reference
- Optional barcode
- Created and updated timestamps

Sources include:

- Manual entry
- Chat entry
- Personal observation
- Household observation
- Receipt scan
- Barcode scan
- Community submission
- Verified retailer source
- Promotional offer

Retain price history instead of overwriting older observations.

---

## 12. Community pricing

Community pricing is opt-in. Public records contain useful price data without publicly identifiable user information.

Initial rules:

- Accept submissions at the user's word.
- Do not initially require receipt evidence.
- Do not manually review every submission.
- Allow inaccurate prices to be reported.
- Keep contributor identities private from other users.
- Use automatic confidence and outlier handling.

Confidence examples:

- High: several recent matching observations
- Medium: one recent observation or several older observations
- Low: old or conflicting observations
- Unconfirmed: one unusual observation

Outliers do not have to be deleted. Their influence can be reduced and their uncertainty displayed.

Support both:

- Latest observed price
- Likely price range

Users can simplify or hide the range display in Settings.

Never present stale community data as a guaranteed current price. Use labels such as “last seen,” “estimated,” “likely range,” and “confidence.”

Receipt images are never published to the community. If sharing is enabled, only anonymous structured price information is contributed.

---

## 13. Product catalogue

The product catalogue starts empty and grows organically through:

- Chat
- Manual entry
- Shopping lists
- Recipes
- Receipt scans
- Barcode scans
- Community observations

Distinguish generic products from purchasable variants:

```text
Generic product: Milk
├── Tine Lettmelk 1%, 1 L
├── Tine Helmelk, 1 L
└── Q Lettmelk, 1 L
```

Support:

- Generic items
- Exact products
- Brands and variants
- Package sizes and units
- Barcodes
- Categories
- Ingredients and allergens
- User-defined names and aliases
- Duplicate detection and merging

When a user asks for a broad item such as “milk,” the AI uses relevant memory and context. It asks a clarifying question only when ambiguity materially changes the result.

Substitution behaviour should primarily emerge from AI Memory rather than requiring every possible preference to be hardcoded.

---

## 14. Shopping lists

Support multiple simultaneous lists, including:

- Weekly Shop
- Taco Night
- Party
- Cabin
- Christmas Dinner

A shopping list contains:

- Name
- Owner
- Personal or household scope
- Created date
- Planned shopping date
- Status
- Items
- Optimisation overrides
- Estimated total
- Actual total

A list item contains:

- Generic or exact product
- Original natural-language request
- Requested and normalised quantity
- Preferred variant if applicable
- Acceptable alternatives derived from relevant memory
- Recipe source if applicable
- Assigned supermarket
- Estimated price
- Actual price
- Completion status
- Completed by
- Notes

Support exact and conversational quantities:

- 800 g chicken
- Two packs
- Enough chicken for four people
- One week of milk
- Ingredients for taco night

The AI turns informal quantities into proposals and explains meaningful assumptions.

Household lists synchronise live and may show who added or completed an item.

When an item is checked off, optionally ask whether the expected price was correct. Allow the user to confirm or enter the actual price so the price database improves naturally. This prompt must not be mandatory.

---

## 15. Defining “cheapest”

The meaning of “cheapest” is configurable during onboarding, through Settings, or through chat.

Presets:

### Absolute cheapest

Split items across any number of enabled supermarkets to minimise item cost.

### Best practical trip

Balance prices against store count, distance, travel expense, and inconvenience.

### One-store shop

Find the lowest estimated total at one supermarket.

### Preferred stores only

Ignore disabled supermarkets.

### Custom

Use the user's own preferences and relevant AI Memory.

Potential optimisation factors:

- Maximum supermarket count
- Minimum saving required before adding another store
- Distance and travel time
- Estimated travel cost
- Preferred and avoided stores
- Loyalty discounts
- Membership requirements
- Offers versus regular prices
- Brand preferences
- Acceptable substitutions
- Package size and bulk-buying tolerance
- Product freshness
- Price freshness and confidence
- Waste risk

The optimiser must explain its recommendation.

Example:

> Kiwi is estimated to cost kr 43 less than a one-store shop at Meny. Adding Rema 1000 would save another kr 8, so it was excluded because your saved minimum additional saving is kr 20.

If a saved preference materially increases the price, the AI should mention the cheaper alternative and explain why it was not selected.

---

## 16. Recipes

Recipes support:

- Title and description
- Serving count
- Ingredients, quantities, and units
- Preparation steps
- Tags
- Dietary information
- Personal or household scope
- Source and notes
- Favourite status

The AI can:

- Create or edit recipes from conversation
- Scale serving counts
- Suggest ingredient substitutions
- Check recipes against hard dietary requirements
- Estimate recipe cost
- Compare recipe cost across supermarkets
- Add missing ingredients to a shopping list
- Exclude ingredients believed to be in stock
- Ask for confirmation when pantry information may be stale

Recipe substitutions must respect hard requirements and relevant AI Memory.

---

## 17. Receipt scanning

Receipt scanning is required for the first public release, though it can follow the earliest prototype.

Flow:

1. Photograph or import a receipt.
2. Extract branch, date, receipt lines, quantities, and prices.
3. Match receipt lines to known products.
4. Propose products for unknown lines.
5. Highlight ambiguous matches.
6. Let the user correct results.
7. Present a complete import proposal.
8. Save only after approval.
9. Add personal or household price observations.
10. If community sharing is enabled, contribute anonymous structured observations.

Retain receipt images privately only with user consent. Provide clear deletion and retention controls.

---

## 18. Barcode scanning

Barcode scanning is required for the first public release.

Scanning a barcode can:

- Find an existing product
- Propose a new product if unknown
- Show relevant known prices
- Record a newly observed price
- Add the product to a list
- Mark the product as a favourite
- Detect possible duplicates

Do not assume barcodes perfectly identify every package change or store-specific variant.

---

## 19. Accounts and households

Households require user accounts and invitations.

Support:

- Account creation and sign-in
- Household creation
- Member invitations
- Invitation acceptance or rejection
- Member roles
- Leaving a household
- Removing members with confirmation
- Shared lists
- Shared recipes
- Shared price observations
- Shared household memory
- Real-time synchronisation

Keep personal and household records clearly separated. Household membership and privacy changes always require explicit confirmation.

---

## 20. Settings

Settings include:

- Account
- Household
- Country and region
- Currency and language
- Measurement system
- Enabled supermarket chains
- Enabled specific branches
- Location radius
- Definition of cheapest
- Maximum store count
- Minimum additional-store saving
- Community-price participation
- Community price display mode
- Price freshness preferences
- Notifications
- Receipt retention
- AI provider and developer configuration
- AI permissions
- AI Memory
- Data export
- Data deletion
- Privacy controls
- Restart or resume onboarding

Every setting should be manageable through chat where safe.

---

## 21. Suggested domain model

Create models or equivalent entities for:

- `User`
- `UserProfile`
- `Household`
- `HouseholdMember`
- `Invitation`
- `Country`
- `Currency`
- `SupermarketChain`
- `StoreBranch`
- `Product`
- `ProductVariant`
- `ProductAlias`
- `Barcode`
- `PriceObservation`
- `Receipt`
- `ReceiptLine`
- `ShoppingList`
- `ShoppingListItem`
- `Recipe`
- `RecipeIngredient`
- `AIMemory`
- `Conversation`
- `ChatMessage`
- `ProposedAction`
- `ExecutedAction`
- `AIPermission`
- `ShoppingOptimisationProfile`
- `CommunityContribution`
- `Report`
- `SyncMetadata`

Use stable IDs and timestamps. Cloud-backed records should be syncable without replacing their local IDs.

---

## 22. Google AI Studio free-tier integration

Use the Gemini Developer API with an API key created through Google AI Studio. Remain on Google's Free Tier during development and early testing. Do not enable paid billing without an explicit later decision.

Google AI Studio is the project, API-key, prompt-testing, quota, and model-management interface. The iPhone app itself communicates with the Gemini Developer API.

### Development requirements

- Abstract the AI provider behind an `AIService` protocol.
- Keep the exact Gemini model configurable.
- Initially select a supported free-tier Flash or Flash-Lite model that provides structured output and function calling.
- Do not hardcode the API key in Swift source.
- Never commit an API key to Git.
- For local development, load the key from an ignored `.xcconfig`, an Xcode environment variable, or a Keychain-backed developer setting.
- Validate every AI-generated tool call in native code.
- Execute CRUD through the native action layer, never directly through the language model.
- Send only task-relevant records and AI memories.
- Do not repeatedly send the complete database or conversation history.
- Add token-conscious context retrieval and conversation summarisation.
- Rate-limit and debounce requests where appropriate.
- Cache safe, reusable interpretations where practical.
- Handle quota and service errors without breaking the app.
- Keep manual CRUD available while AI is offline or quota-limited.
- Retain `MockAIService` for previews, UI development, tests, and development without a key.

Suggested service boundary:

```swift
protocol AIService {
    func send(
        messages: [AIMessage],
        context: AIContext,
        availableTools: [AIToolDefinition]
    ) async throws -> AIResponse
}
```

Tool validation, permission evaluation, confirmation, and execution happen outside `AIService`.

### Free-tier quota behaviour

Free-tier limits vary by model and may change. They may include requests per minute, input tokens per minute, and requests per day. Limits apply per Google project, not independently per API key.

- Treat HTTP `429` / `RESOURCE_EXHAUSTED` as expected free-tier behaviour.
- Show a friendly explanation that the free AI allowance is temporarily exhausted.
- Preserve the user's unsent or failed message.
- Allow retrying later.
- Do not silently switch to paid use or another provider.
- Provide optional quota diagnostics in debug builds.

### Free-tier privacy

Free-tier AI requests are subject to Google's free-tier data terms. The app may handle dietary information, household details, memories, and receipts, so minimise what is sent.

- Explain the experimental AI integration during testing.
- Keep the main structured database local whenever possible.
- Send only relevant memories.
- Do not send household member names unless required.
- Avoid sending complete receipt images when extracted or redacted data is sufficient.
- Require approval before sending a receipt for AI processing.
- Never expose community contributor identities.
- Let users disable AI without disabling manual features.
- Avoid real sensitive health or allergy data during early development testing.

### Production boundary

The development API key must not be embedded in a publicly distributed iPhone app. Keys compiled into mobile applications can be extracted.

Development architecture:

```text
iPhone app → Gemini Developer API
             using a local free-tier AI Studio key
```

Production architecture:

```text
iPhone app → Secure application backend → Gemini Developer API
```

Before public release, use a secure backend proxy that:

- Stores provider credentials server-side
- Authenticates app users
- Enforces per-user limits
- Prevents abuse
- Records privacy-conscious usage metrics
- Supports cost controls and service-level fallbacks

Do not build the production AI backend during the initial local prototype, but do not couple the UI or domain layer to direct Gemini networking.

Keep the provider abstraction open for:

- A production Gemini backend
- Bring-your-own-key mode
- Another hosted provider
- An on-device model
- A mock or offline provider

---

## 23. Recommended iOS architecture

Use:

- Swift
- SwiftUI
- Modern Swift concurrency
- Protocol-based dependency injection
- Feature-oriented organisation
- Repository abstractions
- Local persistence suitable for structured offline data
- Testable domain services
- Native accessibility and Dynamic Type
- Localised strings from the beginning

Suggested structure:

```text
App
├── Core
│   ├── Models
│   ├── Persistence
│   ├── Networking
│   ├── AI
│   ├── Permissions
│   ├── Localisation
│   └── Utilities
├── Features
│   ├── Onboarding
│   ├── Chat
│   ├── Shopping
│   ├── Prices
│   ├── Products
│   ├── Recipes
│   ├── Scanner
│   ├── Household
│   ├── Memory
│   └── Settings
└── DesignSystem
```

Do not create one massive global view model. Keep UI state, domain services, action execution, and persistence separate.

---

## 24. Security and privacy rules

- Never expose personal information through community prices.
- Never publish receipt images.
- Sensitive memories require confirmation.
- Keep allergies distinct from ordinary preferences.
- Keep personal and household memories separate.
- Give users access to and control over saved memories.
- Allow users to export and delete their data.
- Do not log API keys or sensitive prompts.
- Store secrets in Keychain or on a secure backend.
- Require confirmation for destructive and privacy-related actions.
- Keep an audit trail of AI-executed mutations.
- Do not allow prompt content to bypass native permission checks.

---

## 25. Empty, loading, offline, and error states

Design explicitly for:

- Empty product catalogue
- No known prices
- No enabled branches
- Stale prices
- AI unavailable
- Free-tier quota exhausted
- Offline mode
- Account or sync failure
- Expired household invitation
- Receipt extraction failure
- Unknown barcode
- Invalid AI tool arguments
- Conflicting memories
- Missing community estimates

Users must still be able to view and manually manage local data when AI is unavailable.

---

## 26. Development phases

### Phase 1: Foundation prototype

- SwiftUI app shell
- Five-tab navigation
- Local models and persistence
- Norway and NOK defaults
- Onboarding shell
- Chain and branch selection
- Manual products and prices
- Multiple shopping lists
- Manual recipes
- Chat UI
- Mock AI service
- Proposed-action cards
- Confirmation and execution flow
- Activity tags
- Basic AI Memory
- AI permission model

### Phase 2: Working AI

- Google AI Studio free-tier API key configuration
- Gemini Developer API integration
- Structured tool calling
- Relevant-context retrieval
- Memory proposals
- Chat-driven CRUD
- Chat-driven settings
- Explanations and undo
- Basic shopping optimisation

### Phase 3: Accounts and households

- Authentication
- Cloud repository and sync
- Household creation
- Invitations
- Shared lists and recipes
- Shared price observations
- Personal and household memory separation

### Phase 4: Smart capture

- Barcode scanning
- Receipt photography/import
- Receipt extraction
- Product matching
- Duplicate resolution
- Price-import confirmation

### Phase 5: Community pricing

- Anonymous contributions
- Branch-specific community prices
- Confidence scoring
- Outlier handling
- Latest price and likely range
- Reporting and privacy controls

### Phase 6: Advanced optimisation

- Distance-aware recommendations
- Travel-cost estimates
- Additional-store thresholds
- Loyalty and member pricing
- Promotional prices
- Price-freshness weighting
- Waste and bulk-buying logic
- Advanced recipe costing

---

## 27. Current default decisions

Unless changed later:

- Use multiple simultaneous shopping lists.
- Sync household lists live.
- Show who added or completed household items.
- Support informal and exact quantities.
- Optionally ask for the actual price when completing an item.
- Recommend materially cheaper substitutes.
- Explain when memory caused a more expensive selection.
- Ask before saving persistent memories.
- Support temporary conversation or shopping-trip memory.
- Support “don't learn from this conversation.”
- Give each member a personal brain and the household a shared brain.
- Always confirm sensitive memories.
- Let repeated behaviour suggest memories, not create automatic hard rules.
- Show latest community price and likely range by default.
- Use specific branches as the primary price location.
- Use clearly labelled chain/regional fallbacks where necessary.
- Accept unverified community submissions initially.
- Start with an empty product catalogue.
- Require accounts and invitations for households.
- Include receipt and barcode scanning in the first public release.
- Use Google AI Studio's free tier during development.
- Never enable paid AI usage silently.

---

## 28. Initial acceptance criteria

The first functional prototype succeeds when a user can:

1. Launch the app and see Chat as the default tab.
2. Complete, minimise, resume, or skip onboarding.
3. Select Norway, NOK, and enabled supermarket branches.
4. Create products, prices, lists, and recipes manually.
5. Ask the chatbot to propose creating those records.
6. Review, edit, approve, or reject proposed actions.
7. See visually distinct activity tags after execution.
8. Tap an activity tag to inspect the affected record.
9. Save an approved preference into AI Memory.
10. Ask the AI what it remembers.
11. Remove or update a saved memory.
12. Configure AI permissions.
13. Build a basic cheapest-store plan using known local prices.
14. Continue using all manual features when AI is unavailable.
15. Use a mock AI when no API key is configured.
16. Receive a friendly response when the free-tier quota is exhausted.

---

## 29. First instruction to Claude in Xcode

Start with Phase 1.

First inspect the existing Xcode project and report what already exists. Then propose a concise implementation sequence that respects the current project structure.

Build the application shell, domain models, repository protocols, local persistence, mock AI service, Chat UI, typed proposed-action system, permission evaluation, and confirmation flow.

Keep the project compiling after every meaningful step. Add SwiftUI previews and tests for important domain behaviour. Do not attempt production accounts, production community infrastructure, a production AI backend, or receipt OCR until the local foundation and AI action boundary are reliable.

Do not place a Google AI Studio API key in source control. Begin with `MockAIService`; add the live free-tier integration only after the action system and manual data flows are stable.
