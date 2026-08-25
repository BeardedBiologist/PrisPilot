# PrisPilot — Build Status & Roadmap

Last updated: 2026-08-21 (removed brittle camera privacy-key runtime gate)

---

## Current Status

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — Foundation | ✅ Complete | All 16 acceptance criteria met |
| Phase 2 — Working AI | ✅ Complete | Gemini live, tool calling, shopping optimisation |
| Phase 3 — Accounts & Households | 🟡 Partial | Auth UI and local household scaffold built; cloud sync blocked on paid dev account/backend |
| Phase 4 — Smart Capture | ✅ Complete | Barcode scanning, receipt OCR, duplicate barcode handling, fuzzy matching, store inference, and consent-gated AI receipt parsing built |
| Phase 5 — Community Pricing | 🟡 Partial | Local opt-in, anonymous contribution queue, confidence/outlier scoring, and reporting UI built; backend submission blocked |
| Phase 6 — Advanced Optimisation | ✅ Complete | Store-splitting threshold, CoreLocation/MapKit distance estimates, travel costs, member prices, freshness weighting, waste risk, and recipe store totals built |

---

## Phase 1 — Foundation Prototype ✅

### What's built
- SwiftUI app shell with five-tab navigation (Chat · Shopping · Prices · Recipes · Profile)
- `AppStore` — `@Observable` singleton holding all in-memory state
- SwiftData persistence via snapshot model (`SwiftDataPersistence.swift`)
- All domain models: `Product`, `PriceObservation`, `ShoppingList`, `ShoppingListItem`, `Recipe`, `AIMemory`, `StoreBranch`, `SupermarketChain`, `AppSettings`
- Norway / NOK defaults, configurable region, currency, language
- `AIService` protocol with `MockAIService` (pattern-matched responses)
- Full proposed-action system: `ProposedAction`, `ProposedActionPayload`, `ProposedActionType`, `AppStore.execute()`
- AI permission model — per-area, per-operation, four modes
- Chat UI: multi-session, typing indicator, action proposal cards, approve/reject individual or all
- Activity tags after execution — tappable, open affected record in a sheet, and undo supported created records
- Onboarding: AI-guided flow and manual flow, resumable, skippable
- Store management: add/edit/delete chains and branches manually and via chat
- Manual entry sheets: products, prices, shopping lists + items, recipes
- Price comparison view: estimated cost per enabled store, cheapest item per store
- AI Memory list (inspectable from chat header and Settings)
- AI Permissions view (Settings)
- Local data controls: export current app snapshot as JSON and delete all local data with confirmation

### Key files
- `Store/AppStore.swift` — central state + `execute(_ action:)`
- `Models/AppModels.swift` — all domain value types
- `Models/ProposedAction.swift` — action types, payloads, activity tags
- `Services/MockAIService.swift` — mock AI with seeded responses
- `Features/Chat/` — ChatView, ChatViewModel, MessageBubbleView, ActionProposalView, ActivityTagView
- `Features/Onboarding/` — OnboardingView, OnboardingFlow
- `Features/Shopping/`, `Features/Prices/`, `Features/Recipes/`, `Features/Settings/`

---

## Phase 2 — Working AI ✅

### What's built
- `GeminiAIService` — full Gemini Developer API integration via REST (no SDK)
- Model: `gemini-2.5-flash` with fallback chain (`gemini-2.5-flash-lite`, etc.)
- Retry logic for overloaded/unavailable models (2 attempts per model, 700 ms delay)
- Structured function calling — 9 tools: `createPriceObservation`, `addShoppingListItem`, `createShoppingList`, `createMemory`, `createProduct`, `createStore`, `updateStore`, `deleteStore`, `setStoreEnabled`
- Context retrieval: relevant memories, available shopping lists, and enabled store branches sent per request
- Memory proposals — AI proposes `createMemory` as a separate action; user confirms
- Chat-driven CRUD for prices, lists, items, stores, products, settings
- `changeAppSetting` action maps to `AppSettings` fields
- Quota / 429 handling with user-friendly message
- Invalid API key detection (401/403)
- AI-guided onboarding with Gemini: structured JSON responses extract stores, memories, products, and settings from natural-language answers
- `APIKeys.swift` — gitignored file for local key; app falls back to `MockAIService` when key is empty
- Live/Mock indicator in chat header and Settings
- `OnboardingAIService` protocol for onboarding-specific AI turn handling

