import SwiftUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @State private var viewModel = ChatViewModel(appStore: .shared)
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ChatSurfaceBackground()

                VStack(spacing: 0) {
                    chatHeader
                    messageList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    inputBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.ensureDefaultChatSession()
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ChatHistoryView(viewModel: viewModel)
            } label: {
                HeaderIconButton(systemImage: "clock.arrow.circlepath")
            }
            .accessibilityLabel("Chat history")

            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedChatSession?.title ?? "PrisPilot")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.isUsingLiveAI ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(store.isUsingLiveAI ? "Live AI" : "Mock AI")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.startNewChat()
            } label: {
                HeaderIconButton(systemImage: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New chat")

            NavigationLink {
                MemoryListView()
            } label: {
                HeaderIconButton(systemImage: "brain.head.profile")
            }
            .accessibilityLabel("AI memory")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            onApproveAll: { viewModel.approveAll(in: message.id) },
                            onApprove: { id in viewModel.approve(actionID: id, in: message.id) },
                            onReject: { id in viewModel.reject(actionID: id, in: message.id) },
                            onRejectAll: { viewModel.rejectAll(in: message.id) }
                        )
                        .id(message.id)
                    }

                    if viewModel.isTyping {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isTyping) { _, typing in
                if typing { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private var shouldShowSuggestions: Bool {
        viewModel.messages.filter { $0.role == .user }.isEmpty && !viewModel.isTyping
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if viewModel.isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 10) {
            if shouldShowSuggestions {
                SuggestedPromptGrid { prompt in
                    viewModel.inputText = prompt
                    inputFocused = true
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask PrisPilot...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }

                Button {
                    viewModel.sendMessage()
                    inputFocused = false
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(canSend ? Color.blue : Color(.systemGray3), in: Circle())
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }
}

// MARK: - Chat Surface

struct ChatSurfaceBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(red: 0.96, green: 0.98, blue: 0.98),
                Color(red: 0.98, green: 0.97, blue: 0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct HeaderIconButton: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 42, height: 42)
            .background(Color(.systemBackground).opacity(0.86), in: Circle())
            .overlay {
                Circle().stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SuggestedPromptGrid: View {
    let onSelect: (String) -> Void

    private let prompts = [
        ("tag.fill", "Log a price", "I paid kr 39.90 for 400 g minced beef at Kiwi"),
        ("cart.fill", "Build a list", "Make a shopping list for tacos under kr 250"),
        ("fork.knife", "Plan dinner", "Plan three cheap dinners for this week"),
        ("brain.head.profile", "Remember this", "Remember that I prefer Kiwi and Rema 1000")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.1) { prompt in
                    Button {
                        onSelect(prompt.2)
                    } label: {
                        Label(prompt.1, systemImage: prompt.0)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground), in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 34)
    }
}

// MARK: - Chat History

struct ChatHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let viewModel: ChatViewModel

    var body: some View {
        List {
            ForEach(store.chatSessions) { session in
                Button {
                    viewModel.selectChatSession(session.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: store.selectedChatSessionID == session.id ? "checkmark.circle.fill" : "bubble.left.and.bubble.right")
                            .foregroundStyle(store.selectedChatSessionID == session.id ? .blue : .secondary)
                            .frame(width: 26)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(session.previewText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(session.updatedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { offsets in
                viewModel.deleteChatSessions(at: offsets)
            }
        }
        .navigationTitle("Chat History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.startNewChat()
                    dismiss()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New chat")
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AssistantAvatar(size: 28)

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 8, height: 8)
                        .offset(y: dotOffset(for: i))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(Color(.systemBackground).opacity(0.86), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.2
        return phase == 0 ? 0 : sin((phase + delay) * .pi) * -4
    }
}

// MARK: - Shared Chat Elements

struct AssistantAvatar: View {
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [.blue, Color(red: 0.0, green: 0.62, blue: 0.56)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }
}

// MARK: - Memory List View

struct MemoryListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            if store.activeMemories.isEmpty {
                ContentUnavailableView(
                    "No Memories Yet",
                    systemImage: "brain.head.profile",
                    description: Text("As you use the app, I'll remember your preferences here.")
                )
            } else {
                ForEach(store.activeMemories) { memory in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: memory.category.systemImage)
                                .foregroundStyle(.purple)
                            Text(memory.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(memory.summary)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("AI Memory")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    ChatView()
        .environment(AppStore.shared)
}
