import SwiftUI

// MARK: - Planner Range & View Mode

enum PlannerRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case fortnight = "Fortnight"
    case month = "Month"
    var id: String { rawValue }
}

private enum PlannerViewMode: String, CaseIterable, Identifiable {
    case list = "List"
    case calendar = "Calendar"
    var id: String { rawValue }
}

/// The Meals tab's planner — embedded directly inside `RecipesView`'s own
/// `List` (its `body` is `Section`s, not an owning `List`/`ScrollView`, so
/// it composes into the parent list rather than nesting one).
struct MealPlanView: View {
    @Environment(AppStore.self) private var store

    @State private var anchorDate = Date()
    @State private var range: PlannerRange = .week
    @State private var viewMode: PlannerViewMode = .list
    @State private var editingTarget: SlotEditTarget?
    @State private var dayForDetail: IdentifiableDate?

    private var periodStart: Date {
        switch range {
        case .day:
            return Calendar.mealPlanCalendar.startOfDay(for: anchorDate)
        case .week, .fortnight:
            return Calendar.mealPlanCalendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start ?? anchorDate
        case .month:
            return Calendar.mealPlanCalendar.dateInterval(of: .month, for: anchorDate)?.start ?? anchorDate
        }
    }

    private var days: [Date] {
        switch range {
        case .day:
            return [periodStart]
        case .week:
            return (0..<7).compactMap { Calendar.mealPlanCalendar.date(byAdding: .day, value: $0, to: periodStart) }
        case .fortnight:
            return (0..<14).compactMap { Calendar.mealPlanCalendar.date(byAdding: .day, value: $0, to: periodStart) }
        case .month:
            let dayCount = Calendar.mealPlanCalendar.range(of: .day, in: .month, for: periodStart)?.count ?? 30
            return (0..<dayCount).compactMap { Calendar.mealPlanCalendar.date(byAdding: .day, value: $0, to: periodStart) }
        }
    }

    /// Effectively `viewMode`, but calendar mode is only meaningful for a
    /// multi-day range — a single day's "grid" would just be one cell.
    private var usesCalendarLayout: Bool {
        viewMode == .calendar && range != .day
    }

    private func slot(for date: Date, mealType: MealType) -> MealPlanSlot? {
        visibleSlots.first { Calendar.mealPlanCalendar.isDate($0.date, inSameDayAs: date) && $0.mealType == mealType }
    }

    private var visibleSlots: [MealPlanSlot] {
        store.mealPlanSlots(on: days)
    }

    // MARK: Week summary

    private var totalSlotCount: Int { days.count * MealType.defaultTypes.count }
    private var plannedCount: Int { visibleSlots.count }
    private var openSlotCount: Int { max(totalSlotCount - plannedCount, 0) }

    private var matkasseCoveredCount: Int {
        visibleSlots.filter {
            if case .matkasseMeal = $0.content { return true }
            return false
        }.count
    }

    /// Estimated grocery cost for the range's planned *recipe* slots only —
    /// matkasse, freeform, and eating-out slots don't feed a grocery
    /// estimate since matkasse is billed separately and the other two
    /// aren't recipes to cost out.
    private var rangeCostEstimates: [RecipeCostEstimate] {
        visibleSlots.compactMap { slot in
            guard case .recipe(let recipeID, _) = slot.content,
                  let recipe = store.recipes.first(where: { $0.id == recipeID }) else { return nil }
            return RecipeCostEstimate(recipe: recipe, observations: store.priceObservations)
        }
    }

    private var estimatedGroceryCost: Decimal {
        rangeCostEstimates.reduce(Decimal.zero) { $0 + $1.total }
    }

    private var missingIngredientPriceCount: Int {
        rangeCostEstimates.reduce(0) { $0 + $1.missingIngredients.count }
    }

    var body: some View {
        Group {
            controlsSection
            weekNavigationSection
            weekSummarySection

            if usesCalendarLayout {
                calendarSection
            } else {
                ForEach(days, id: \.self) { day in
                    daySection(day)
                }
            }
        }
        .sheet(item: $editingTarget) { target in
            MealSlotEditorSheet(
                date: target.date,
                mealType: target.mealType,
                existingSlot: slot(for: target.date, mealType: target.mealType)
            )
            .environment(store)
        }
        .sheet(item: $dayForDetail) { wrapped in
            DayMealsSheet(
                date: wrapped.date,
                slotProvider: { slot(for: wrapped.date, mealType: $0) },
                onSelectMealType: { mealType in
                    dayForDetail = nil
                    editingTarget = SlotEditTarget(date: wrapped.date, mealType: mealType)
                }
            )
            .environment(store)
        }
    }

