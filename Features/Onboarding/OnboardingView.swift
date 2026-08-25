import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onStartAISetup: () -> Void
    @State private var step: Step = .welcome
    @State private var selectedBranchIDs: Set<UUID> = []
    @State private var selectedOption: String?
    @State private var freeformAnswer = ""

    init(onStartAISetup: @escaping () -> Void = {}) {
        self.onStartAISetup = onStartAISetup
    }

    enum Step: Equatable {
        case welcome
        case manualQuestion(Int)
        case done
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .manualQuestion(let index):
                    manualQuestionStep(index)
                case .done:
                    doneStep
                }
            }
            .transition(stepTransition)
        }
        .interactiveDismissDisabled(step != .welcome)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func setStep(_ newStep: Step) {
        guard !reduceMotion else {
            step = newStep
            return
        }
        withAnimation(.smooth) {
            step = newStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "cart.fill.badge.plus")
                    .font(.system(size: 88))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .symbolEffectsRemoved(reduceMotion)

                VStack(spacing: 8) {
                    Text("PrisPilot")
                        .font(.largeTitle.weight(.bold))
                    Text("Track grocery prices, manage\nlists, and shop smarter.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    beginManualOnboarding()
                } label: {
                    Label("Set up manually", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button {
                    store.startOrResumeAIOnboardingChat()
                    onStartAISetup()
                    dismiss()
                } label: {
                    Label("Set up with AI in Chat", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button("Skip for now") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Skip") { dismiss() }.foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Manual Questions

    private func manualQuestionStep(_ index: Int) -> some View {
        let question = OnboardingFlow.questions[index]

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Step \(index + 1) of \(OnboardingFlow.questions.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(question.title)
                    .font(.largeTitle.weight(.bold))
                Text(question.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ProgressView(value: Double(index + 1), total: Double(OnboardingFlow.questions.count))
                .animation(reduceMotion ? nil : .smooth, value: index)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            if question.id == .stores {
                storeSelectionList
            } else {
                answerForm(for: question)
            }

            Button(index == OnboardingFlow.questions.count - 1 ? "Finish setup" : "Continue") {
                saveManualAnswer(question, index: index)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canContinue(question))
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { goBack(from: index) }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Skip") { movePastQuestion(index) }
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadQuestionState(question)
        }
    }

    private func answerForm(for question: OnboardingQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(question.prompt)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if !question.options.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(question.options, id: \.self) { option in
                            Button {
                                selectedOption = option
                                if !question.allowsFreeText {
                                    freeformAnswer = option
                                }
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    Image(systemName: selectedOption == option ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedOption == option ? .blue : Color(.systemGray3))
                                        .contentTransition(.symbolEffect(.replace))
                                        .symbolEffectsRemoved(reduceMotion)
                                }
                                .padding(14)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .animation(reduceMotion ? nil : .snappy, value: selectedOption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if question.allowsFreeText {
                    TextField("Type your answer", text: $freeformAnswer, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...7)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
                }
            }
            .padding(24)
        }
    }

    private var storeSelectionList: some View {
        List {
            Section {
                Text(OnboardingFlow.questions.first(where: { $0.id == .stores })?.prompt ?? "Choose stores")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(store.chains) { chain in
                let chainBranches = store.branches.filter { $0.chainID == chain.id }
                if !chainBranches.isEmpty {
                    Section(chain.name) {
                        ForEach(chainBranches) { branch in
                            HStack {
                                Text(branch.displayName)
                                Spacer()
                                Image(systemName: selectedBranchIDs.contains(branch.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedBranchIDs.contains(branch.id) ? .blue : Color(.systemGray3))
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffectsRemoved(reduceMotion)
                            }
                            .contentShape(Rectangle())
                            .animation(reduceMotion ? nil : .snappy, value: selectedBranchIDs)
                            .onTapGesture {
                                if selectedBranchIDs.contains(branch.id) {
                                    selectedBranchIDs.remove(branch.id)
                                } else {
                                    selectedBranchIDs.insert(branch.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .symbolEffectsRemoved(reduceMotion)

                VStack(spacing: 10) {
                    Text("You're all set!")
                        .font(.largeTitle.weight(.bold))
                    Text("Thanks. PrisPilot is ready to help with prices, lists, and shopping plans.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 14) {
                    tipRow("bubble.left.and.bubble.right.fill", "Open Chat to record prices and manage lists")
                    tipRow("cart.fill", "Browse shopping lists manually")
                    tipRow("tag.fill", "Compare prices across your enabled stores")
                    tipRow("brain.head.profile", "Your AI preferences are stored as setup answers")
                }
                .padding(18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            }

            Spacer()

            Button("Start Shopping") {
                store.settings.onboardingCompleted = true
                dismiss()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.bottom, 48)
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func beginManualOnboarding() {
        selectedBranchIDs = Set(store.branches.filter(\.isEnabled).map(\.id))
        if selectedBranchIDs.isEmpty {
            selectedBranchIDs = Set(store.branches.map(\.id))
        }
        setStep(.manualQuestion(0))
    }

    private func loadQuestionState(_ question: OnboardingQuestion) {
        if question.id == .stores {
            if selectedBranchIDs.isEmpty {
                selectedBranchIDs = Set(store.branches.filter(\.isEnabled).map(\.id))
            }
            return
        }

        let existing = store.onboardingAnswers[question.id] ?? ""
        freeformAnswer = existing
        selectedOption = question.options.first { $0 == existing }
    }

    private func canContinue(_ question: OnboardingQuestion) -> Bool {
        if question.id == .stores {
            return !selectedBranchIDs.isEmpty
        }
        if !question.allowsFreeText {
            return selectedOption != nil
        }
        return !freeformAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedOption != nil
    }

    private func saveManualAnswer(_ question: OnboardingQuestion, index: Int) {
        if question.id == .stores {
            applyBranchSelection()
            let enabledNames = store.enabledBranches.map(\.displayName).joined(separator: ", ")
            store.recordOnboardingAnswer(enabledNames, for: question.id)
        } else {
            let answer = freeformAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedOption ?? "" : freeformAnswer
            store.recordOnboardingAnswer(answer, for: question.id)
        }
        movePastQuestion(index)
    }

    private func movePastQuestion(_ index: Int) {
        selectedOption = nil
        freeformAnswer = ""
        if index + 1 < OnboardingFlow.questions.count {
            setStep(.manualQuestion(index + 1))
        } else {
            store.settings.onboardingCompleted = true
            setStep(.done)
        }
    }

    private func goBack(from index: Int) {
        selectedOption = nil
        freeformAnswer = ""
        if index == 0 {
            setStep(.welcome)
        } else {
            setStep(.manualQuestion(index - 1))
        }
    }

    private func applyBranchSelection() {
        for i in store.branches.indices {
            store.branches[i].isEnabled = selectedBranchIDs.contains(store.branches[i].id)
        }
        store.persistNow()
    }
}

#Preview {
    OnboardingView()
        .environment(AppStore.shared)
}
