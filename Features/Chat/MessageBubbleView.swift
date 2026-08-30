import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    var quickActions: [ChatQuickAction] = []
    var onApproveAll: () -> Void
    var onApprove: (UUID) -> Void
    var onReject: (UUID) -> Void
    var onRejectAll: () -> Void
    var onEdit: ((UUID, ProposedActionPayload, String) -> Void)? = nil
    var onUsePrompt: (String) -> Void = { _ in }
    var onStartNewChat: () -> Void = {}

    var body: some View {
        switch message.content {
        case .text(let text):
            TextBubble(
                text: text,
                isUser: message.role == .user,
                quickActions: message.role == .assistant ? quickActions : [],
                onUsePrompt: onUsePrompt
            )
        case .proposedActions(let intro, let actions, let memoryProposals):
            AssistantMessageContainer {
                VStack(alignment: .leading, spacing: 8) {
                    ActionProposalView(
                        intro: intro,
                        assumptions: message.assumptions,
                        actions: actions,
                        memoryProposals: memoryProposals,
                        onApproveAll: onApproveAll,
                        onApprove: onApprove,
                        onReject: onReject,
                        onRejectAll: onRejectAll,
                        onEdit: onEdit
                    )
                    if actions.contains(where: { $0.status == .failed }) {
                        RepairSuggestionRow(actions: actions, onUsePrompt: onUsePrompt)
                    }
#if DEBUG
                    if let trace = message.trace {
                        AITraceMetadataView(trace: trace)
                    }
#endif
                }
            }
        case .activityTags(let tags):
            AssistantMessageContainer {
                VStack(alignment: .leading, spacing: 8) {
                    ActivityTagsView(tags: tags)
                    if !quickActions.isEmpty {
                        QuickActionStrip(actions: quickActions, onUsePrompt: onUsePrompt)
                    }
#if DEBUG
                    if let trace = message.trace {
                        AITraceMetadataView(trace: trace)
                    }
#endif
                }
            }
        case .error(let error):
            VStack(alignment: .leading, spacing: 8) {
                ErrorBubble(error: error)
#if DEBUG
                if let trace = message.trace {
                    AITraceMetadataView(trace: trace)
                        .padding(.leading, 34)
                }
#endif
            }
        case .onboardingComplete:
            OnboardingCompleteBubble(onStartNewChat: onStartNewChat)
        }
    }
}

// MARK: - Text Bubble

struct TextBubble: View {
    let text: String
    let isUser: Bool
    var quickActions: [ChatQuickAction] = []
    var onUsePrompt: (String) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 40)
                userBubble
            } else {
                AssistantAvatar(size: 26)
                VStack(alignment: .leading, spacing: 8) {
                    assistantBubble
                    if !quickActions.isEmpty {
                        QuickActionStrip(actions: quickActions, onUsePrompt: onUsePrompt)
                    }
                }
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

struct QuickActionStrip: View {
    let actions: [ChatQuickAction]
    let onUsePrompt: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(actions) { action in
                    Button {
                        onUsePrompt(action.prompt)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minHeight: 30)
    }
}

struct RepairSuggestionRow: View {
    let actions: [ProposedAction]
    let onUsePrompt: (String) -> Void

    private var failedSummaries: String {
        actions
            .filter { $0.status == .failed }
            .prefix(2)
            .map(\.summary)
            .joined(separator: "; ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Button {
                let suffix = failedSummaries.isEmpty ? "" : " The failed change was: \(failedSummaries)."
                onUsePrompt("Let's repair the failed PrisPilot proposal.\(suffix) Ask one concise clarification question if a target is missing or ambiguous.")
            } label: {
                Text("Fix failed action")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

#if DEBUG
struct AITraceMetadataView: View {
    let trace: AITraceMetadata

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                traceRow("Provider", trace.provider)
                traceRow("Model", trace.model)
                traceRow("Prompt", trace.promptVersion)
                traceRow("Schema", trace.schemaVersion)
                traceRow("Format", trace.responseFormat)
                traceRow("Latency", "\(trace.latencyMilliseconds) ms")
                traceRow("Fallbacks", trace.fallbackModelsTried.isEmpty ? "None" : trace.fallbackModelsTried.joined(separator: ", "))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        } label: {
            Label("AI trace", systemImage: "waveform.path.ecg")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func traceRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .fontWeight(.semibold)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
#endif

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
