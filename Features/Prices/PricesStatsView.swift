import SwiftUI

// MARK: - Segment

private enum PricesStatSegment: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case stores   = "Stores"
    case products = "Products"
    var id: String { rawValue }
}

// MARK: - Main View

struct PricesStatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var segment: PricesStatSegment = .overview

    // MARK: Computed data

    private var allObs: [PriceObservation] { store.priceObservations }
    private var personalObs: [PriceObservation] { allObs.filter { $0.source != .community } }
    private var communityObs: [PriceObservation] { allObs.filter { $0.source == .community } }
    private var freshObs: [PriceObservation] { allObs.filter { !$0.isStale } }
    private var staleObs: [PriceObservation] { allObs.filter { $0.isStale } }
    private var freshnessFraction: Double {
        allObs.isEmpty ? 0 : Double(freshObs.count) / Double(allObs.count)
    }
    private var uniqueProducts: Int { Set(allObs.map { $0.productName }).count }
    private var storeCount: Int { store.enabledBranches.count }

    private var obsByStore: [(store: String, count: Int)] {
        var counts: [String: Int] = [:]
        for obs in allObs {
            counts[obs.storeBranchName, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var obsByProduct: [(product: String, count: Int)] {
        var counts: [String: Int] = [:]
        for obs in allObs {
            counts[obs.productName, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var communityFraction: Double {
        allObs.isEmpty ? 0 : Double(communityObs.count) / Double(allObs.count)
    }

    private var avgObsPerProduct: Double {
        uniqueProducts == 0 ? 0 : Double(allObs.count) / Double(uniqueProducts)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Picker("", selection: $segment) {
                        ForEach(PricesStatSegment.allCases) { s in
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
                        case .stores:   storesContent
                        case .products: productsContent
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: segment)
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prices Stats")
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
            HStack(spacing: 10) {
                heroTile("\(allObs.count)", label: "Observations", icon: "tag.fill",        color: .blue)
                heroTile("\(uniqueProducts)", label: "Products",   icon: "shoppingbag.fill", color: .green)
                heroTile("\(storeCount)",     label: "Stores",     icon: "building.2.fill",  color: .purple)
            }
            .padding(.horizontal, 16)

            // Freshness ring
            card {
                HStack(spacing: 20) {
                    RingView(value: freshnessFraction, color: freshnessColor, size: 90) {
                        VStack(spacing: 1) {
                            Text("\(Int(freshnessFraction * 100))%")
                                .font(.title3.weight(.bold))
                            Text("fresh")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Data Freshness", systemImage: "clock.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("\(freshObs.count) fresh, \(staleObs.count) stale out of \(allObs.count) observations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(freshnessLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(freshnessColor)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Source split
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Price Sources", systemImage: "person.2.fill")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 0) {
                        sourceColumn(count: personalObs.count,  label: "Personal",  icon: "person.fill",   color: .blue)
                        Divider().frame(height: 44)
                        sourceColumn(count: communityObs.count, label: "Community", icon: "person.3.fill",  color: .purple)
                        Divider().frame(height: 44)
                        VStack(spacing: 4) {
                            Text(String(format: "%.1f", avgObsPerProduct))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                            Text("avg/product")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if allObs.count > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.blue.opacity(0.3))
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.purple.opacity(0.5))
                                        .frame(width: geo.size.width * communityFraction)
                                }
                            }
                            .frame(height: 10)

                            HStack {
                                Label("\(Int((1 - communityFraction) * 100))% personal", systemImage: "circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Label("\(Int(communityFraction * 100))% community", systemImage: "circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
            }

            // Quick stats
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Quick Stats", systemImage: "chart.bar.fill")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 0) {
                        miniStat(
                            value: staleObs.isEmpty ? "All fresh" : "\(staleObs.count)",
                            label: "Stale obs"
                        )
                        Divider().frame(height: 40)
                        let needsPrice = store.needsPriceEntries().count
                        miniStat(value: "\(needsPrice)", label: "Need price")
                        Divider().frame(height: 40)
                        if let last = allObs.map({ $0.observedDate }).max() {
                            miniStat(
                                value: last.formatted(.relative(presentation: .named)),
                                label: "Last entry"
                            )
                        } else {
                            miniStat(value: "—", label: "Last entry")
                        }
                    }
                }
            }
        }
    }

    // MARK: Stores

    @ViewBuilder
    private var storesContent: some View {
        VStack(spacing: 14) {
            if obsByStore.isEmpty {
                card {
                    ContentUnavailableView(
                        "No Price Data",
                        systemImage: "building.2",
                        description: Text("Add price observations to see store stats.")
                    )
                    .frame(height: 180)
                }
            } else {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Observations per Store", systemImage: "building.2.fill")
                            .font(.subheadline.weight(.semibold))

                        let maxCount = obsByStore.first?.count ?? 1
                        ForEach(obsByStore, id: \.store) { entry in
                            barRow(entry.store, count: entry.count, max: maxCount, color: .blue)
                        }
                    }
                }

                // Per-store freshness breakdown
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Freshness by Store", systemImage: "clock")
                            .font(.subheadline.weight(.semibold))

                        ForEach(obsByStore.prefix(8), id: \.store) { entry in
                            let storeObs = allObs.filter { $0.storeBranchName == entry.store }
                            let freshCount = storeObs.filter { !$0.isStale }.count
                            let fraction = storeObs.isEmpty ? 0.0 : Double(freshCount) / Double(storeObs.count)
                            let color: Color = fraction >= 0.8 ? .green : fraction >= 0.5 ? .orange : .red

                            HStack(spacing: 10) {
                                Text(entry.store)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: 130, alignment: .leading)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemFill))
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(color.opacity(0.75))
                                            .frame(width: geo.size.width * fraction)
                                    }
                                }
                                .frame(height: 10)

                                Text("\(Int(fraction * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color)
                                    .frame(width: 34, alignment: .trailing)
                            }
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
            card {
                HStack(spacing: 0) {
                    miniStat(value: "\(uniqueProducts)", label: "Unique")
                    Divider().frame(height: 40)
                    miniStat(value: String(format: "%.1f", avgObsPerProduct), label: "Avg obs")
                    Divider().frame(height: 40)
                    let wellTracked = obsByProduct.filter { $0.count >= 3 }.count
                    miniStat(value: "\(wellTracked)", label: "Well tracked")
                }
            }

            if !obsByProduct.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Most Observed Products", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))

                        let top = Array(obsByProduct.prefix(10))
                        let maxCount = top.first?.count ?? 1
                        ForEach(top, id: \.product) { entry in
                            barRow(entry.product, count: entry.count, max: maxCount, color: .blue)
                        }
                    }
                }
            }

            let staleProdNames = Set(staleObs.map { $0.productName })
            if !staleProdNames.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Products with Stale Data", systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)

                        Text("\(staleProdNames.count) product\(staleProdNames.count == 1 ? " has" : "s have") at least one stale observation")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let staleByProduct = Dictionary(grouping: staleObs, by: { $0.productName })
                            .map { ($0.key, $0.value.count) }
                            .sorted { $0.1 > $1.1 }
                            .prefix(8)
                        let maxStale = staleByProduct.first?.1 ?? 1

                        ForEach(Array(staleByProduct), id: \.0) { name, count in
                            barRow(name, count: count, max: maxStale, color: .orange)
                        }
                    }
                }
            }

            if communityObs.count > 0 && personalObs.count > 0 {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Community vs Personal", systemImage: "person.2.fill")
                            .font(.subheadline.weight(.semibold))

                        let topProducts = Array(obsByProduct.prefix(8))
                        ForEach(topProducts, id: \.product) { entry in
                            let prodObs = allObs.filter { $0.productName == entry.product }
                            let communityCount = prodObs.filter { $0.source == .community }.count
                            let fraction = entry.count == 0 ? 0.0 : Double(communityCount) / Double(entry.count)

                            HStack(spacing: 10) {
                                Text(entry.product)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: 130, alignment: .leading)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.blue.opacity(0.25))
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.purple.opacity(0.5))
                                            .frame(width: geo.size.width * fraction)
                                    }
                                }
                                .frame(height: 10)

                                Text("\(communityCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }

                        HStack(spacing: 14) {
                            Label("Personal", systemImage: "circle.fill").foregroundStyle(.blue)
                            Label("Community", systemImage: "circle.fill").foregroundStyle(.purple)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var freshnessColor: Color {
        freshnessFraction >= 0.8 ? .green : freshnessFraction >= 0.5 ? .orange : .red
    }
    private var freshnessLabel: String {
        freshnessFraction >= 0.8 ? "Data is fresh" : freshnessFraction >= 0.5 ? "Some stale data" : "Many observations stale"
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

    private func sourceColumn(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
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
}