### Key files
- `Services/GeminiAIService.swift` — all Gemini integration
- `Models/AITypes.swift` — `AIService`, `OnboardingAIService`, `AIContext`, `AIResponse`, `MemoryProposal`
- `Models/GeminiAPITypes.swift` — Codable response types

### Known gaps (not blocking)
- Undo support is limited to AI-created records where `ActivityTag.affectedRecordIDs` is enough to reverse the action. True restore/rollback for edits and deletes still needs richer `UndoInfo` snapshots.
- Token-conscious context truncation — currently sends last 20 messages and all memories. Add summarisation in Phase 3+ when conversation lengths grow.

---

## Phase 3 — Accounts & Households 🟡

### What's built
- `AuthModels.swift` — `AuthUser`, `AuthState`
- `AuthStore.swift` — `@Observable` singleton; checks existing Apple credential on launch via `ASAuthorizationAppleIDProvider`, handles sign-in credential, sign-out, credential persistence in `UserDefaults`
- `AccountView.swift` — `SignInView` (with `SignInWithAppleButton`) and `AccountManagementView` (avatar, email, sign-out, delete account stub)
- `SettingsView` account row — switches on auth state: spinner → sign-in button → account detail link
- DEBUG mock account bypass (`AuthStore.signInWithMockAccount()`) for testing signed-in UI without the entitlement
- Local household domain models: `Household`, `HouseholdMember`, `HouseholdRole`, `Invitation`, `InvitationStatus`
- `AppStore.household` and `AppStore.invitations` persisted in `AppStoreSnapshot`
- Account UI can create/disband/leave a household, create local invite codes, show members, and accept a local invite code
- Shopping lists and recipes can be marked Personal or Household at creation and are grouped by scope in their tabs
- AI Memory is grouped by Personal vs Household scope
- Chat AI context includes personal memories plus household memories only when a household exists, and labels shopping lists by scope

### What's NOT built (blocked on paid Apple Developer account)

#### Step 1 — Unlock Sign in with Apple (requires paid account)
- [ ] Register App ID in Apple Developer Portal
- [ ] Add "Sign In with Apple" capability in Xcode → target → Signing & Capabilities
- [ ] This also enables testing `SignInWithAppleButton` on real devices
- [ ] Auth flow is fully coded and will work immediately once the entitlement is active

#### Step 2 — Choose and wire up a cloud backend
Three options, in order of recommendation:

**Option A — CloudKit (recommended)**
Best fit because it's Apple-native, free, integrates with the same Apple ID, and supports sharing between users natively. Requires paid developer account.
- [ ] Enable CloudKit capability in Xcode
- [ ] Create a CloudKit container in the Developer Portal
- [ ] Replace `AppStoreSnapshot` persistence with a `CloudKitRepository` that syncs `CKRecord`s
- [ ] Use `NSPersistentCloudKitContainer` (SwiftData has CloudKit sync built-in) or manual `CKDatabase` calls
- [ ] For shared household data, use `CKShare` to share a record zone between users
- [ ] Add `SyncMetadata` model (exists in brief section 21) for tracking sync state

**Option B — Supabase (no paid Apple account needed, but needs a server)**
- Free tier available, PostgreSQL-backed, good Swift SDK
- [ ] Create a Supabase project
- [ ] Design schema: `users`, `households`, `household_members`, `invitations`, `shopping_lists`, `list_items`, `price_observations`, `recipes`, `memories`
- [ ] Add `Supabase` Swift package
- [ ] Create `SupabaseRepository` conforming to repository protocols

**Option C — Firebase (widely used, free tier)**
- Similar to Supabase but uses Firestore (document database)
- [ ] Create a Firebase project, add GoogleService-Info.plist
- [ ] Add Firebase Swift SDK

#### Step 3 — Household model (build regardless of backend choice)
The domain models need to be extended:

- [x] Add `Household` model to `AppModels.swift`:
  ```swift
  struct Household: Codable, Identifiable {
      let id: UUID
      var name: String
      var ownerUserID: String
      var members: [HouseholdMember]
      var createdAt: Date
  }
  
  struct HouseholdMember: Codable, Identifiable {
      let id: UUID
      var userID: String
      var displayName: String?
      var role: HouseholdRole  // .owner, .member
      var joinedAt: Date
  }
  
  enum HouseholdRole: String, Codable {
      case owner, member
  }
  
  struct Invitation: Codable, Identifiable {
      let id: UUID
      var householdID: UUID
      var inviterUserID: String
      var inviteeEmail: String?
      var shareCode: String       // short code for accepting invites
      var status: InvitationStatus
      var expiresAt: Date
      var createdAt: Date
  }
  
  enum InvitationStatus: String, Codable {
      case pending, accepted, declined, expired
  }
  ```

