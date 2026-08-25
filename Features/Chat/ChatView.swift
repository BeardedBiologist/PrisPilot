import SwiftUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.floatingTabBarInset) private var floatingTabBarInset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = ChatViewModel(appStore: .shared)
    @FocusState private var inputFocused: Bool
    @State private var sendBounce = false

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
            GlassEffectContainer(spacing: GlassTheme.containerSpacing) {
                NavigationLink {
                    ChatHistoryView(viewModel: viewModel)
                } label: {
                    HeaderIconButton(systemImage: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Chat history")
            }

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

            GlassEffectContainer(spacing: GlassTheme.containerSpacing) {
                HStack(spacing: 10) {
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
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
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
                            onRejectAll: { viewModel.rejectAll(in: message.id) },
                            onStartNewChat: { viewModel.startNewChat() }
                        )
                        .id(message.id)
                        .transition(messageTransition)
                    }

                    if viewModel.isTyping {
                        TypingIndicatorView()
                            .id("typing")
                            .transition(messageTransition)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .animation(reduceMotion ? nil : .snappy, value: viewModel.messages.count)
                .animation(reduceMotion ? nil : .snappy, value: viewModel.isTyping)
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

    private var messageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .push(from: .bottom).combined(with: .opacity),
                removal: .opacity
            )
    }

    private var shouldShowSuggestions: Bool {
        guard let sessionID = store.selectedChatSessionID,
              store.purpose(for: sessionID) == .general else { return false }
        return viewModel.messages.filter { $0.role == .user }.isEmpty && !viewModel.isTyping
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
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                Button {
                    sendBounce.toggle()
                    viewModel.sendMessage()
                    inputFocused = false
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: sendBounce)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glassProminent)
                .tint(GlassTheme.tint)
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
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .padding(.bottom, floatingTabBarInset)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }
}

// MARK: - Chat Surface

struct ChatSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark ? darkColors : lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [
            Color(.systemBackground),
            Color(red: 0.96, green: 0.98, blue: 0.98),
            Color(red: 0.98, green: 0.97, blue: 0.94)
        ]
    }

    private var darkColors: [Color] {
        [
            Color(red: 0.07, green: 0.09, blue: 0.10),
            Color(red: 0.04, green: 0.12, blue: 0.13),
            Color(red: 0.11, green: 0.10, blue: 0.07)
        ]
    }
}

struct HeaderIconButton: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 42, height: 42)
            .glassEffect(.regular.interactive(), in: Circle())
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
                            .background(Color(.secondarySystemBackground), in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
        .reservesFloatingTabBarSpace()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AssistantAvatar(size: 28)

            Group {
                if reduceMotion {
                    dots(activeIndex: nil)
                } else {
                    PhaseAnimator([0, 1, 2]) { activeIndex in
                        dots(activeIndex: activeIndex)
                    } animation: { _ in
                        .easeInOut(duration: 0.3)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dots(activeIndex: Int?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(activeIndex == i ? 1.35 : 1.0)
                    .offset(y: activeIndex == i ? -4 : 0)
            }
        }
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
    @State private var editingMemory: AIMemory?

    private var grouped: [(scope: DataScope, groups: [(category: MemoryCategory, memories: [AIMemory])])] {
        [DataScope.personal, DataScope.household].compactMap { scope in
            let scopedMemories = store.activeMemories.filter { $0.scope == scope }
            let groups = MemoryCategory.allCases.compactMap { cat in
                let items = scopedMemories.filter { $0.category == cat }
                return items.isEmpty ? nil : (category: cat, memories: items)
            }
            return groups.isEmpty ? nil : (scope: scope, groups: groups)
        }
    }

    var body: some View {
        List {
            if store.activeMemories.isEmpty {
                ContentUnavailableView(
                    "No Memories Yet",
                    systemImage: "brain.head.profile",
                    description: Text("As you use the app, I'll remember your preferences here.")
                )
            } else {
                ForEach(grouped, id: \.scope) { scopeGroup in
                    ForEach(scopeGroup.groups, id: \.category) { group in
                        Section {
                            ForEach(group.memories) { memory in
                                Button {
                                    editingMemory = memory
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(memory.summary)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 6) {
                                            Text(memory.strength.rawValue)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.12), in: Capsule())
                                                .foregroundStyle(.purple)
                                            Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteMemory(memory.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Label("\(scopeGroup.scope.rawValue) · \(group.category.rawValue)", systemImage: group.category.systemImage)
                        }
                    }
                }
            }
        }
        .reservesFloatingTabBarSpace()
        .navigationTitle("AI Memory")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingMemory) { memory in
            MemoryEditSheet(memory: memory)
                .environment(store)
        }
    }
}

struct MemoryEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let memory: AIMemory

    @State private var summary: String
    @State private var category: MemoryCategory
    @State private var strength: ConstraintStrength
    @State private var sensitivityLevel: SensitivityLevel
    @State private var showDeleteConfirmation = false

    init(memory: AIMemory) {
        self.memory = memory
        _summary = State(initialValue: memory.summary)
        _category = State(initialValue: memory.category)
        _strength = State(initialValue: memory.strength)
        _sensitivityLevel = State(initialValue: memory.sensitivityLevel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Classification") {
                    Picker("Category", selection: $category) {
                        ForEach(MemoryCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                    Picker("Strength", selection: $strength) {
                        ForEach(ConstraintStrength.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    Picker("Sensitivity", selection: $sensitivityLevel) {
                        ForEach(SensitivityLevel.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }

                Section {
                    LabeledContent("Saved", value: memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete memory", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateMemory(
                            memory.id,
                            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category,
                            strength: strength,
                            sensitivityLevel: sensitivityLevel
                        )
                        dismiss()
                    }
                    .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete Memory", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    store.deleteMemory(memory.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This memory will be permanently removed.")
            }
        }
    }
}

#Preview {
    ChatView()
        .environment(AppStore.shared)
}
