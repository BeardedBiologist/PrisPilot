import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    var onApproveAll: () -> Void
    var onApprove: (UUID) -> Void
    var onReject: (UUID) -> Void
    var onRejectAll: () -> Void

    var body: some View {
        switch message.content {
        case .text(let text):
            TextBubble(text: text, isUser: message.role == .user)
        case .proposedActions(let intro, let actions, let memoryProposals):
            AssistantMessageContainer {
                ActionProposalView(
                    intro: intro,
                    actions: actions,
                    memoryProposals: memoryProposals,
                    onApproveAll: onApproveAll,
                    onApprove: onApprove,
                    onReject: onReject,
                    onRejectAll: onRejectAll
                )
            }
        case .activityTags(let tags):
            AssistantMessageContainer {
                ActivityTagsView(tags: tags)
            }
        case .error(let error):
            ErrorBubble(error: error)
        }
    }
}

// MARK: - Text Bubble

struct TextBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser {
                Spacer(minLength: 46)
                userBubble
            } else {
                AssistantAvatar(size: 32)
                assistantBubble
                Spacer(minLength: 44)
            }
        }
    }

    private var userBubble: some View {
        Text(text)
            .font(.body)
            .lineSpacing(2)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [.blue, Color(red: 0.0, green: 0.52, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 20,
                    style: .continuous
                )
            )
            .foregroundStyle(.white)
            .shadow(color: .blue.opacity(0.18), radius: 10, y: 4)
    }

    private var assistantBubble: some View {
        Text(text)
            .font(.body)
            .lineSpacing(2)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(
                Color(.systemBackground).opacity(0.9),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 20,
                    style: .continuous
                )
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
            .foregroundStyle(.primary)
    }
}

struct AssistantMessageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar(size: 32)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 24)
        }
    }
}

// MARK: - Error Bubble

struct ErrorBubble: View {
    let error: AIServiceError

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar(size: 32)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI request failed")
                        .font(.subheadline.weight(.semibold))
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            }
            Spacer(minLength: 24)
        }
    }
}
