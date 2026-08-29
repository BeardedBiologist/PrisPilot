import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    var onApproveAll: () -> Void
    var onApprove: (UUID) -> Void
    var onReject: (UUID) -> Void
    var onRejectAll: () -> Void
    var onStartNewChat: () -> Void = {}

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
        case .onboardingComplete:
            OnboardingCompleteBubble(onStartNewChat: onStartNewChat)
        }
    }
}

// MARK: - Text Bubble

struct TextBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 40)
                userBubble
            } else {
                AssistantAvatar(size: 26)
                assistantBubble
                Spacer(minLength: 36)
            }
        }
    }

    private var userBubble: some View {
        Text(text)
            .font(.callout)
            .lineSpacing(1.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [.blue, Color(red: 0.0, green: 0.52, blue: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .shadow(color: .blue.opacity(0.15), radius: 8, y: 3)
    }

    private var assistantBubble: some View {
        Text(text)
            .font(.callout)
            .lineSpacing(1.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Color(.secondarySystemBackground),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
}

struct AssistantMessageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar(size: 26)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 20)
        }
    }
}

// MARK: - Completion Bubble

struct OnboardingCompleteBubble: View {
    let onStartNewChat: () -> Void

    var body: some View {
        AssistantMessageContainer {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Setup complete")
                            .font(.subheadline.weight(.semibold))
                        Text("Thanks. PrisPilot is ready to use.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Open a new chat when you are ready to log prices, build a shopping list, or plan a cheap shop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button {
                    onStartNewChat()
                } label: {
                    Label("Start new chat", systemImage: "plus.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

// MARK: - Error Bubble

struct ErrorBubble: View {
    let error: AIServiceError

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar(size: 26)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI request failed")
                        .font(.caption.weight(.semibold))
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(11)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            }
            Spacer(minLength: 24)
        }
    }
}