    // MARK: Controls

    private var controlsSection: some View {
        Section {
            Picker("Range", selection: $range) {
                ForEach(PlannerRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if range != .day {
                Picker("View", selection: $viewMode) {
                    ForEach(PlannerViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Navigation

    private var weekNavigationSection: some View {
        Section {
            HStack {
                Button { step(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 1) {
                    Text(periodRangeText)
                        .font(.subheadline.weight(.semibold))
                    if !isViewingCurrentPeriod {
                        Button(resetLabel) { anchorDate = Date() }
                            .font(.caption)
                    }
                }
                Spacer()
                Button { step(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .listRowBackground(Color.clear)
    }

    private func step(by direction: Int) {
        switch range {
        case .day:
            anchorDate = Calendar.mealPlanCalendar.date(byAdding: .day, value: direction, to: anchorDate) ?? anchorDate
        case .week:
            anchorDate = Calendar.mealPlanCalendar.date(byAdding: .day, value: direction * 7, to: anchorDate) ?? anchorDate
        case .fortnight:
            anchorDate = Calendar.mealPlanCalendar.date(byAdding: .day, value: direction * 14, to: anchorDate) ?? anchorDate
        case .month:
            anchorDate = Calendar.mealPlanCalendar.date(byAdding: .month, value: direction, to: anchorDate) ?? anchorDate
        }
    }

    private var isViewingCurrentPeriod: Bool {
        switch range {
        case .day:
            return Calendar.mealPlanCalendar.isDateInToday(anchorDate)
        case .week, .fortnight:
            return Calendar.mealPlanCalendar.isDate(anchorDate, equalTo: Date(), toGranularity: .weekOfYear)
        case .month:
            return Calendar.mealPlanCalendar.isDate(anchorDate, equalTo: Date(), toGranularity: .month)
        }
    }

    private var resetLabel: String {
        switch range {
        case .day: return "Today"
        case .week: return "This Week"
        case .fortnight: return "This Fortnight"
        case .month: return "This Month"
        }
    }

    private var periodRangeText: String {
        switch range {
        case .day:
            return periodStart.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        case .month:
            return periodStart.formatted(.dateTime.month(.wide).year())
        case .week, .fortnight:
            guard let end = days.last else { return "" }
            let start = periodStart.formatted(.dateTime.day().month(.abbreviated))
            let endText = end.formatted(.dateTime.day().month(.abbreviated))
            return "\(start) – \(endText)"
        }
    }

    // MARK: Summary

    private var weekSummarySection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    summaryTile(value: "\(plannedCount)", label: "planned", icon: "fork.knife.circle.fill", color: .blue)
                    if matkasseCoveredCount > 0 {
                        summaryTile(value: "\(matkasseCoveredCount)", label: "matkasse", icon: "shippingbox.fill", color: .purple)
                    }
                    if openSlotCount > 0 {
                        summaryTile(value: "\(openSlotCount)", label: "open", icon: "circle.dashed", color: .secondary)
                    }
                    if estimatedGroceryCost > 0 {
                        summaryTile(value: "kr \(formatDecimal(estimatedGroceryCost))", label: "grocery est.", icon: "creditcard.fill", color: .green)
                    }
                    if missingIngredientPriceCount > 0 {
                        summaryTile(value: "\(missingIngredientPriceCount)", label: "missing price", icon: "questionmark.circle.fill", color: .orange)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 12))
    }

    private func summaryTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 84, height: 76)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: List layout

    private func daySection(_ day: Date) -> some View {
        Section {
            ForEach(MealType.defaultTypes, id: \.self) { mealType in
                Button {
                    editingTarget = SlotEditTarget(date: day, mealType: mealType)
                } label: {
                    MealSlotRow(mealType: mealType, slot: slot(for: day, mealType: mealType))
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(dayHeaderText(day))
        }
    }

    private func dayHeaderText(_ day: Date) -> String {
        let isToday = Calendar.mealPlanCalendar.isDateInToday(day)
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return isToday ? "\(text) · Today" : text
    }

    // MARK: Calendar layout

    private var calendarSection: some View {
        Section {
            MealCalendarGrid(
                days: days,
                leadingBlankCount: range == .month ? leadingBlankCount : 0,
                hasContent: { date, mealType in slot(for: date, mealType: mealType) != nil },
                onSelectDay: { date in dayForDetail = IdentifiableDate(date: date) }
            )
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
    }

    /// Blank leading cells so a month grid's 1st lines up under its actual
    /// weekday column instead of always starting in the Monday slot.
    private var leadingBlankCount: Int {
        guard let first = days.first else { return 0 }
        // ISO calendar: Monday = 2 ... Sunday = 1 (wraps). Convert to a
        // 0-based Monday-first offset.
        let weekday = Calendar.mealPlanCalendar.component(.weekday, from: first)
        return (weekday + 5) % 7
    }

    private func formatDecimal(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}

// MARK: - Identifiable Date wrapper (for `.sheet(item:)` on a plain `Date?`)

private struct IdentifiableDate: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - Slot Edit Target

private struct SlotEditTarget: Identifiable {
    let date: Date
    let mealType: MealType
    var id: String { "\(date.timeIntervalSince1970)-\(mealType.displayName)" }
}

// MARK: - Meal Slot Row

private struct MealSlotRow: View {
    let mealType: MealType
    let slot: MealPlanSlot?

    var body: some View {
        HStack(spacing: 12) {
            Text(mealType.displayName)
                .font(.subheadline.weight(.medium))
                .frame(width: 76, alignment: .leading)
                .foregroundStyle(.primary)

            if let slot {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: contentIcon(slot.content))
                            .font(.caption)
                            .foregroundStyle(contentColor(slot.content))
                        Text(contentTitle(slot.content))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if slot.isLeftover {
                        Text("Leftovers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Tap to plan")
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private func contentTitle(_ content: MealSlotContent) -> String {
    switch content {
    case .recipe(_, let title): return title
    case .matkasseMeal(_, let title): return title
    case .freeform(let text): return text
    case .eatingOut(let note): return note?.isEmpty == false ? "Eating out — \(note!)" : "Eating out"
    }
}

private func contentIcon(_ content: MealSlotContent) -> String {
    switch content {
    case .recipe: return "fork.knife"
    case .matkasseMeal: return "shippingbox.fill"
    case .freeform: return "square.and.pencil"
    case .eatingOut: return "takeoutbag.and.cup.and.straw.fill"
    }
}

private func contentColor(_ content: MealSlotContent) -> Color {
    switch content {
    case .recipe: return .blue
    case .matkasseMeal: return .purple
    case .freeform: return .secondary
    case .eatingOut: return .orange
    }
}

// MARK: - Calendar Grid

private struct MealCalendarGrid: View {
    let days: [Date]
    let leadingBlankCount: Int
    let hasContent: (Date, MealType) -> Bool
    let onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingBlankCount, id: \.self) { _ in
                    Color.clear.frame(height: 46)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = Calendar.mealPlanCalendar.isDateInToday(day)
        return Button {
            onSelectDay(day)
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.mealPlanCalendar.component(.day, from: day))")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                HStack(spacing: 2) {
                    ForEach(MealType.defaultTypes, id: \.self) { mealType in
                        Circle()
                            .fill(hasContent(day, mealType) ? dotColor(mealType) : Color(.systemGray5))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                isToday ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    private func dotColor(_ mealType: MealType) -> Color {
        switch mealType {
        case .breakfast: return .orange
        case .lunch: return .green
        case .dinner: return .blue
        default: return .secondary
        }
    }
}

// MARK: - Day Meals Sheet (calendar day tap)

private struct DayMealsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let slotProvider: (MealType) -> MealPlanSlot?
    let onSelectMealType: (MealType) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(MealType.defaultTypes, id: \.self) { mealType in
                    Button {
                        onSelectMealType(mealType)
                    } label: {
                        MealSlotRow(mealType: mealType, slot: slotProvider(mealType))
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Slot Editor Sheet

private enum SlotEditorKind: String, CaseIterable, Identifiable {
    case recipe = "Recipe"
    case matkasse = "Matkasse"
    case freeform = "Freeform"
    case eatingOut = "Eating Out"

    var id: String { rawValue }
}

struct MealSlotEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let mealType: MealType
    let existingSlot: MealPlanSlot?

    @State private var kind: SlotEditorKind
    @State private var selectedRecipeID: UUID?
    @State private var selectedMatkasseMealID: UUID?
    @State private var freeformText: String
    @State private var eatingOutNote: String
    @State private var isLeftover: Bool

    init(date: Date, mealType: MealType, existingSlot: MealPlanSlot?) {
        self.date = date
        self.mealType = mealType
        self.existingSlot = existingSlot

        var initialKind: SlotEditorKind = .recipe
        var initialRecipeID: UUID?
        var initialMatkasseID: UUID?
        var initialFreeform = ""
        var initialEatingOutNote = ""

        if let content = existingSlot?.content {
            switch content {
            case .recipe(let id, _):
                initialKind = .recipe
                initialRecipeID = id
            case .matkasseMeal(let id, _):
                initialKind = .matkasse
                initialMatkasseID = id
            case .freeform(let text):
                initialKind = .freeform
                initialFreeform = text
            case .eatingOut(let note):
                initialKind = .eatingOut
                initialEatingOutNote = note ?? ""
            }
        }

        _kind = State(initialValue: initialKind)
        _selectedRecipeID = State(initialValue: initialRecipeID)
        _selectedMatkasseMealID = State(initialValue: initialMatkasseID)
        _freeformText = State(initialValue: initialFreeform)
        _eatingOutNote = State(initialValue: initialEatingOutNote)
        _isLeftover = State(initialValue: existingSlot?.isLeftover ?? false)
    }

    private var allMatkasseMeals: [(box: MatkasseBox, meal: MatkasseMeal)] {
        store.matkasseBoxes.flatMap { box in box.includedMeals.map { (box, $0) } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(SlotEditorKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch kind {
                case .recipe:
                    Section("Recipe") {
                        if store.recipes.isEmpty {
                            Text("No saved recipes yet. Add one from the Recipes list.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Recipe", selection: $selectedRecipeID) {
                                Text("Select a recipe").tag(Optional<UUID>.none)
                                ForEach(store.recipes) { recipe in
                                    Text(recipe.title).tag(Optional(recipe.id))
                                }
                            }
                        }
                    }
                case .matkasse:
                    Section("Matkasse Meal") {
                        if allMatkasseMeals.isEmpty {
                            Text("No matkasse boxes yet. Add one from the meal plan's matkasse section.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Meal", selection: $selectedMatkasseMealID) {
                                Text("Select a meal").tag(Optional<UUID>.none)
                                ForEach(allMatkasseMeals, id: \.meal.id) { entry in
                                    Text("\(entry.meal.title) (\(entry.box.provider))").tag(Optional(entry.meal.id))
                                }
                            }
                        }
                    }
                case .freeform:
                    Section("Meal") {
                        TextField("e.g. Leftover soup, sandwiches", text: $freeformText)
                            .autocorrectionDisabled()
                    }
                case .eatingOut:
                    Section("Eating Out") {
                        TextField("Optional note, e.g. restaurant name", text: $eatingOutNote)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Toggle("Leftovers", isOn: $isLeftover)
                } footer: {
                    Text("Marks this as reusing a previous meal's cooking rather than a new dish.")
                }

                if existingSlot != nil {
                    Section {
                        Button("Clear This Meal", role: .destructive) {
                            store.clearMealPlanSlot(date: date, mealType: mealType)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("\(mealType.displayName) · \(date.formatted(date: .abbreviated, time: .omitted))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isValid: Bool {
        switch kind {
        case .recipe: return selectedRecipeID != nil
        case .matkasse: return selectedMatkasseMealID != nil
        case .freeform: return !freeformText.trimmingCharacters(in: .whitespaces).isEmpty
        case .eatingOut: return true
        }
    }

    private func save() {
        let content: MealSlotContent
        switch kind {
        case .recipe:
            guard let id = selectedRecipeID, let recipe = store.recipes.first(where: { $0.id == id }) else { return }
            content = .recipe(recipeID: id, title: recipe.title)
        case .matkasse:
            guard let id = selectedMatkasseMealID, let entry = allMatkasseMeals.first(where: { $0.meal.id == id }) else { return }
            content = .matkasseMeal(matkasseMealID: id, title: entry.meal.title)
        case .freeform:
            let trimmed = freeformText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            content = .freeform(trimmed)
        case .eatingOut:
            let trimmed = eatingOutNote.trimmingCharacters(in: .whitespaces)
            content = .eatingOut(note: trimmed.isEmpty ? nil : trimmed)
        }

        store.setMealPlanSlot(date: date, mealType: mealType, content: content, isLeftover: isLeftover)
        dismiss()
    }
}
