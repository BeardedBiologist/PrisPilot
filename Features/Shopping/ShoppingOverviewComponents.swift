import SwiftUI

// MARK: - Overview Segment

enum ShoppingListSegment: String, CaseIterable, Identifiable {
    case active = "Active"
    case planned = "Planned"
    case completed = "Completed"
    case archived = "Archived"

    var id: String { rawValue }

    var emptyTitle: String {
        switch self {
        case .active: return "No Active Lists"
        case .planned: return "No Planned Lists"
        case .completed: return "No Completed Lists"
        case .archived: return "No Archived Lists"
        }
    }

    var emptyDescription: String {
        switch self {
        case .active: return "Create a list with the + button, or ask the AI in Chat."
        case .planned: return "Give a new list a planned date to see it here."
        case .completed: return "Lists you mark complete show up here."
        case .archived: return "Lists you archive show up here."
        }
    }

    var emptySystemImage: String {
        switch self {
        case .active: return "cart"
        case .planned: return "calendar"
        case .completed: return "checkmark.circle"
        case .archived: return "archivebox"
        }
    }
}

// MARK: - Header Summary Band

struct ShoppingSummaryHeader: View {
    let activeCount: Int
    let nextPlannedDate: Date?
    let estimatedSpend: Decimal
    let missingPriceCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statTile(value: "\(activeCount)", label: activeCount == 1 ? "active list" : "active lists", icon: "cart.fill", color: .blue)

                if let nextPlannedDate {
                    statTile(
                        value: nextPlannedDate.formatted(.relative(presentation: .named)),
                        label: "next shop",
                        icon: "calendar",
                        color: .purple
                    )
                }

                if estimatedSpend > 0 {
                    statTile(
                        value: "kr \(NSDecimalNumber(decimal: estimatedSpend).stringValue)",
                        label: "estimated spend",
                        icon: "creditcard.fill",
                        color: .green
                    )
                }

                if missingPriceCount > 0 {
                    statTile(value: "\(missingPriceCount)", label: "missing price", icon: "questionmark.circle.fill", color: .orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 88, height: 76)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Primary Actions Row

struct ShoppingPrimaryActionsRow: View {
    let showOptimizeAll: Bool
    let isOptimizingAll: Bool
    let onNewList: () -> Void
    let onOptimizeAll: () -> Void
    let onAskAI: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(title: "New List", systemImage: "plus.circle.fill", action: onNewList)

            if showOptimizeAll {
                actionButton(
                    title: "Optimize All",
                    systemImage: "wand.and.sparkles",
                    isLoading: isOptimizingAll,
                    action: onOptimizeAll
                )
            }

            actionButton(title: "Ask AI", systemImage: "bubble.left.and.bubble.right.fill", action: onAskAI)
        }
    }

    private func actionButton(title: String, systemImage: String, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .frame(height: 20)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(height: 20)
                }
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .disabled(isLoading)
    }
}
