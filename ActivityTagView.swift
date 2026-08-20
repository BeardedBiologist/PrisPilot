import SwiftUI

struct ActivityTagsView: View {
    let tags: [ActivityTag]

    var body: some View {
        if tags.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Color(.systemGray3))
                Text("Actions rejected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tags) { tag in
                    ActivityTagRow(tag: tag)
                }
            }
        }
    }
}

struct ActivityTagRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let tag: ActivityTag

    private var isMemory: Bool { tag.actionType.isMemoryAction }
    private var color: Color { isMemory ? .purple : .green }
    private var icon: String { isMemory ? "brain.head.profile" : "checkmark.circle.fill" }
    private var backgroundOpacity: Double { colorScheme == .dark ? 0.28 : 0.12 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(tag.summary)
                .font(.subheadline)
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(colorScheme == .dark ? 0.32 : 0.12), lineWidth: 1)
        }
    }
}
