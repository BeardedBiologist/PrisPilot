import SwiftUI

// MARK: - Segment

private enum ShoppingStatSegment: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case lists    = "Lists"
    case products = "Products"
    var id: String { rawValue }
}

// MARK: - Main View

struct ShoppingStatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var segment: ShoppingStatSegment = .overview

    // MARK: Computed data

    private var allLists: [ShoppingList] { store.shoppingLists }

    private var allItems: [ShoppingListItem] { allLists.flatMap { $0.items } }

    private var pendingItems: [ShoppingListItem] {
        (store.activeLists + store.plannedLists).flatMap { $0.items }.filter { !$0.isCompleted }
    }
    private var pricedPendingItems: [ShoppingListItem] {
        pendingItems.filter { $0.estimatedPrice != nil }
    }
    private var coverageFraction: Double {
        pendingItems.isEmpty ? 0 : Double(pricedPendingItems.count) / Double(pendingItems.count)
    }

    private var estimatedSpendNow: Decimal {
        pricedPendingItems.compactMap(\.estimatedPrice).reduce(0, +)
    }
    private var totalActualSpend: Decimal {
        allLists.compactMap(\.actualTotal).reduce(0, +)
    }
    private var totalSavings: Decimal {
        allLists.compactMap { $0.optimizationSnapshot?.savings }.reduce(0, +)
    }

    private var productFrequency: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in allItems {
            counts[item.productName.trimmingCharacters(in: .whitespaces), default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var optimizedListCount: Int {
        allLists.filter { $0.optimizationSnapshot != nil }.count
    }

    private var archivedCount: Int {
        store.archivedLists.count + store.completedLists.count
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Segmented picker — pinned at top like other tabs
                    Picker("", selection: $segment) {
                        ForEach(ShoppingStatSegment.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                    Group {
                        switch segment {
                        case .overview: overviewContent
                        case .lists:    listsContent
                        case .products: productsContent
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: segment)
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shopping Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewContent: some View {
        VStack(spacing: 14) {
            // Hero tiles
            HStack(spacing: 10) {
                heroTile("\(allLists.count)", label: "Total lists",   icon: "list.bullet",          color: .blue)
                heroTile("\(pendingItems.count)", label: "Pending items", icon: "cart",              color: .green)
                heroTile("kr \(fmt(estimatedSpendNow))", label: "Est. now", icon: "tag.fill",       color: .orange)
            }
            .padding(.horizontal, 16)

            // Coverage ring card
            card {
                HStack(spacing: 20) {
                    RingView(value: coverageFraction, color: coverageColor, size: 90) {
                        VStack(spacing: 1) {
                            Text("\(Int(coverageFraction * 100))%")
                                .font(.title3.weight(.bold))
                            Text("priced")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Price Coverage", systemImage: "chart.bar.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("\(pricedPendingItems.count) of \(pendingItems.count) pending items have price data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(coverageLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(coverageColor)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Spend summary
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Spend Summary", systemImage: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 0) {
                        spendColumn("kr \(fmt(estimatedSpendNow))", label: "Est. pending", color: .blue)
                        Divider().frame(height: 44)
                        spendColumn("kr \(fmt(totalActualSpend))", label: "Total paid", color: .green)
                        Divider().frame(height: 44)
                        spendColumn("kr \(fmt(totalSavings))", label: "Total saved", color: .orange)
                    }
                }
            }
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var listsContent: some View {
        VStack(spacing: 14) {
            // Status distribution
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Lists by Status", systemImage: "tray.2.fill")
                        .font(.subheadline.weight(.semibold))

                    let total = max(allLists.count, 1)
                    barRow("Active",   count: store.activeLists.count,  max: total, color: .green)
                    barRow("Planned",  count: store.plannedLists.count, max: total, color: .blue)
                    barRow("Archived", count: archivedCount,            max: total, color: Color(.systemGray2))
                }
            }

            // List size stats
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("List Sizes", systemImage: "ruler")
                        .font(.subheadline.weight(.semibold))

                    let sizes = allLists.map { $0.items.count }
                    let avg = allLists.isEmpty ? 0 : allItems.count / allLists.count
                    let maxSize = sizes.max() ?? 0
                    let minSize = sizes.min() ?? 0

                    HStack(spacing: 0) {
                        miniStat(value: "\(avg)",     label: "Avg items")
                        Divider().frame(height: 40)
                        miniStat(value: "\(maxSize)", label: "Largest")
                        Divider().frame(height: 40)
                        miniStat(value: "\(minSize)", label: "Smallest")
                        Divider().frame(height: 40)
                        miniStat(value: "\(allItems.count)", label: "Total items")
                    }
                }
            }

            // Optimization stats
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Optimization", systemImage: "wand.and.sparkles")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 0) {
                        miniStat(value: "\(optimizedListCount)", label: "Optimized")
                        Divider().frame(height: 40)
                        miniStat(value: "kr \(fmt(totalSavings))", label: "Total saved")
                        Divider().frame(height: 40)
                        let avg = optimizedListCount == 0 ? Decimal.zero : totalSavings / Decimal(optimizedListCount)
                        miniStat(value: "kr \(fmt(avg))", label: "Avg saving")
                    }

                    if allLists.count > 0 {
                        let optFraction = Double(optimizedListCount) / Double(allLists.count)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(Int(optFraction * 100))% of lists optimized")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            ProgressView(value: optFraction)
                                .tint(.blue)
                        }
                    }
                }
            }

            // Completion rate across all items ever
            if !allItems.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Item Completion", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))

                        let completed = allItems.filter { $0.isCompleted }
                        let fraction = allItems.isEmpty ? 0.0 : Double(completed.count) / Double(allItems.count)

                        HStack(spacing: 16) {
                            RingView(value: fraction, color: .green, size: 60) {
                                Text("\(Int(fraction * 100))%")
                                    .font(.callout.weight(.bold))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(completed.count) of \(allItems.count) items checked off")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(allItems.count - completed.count) still pending across all lists")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Products

    @ViewBuilder
    private var productsContent: some View {
        VStack(spacing: 14) {
            // Unique vs total
            card {
                let unique = Set(allItems.map { $0.productName.lowercased() }).count
                HStack(spacing: 0) {
                    miniStat(value: "\(unique)",         label: "Unique products")
                    Divider().frame(height: 40)
                    miniStat(value: "\(allItems.count)", label: "Total entries")
                    Divider().frame(height: 40)
                    let avg = unique == 0 ? 0 : allItems.count / unique
                    miniStat(value: "x\(avg)", label: "Avg repeats")
                }
            }

            // Most listed
            if !productFrequency.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Most Listed Items", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))

                        let top = Array(productFrequency.prefix(10))
                        let maxCount = top.first?.count ?? 1
                        ForEach(top, id: \.name) { item in
                            barRow(item.name, count: item.count, max: maxCount, color: GlassTheme.tint)
                        }
                    }
                }
            }

            // Price data coverage across unique products
            card {
                let uniqueNames = Set(allItems.map { $0.productName.lowercased() })
                let pricedNames = Set(
                    store.priceObservations.map { $0.productName.lowercased() }
                ).intersection(uniqueNames)
                let fraction = uniqueNames.isEmpty ? 0.0 : Double(pricedNames.count) / Double(uniqueNames.count)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Product Price Data", systemImage: "tag.fill")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 16) {
                        RingView(value: fraction, color: fraction > 0.6 ? .green : .orange, size: 60) {
                            Text("\(Int(fraction * 100))%")
                                .font(.callout.weight(.bold))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(pricedNames.count) of \(uniqueNames.count) products have at least one price observation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(uniqueNames.count - pricedNames.count) products never priced")
                                .font(.caption2)
                                .foregroundStyle(fraction < 0.5 ? .orange : .secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var coverageColor: Color {
        coverageFraction >= 0.8 ? .green : coverageFraction >= 0.5 ? .orange : .red
    }
    private var coverageLabel: String {
        coverageFraction >= 0.8 ? "Great coverage" : coverageFraction >= 0.5 ? "Decent coverage" : "Needs more price data"
    }

    private func heroTile(_ value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ body: () -> Content) -> some View {
        body()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
    }

    private func spendColumn(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func barRow(_ label: String, count: Int, max maxVal: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.75))
                        .frame(width: maxVal == 0 ? 0 : geo.size.width * CGFloat(count) / CGFloat(maxVal))
                }
            }
            .frame(height: 10)

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}

// MARK: - Ring View

struct RingView<Center: View>: View {
    let value: Double
    let color: Color
    let size: CGFloat
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.9).delay(0.1), value: value)
            center()
        }
        .frame(width: size, height: size)
    }
}
