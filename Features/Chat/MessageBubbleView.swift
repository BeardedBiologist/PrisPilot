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
            .textSelection(.enabled)
            .shadow(color: .blue.opacity(0.18), radius: 10, y: 4)
    }

    private var assistantBubble: some View {
        Text(text)
            .font(.body)
            .lineSpacing(2)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(
                Color(.secondarySystemBackground),
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .foregroundStyle(.primary)
            .textSelection(.enabled)
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

// MARK: - Completion Bubble

struct OnboardingCompleteBubble: View {
    let onStartNewChat: () -> Void

    var body: some View {
        AssistantMessageContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Setup complete")
                            .font(.headline.weight(.semibold))
                        Text("Thanks. PrisPilot is ready to use.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Open a new chat when you are ready to log prices, build a shopping list, or plan a cheap shop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button {
                    onStartNewChat()
                } label: {
                    Label("Start new chat", systemImage: "plus.bubble.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
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
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            }
            Spacer(minLength: 24)
        }
    }
}