- [x] Add `household: Household?` to `AppStore`
- [x] Add `DataScope` separation to shopping lists, recipes, memories — personal vs household records are displayed separately
- [x] Add `Household` section to `AccountManagementView`:
  - Create household (owner flow)
  - Invite members via share code or email
  - Show member list
  - Leave household (member)
  - Disband household (owner)
- [x] Add invitation acceptance flow (in-app code entry; deep links remain future work)

#### Step 4 — Separate personal and household memory (AI)
- [x] Add a `scope` filter to `AIContext` — send personal memories, and include household memories when a household exists
- [x] Update `MemoryListView` to segment personal vs household memories
- [x] Update `ChatViewModel.buildContext()` to pass household-scope memories when appropriate

#### Step 5 — Shared lists and recipes
- [x] `ShoppingList.scope` is already on the model (`.personal` / `.household`) — wired to the UI
- [x] Show household lists in `ShoppingView` with a "Household" section
- [ ] Real-time sync for household lists (CloudKit push notifications or Supabase Realtime)

---

## Phase 4 — Smart Capture ✅

**Testable without paid developer account — camera works via Xcode on real device.**

> **⚠️ Info.plist required before testing on device:**
> Add these keys to the app target's Info.plist (Target → Info → Custom iOS Target Properties):
> - `NSCameraUsageDescription` = `"PrisPilot needs camera access to scan barcodes and receipts."`
> - `NSPhotoLibraryUsageDescription` = `"PrisPilot needs photo library access to import receipt images."`
> The scanner views guard against unsupported camera/scanner states and request camera permission before scanning. Keep the privacy keys configured in the app target or iOS will terminate camera access.

### Barcode scanning ✅
- [x] `Features/Scanner/BarcodeScannerView.swift` — full `DataScannerViewController` wrapper (VisionKit, iOS 16+)
- [x] `BarcodeScannerMode` enum — `.priceEntry` and `.addToList(UUID)`
- [x] On scan: look up product by `barcode` field in `store.products`
- [x] If found: `BarcodeResultView` — add to list or record new price
- [x] If not found: "Unknown barcode" card with "Add manually" option
- [x] `barcode: String?` added to `Product` model (backward-compatible `Codable`)
- [x] Barcode scan button (`barcode.viewfinder`) in `PricesView` toolbar
- [x] Barcode scan button (`barcode.viewfinder`) in `ShoppingListDetailView` toolbar
- [x] Barcode saved to product when recording price via `AddPriceObservationSheet`
- [x] Duplicate barcode handling — shows a product chooser when one barcode matches multiple saved products
- [x] Barcode scanner availability guard for previews, unsupported devices, denied camera access, or unavailable scanner state
- [x] Barcode scanner requests camera permission before checking VisionKit scanner availability

### Receipt scanning ✅
- [x] `Features/Scanner/ReceiptScannerView.swift` — camera + photo library import
- [x] `CameraImagePicker` — `UIImagePickerController` wrapped in `UIViewControllerRepresentable`
- [x] `PhotosPicker` for importing from photo library
- [x] `ReceiptParser` — Vision OCR (`VNRecognizeTextRequest`, Norwegian + English) + regex price extraction
- [x] Norwegian price pattern: `\d{1,5}[,\.]\d{2}` at end of line
- [x] Noise filtering: skips lines starting with sum/total/mva/kvittering
- [x] Fuzzy product name matching in `ReceiptParser.parse()` using exact, substring, then word-overlap matching against known products
- [x] Infer likely Norwegian store chain from receipt header lines
- [x] `ReceiptImportView` branch picker with inferred branch pre-selection where possible
- [x] `ReceiptImportView` — review screen with per-line toggle, unrecognised lines shown separately
- [x] On confirm: creates `PriceObservation` records with `source: .receiptScan`
- [x] Receipt scan button (`doc.viewfinder`) in `PricesView` toolbar
- [x] AI receipt parsing via `ReceiptParsingAIService` and `GeminiAIService.parseReceiptLines(rawLines:knownProducts:)`
- [x] Consent prompt before sending OCR text to AI for improved matching
- [x] One AI parse attempt per receipt review to avoid repeated large requests
- [x] Receipt camera availability guard for previews, simulator, or unsupported devices

