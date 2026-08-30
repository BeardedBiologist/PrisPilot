import SwiftUI

struct ActionProposalView: View {
    let intro: String?
    let actions: [ProposedAction]
    let memoryProposals: [MemoryProposal]
    var onApproveAll: () -> Void
    var onApprove: (UUID) -> Void
    var onReject: (UUID) -> Void
    var onRejectAll: () -> Void

    private var hasPending: Bool {
        actions.contains { $0.status == .pending } || !memoryProposals.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let intro {
                Text(intro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                Divider().opacity(0.6)
                actionRows
                memoryRows
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)

            if hasPending {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        onRejectAll()
                    } label: {
                        Label("Reject", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(.red)

                    Button {
                        onApproveAll()
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Review changes")
                    .font(.caption.weight(.semibold))
                Text("\(actions.count + memoryProposals.count) item\((actions.count + memoryProposals.count) == 1 ? "" : "s") ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: actions.count + memoryProposals.count)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var actionRows: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in
            VStack(spacing: 0) {
                if i > 0 { Divider().padding(.leading, 58).opacity(0.6) }
                ActionRow(action: action, onApprove: { onApprove(action.id) }, onReject: { onReject(action.id) })
            }
        }
    }

    private var memoryRows: some View {
        ForEach(memoryProposals) { proposal in
            VStack(spacing: 0) {
                Divider().padding(.leading, 58).opacity(0.6)
                MemoryProposalRow(proposal: proposal)
            }
        }
    }
}

// MARK: - Action Row

struct ActionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: ProposedAction
    var onApprove: () -> Void
    var onReject: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: action.type.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(action.type.isMemoryAction ? .purple : .blue)
                .frame(width: 28, height: 28)
                .background((action.type.isMemoryAction ? Color.purple : Color.blue).opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(action.summary)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(action.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                validationMessage
            }

            Spacer(minLength: 6)
            actionStatus
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actionStatus: some View {
        switch action.status {
        case .pending:
            HStack(spacing: 6) {
                Button { onReject() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reject \(action.type.displayName)")

                Button { onApprove() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 26, height: 26)
                        .background(Color.green.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!action.validationResult.isValid)
                .opacity(action.validationResult.isValid ? 1 : 0.45)
                .accessibilityLabel("Approve \(action.type.displayName)")
            }
        case .approved, .executing:
            ProgressView().scaleEffect(0.75)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: action.status)
                .symbolEffectsRemoved(reduceMotion)
        case .rejected:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.systemGray3))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        switch action.validationResult {
        case .valid:
            EmptyView()
        case .invalid(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.red)
        case .warning(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
        case .requiresClarification(let question):
            Text(question)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Memory Proposal Row

struct MemoryProposalRow: View {
    let proposal: MemoryProposal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
                .background(Color.purple.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.memory.summary)
                    .font(.caption.weight(.medium))
                    .textSelection(.enabled)
                Text("Remember for later")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