### Future enhancements
- [ ] Let users manually correct individual receipt line product matches before import
- [ ] Parse package quantity/unit from receipt lines when present
- [ ] Save full receipt records separately from imported price observations

---

## Phase 5 — Community Pricing 🟡

- [x] Opt-in community participation setting
- [x] Local anonymous contribution queue for new manual/chat/receipt price observations
- [ ] Anonymous submission of price observations to a shared backend (blocked until backend choice)
- [x] Confidence scoring: high (multiple recent matches), medium (two recent), low (outlier), unconfirmed (single unusual)
- [x] Outlier handling — reduce influence rather than delete; outliers remain visible but are excluded from recommendations
- [x] Show community prices in `PricesView` and `PriceComparisonView` with source/confidence/staleness labels
- [x] `CommunityContribution` model: contribution ID, anonymous contributor hash, branch ID, product ID, price, date, receipt image never included
- [x] Reporting: users can flag inaccurate community prices locally
- [x] Privacy: contribution model contains anonymous structured data only; no receipt image, account ID, or personal notes

---

## Phase 6 — Advanced Optimisation ✅

- [x] Manual distance-aware store recommendations via `StoreBranch.distanceFromHomeKm`
- [x] Automatic distance-aware store recommendations using CoreLocation current location + MapKit geocoding to estimate store distance
- [x] Travel cost estimates (configurable cost per km and fixed cost per store stop)
- [x] Minimum saving threshold to justify adding another store (`AppSettings.minimumAdditionalStoreSavings`)
- [x] Shopping optimisation settings screen for strategy, max stores, extra-store saving threshold, and travel costs
- [x] Loyalty and member pricing labels on price observations
- [x] Promotional prices with end dates for manual price entry
- [x] Price freshness and promotion expiry labels in `PricesView`
- [x] Price freshness weighting — reduces displayed confidence and comparison priority as observations age
- [x] Waste and bulk-buying risk model for recipe package-size leftovers
- [x] Basic recipe costing — rough total from cheapest recent matched price observations
- [x] Advanced recipe costing — compatible unit conversion for grams/kg, ml/l, pieces, and packs
- [x] Store-by-store recipe totals
- [x] Natural-language trip plan explanation: "Kiwi saves kr 43 vs Meny. Adding Rema 1000 saves kr 8 more, below your kr 20 threshold — excluded."

> **Info.plist required before testing automatic distance on device:**
> Add `NSLocationWhenInUseUsageDescription` = `"PrisPilot uses your location to estimate travel distance to stores."`

---

## Architecture Notes

### Repository protocol (not yet extracted)
`AppStore` currently holds all data directly. When Phase 3 cloud sync is added:
- Extract `ShoppingListRepository`, `PriceRepository`, `RecipeRepository`, `MemoryRepository` protocols
- Local implementation reads/writes `AppStore` arrays (current behaviour)
- Cloud implementation syncs to CloudKit / Supabase
- `AppStore` becomes a coordinator between local and cloud repositories

### AI context size (watch for Phase 3+)
`ChatViewModel.buildContext()` currently sends all active memories and all enabled stores. As memory and store counts grow, add:
- Relevance scoring (keyword match between user message and memory summary)
- Cap at ~10 memories per request
- Conversation summarisation for long sessions

### Security reminders
- `APIKeys.swift` is gitignored — never commit a real API key
- Sign in with Apple user IDs are stable per app but not shareable across apps — use them as opaque identifiers only
- Household membership changes always require confirmation (already enforced in permission model)
- Community prices must never contain personally identifiable information
- Local data export/delete controls are built in Settings → Data; backend account deletion still depends on the selected cloud backend

---

## Dev Account Activation Checklist

When you get the paid Apple Developer account, do these in order:

1. [ ] Register the App ID (`com.yourname.PrisPilot` or whatever bundle ID you choose)
2. [ ] Enable **Sign in with Apple** capability on the App ID
3. [ ] Enable **CloudKit** capability on the App ID (if using CloudKit for Phase 3)
4. [ ] In Xcode → target → Signing & Capabilities:
   - Add "Sign in with Apple"
   - Add "CloudKit" and create/select a container
5. [ ] Test Sign in with Apple on a real device — the `AuthStore` and `SignInView` code is already complete
6. [ ] Remove the DEBUG mock account button from `SignInView` before any public distribution
7. [ ] Set up the production AI backend proxy (section 22 of brief) before distributing the app publicly — the current architecture sends Gemini requests directly from the device using a compiled-in key, which is unsafe for distribution
