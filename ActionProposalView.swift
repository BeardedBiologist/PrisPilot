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
        VStack(alignment: .leading, spacing: 12) {
            if let intro {
                Text(intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                Divider().opacity(0.6)
                actionRows
                memoryRows
            }
            .background(Color(.systemBackground).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, y: 5)

            if hasPending {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        onRejectAll()
                    } label: {
                        Label("Reject", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
                        onApproveAll()
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Review changes")
                    .font(.subheadline.weight(.semibold))
                Text("\(actions.count + memoryProposals.count) item\((actions.count + memoryProposals.count) == 1 ? "" : "s") ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    let action: ProposedAction
    var onApprove: () -> Void
    var onReject: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: action.type.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(action.type.isMemoryAction ? .purple : .blue)
                .frame(width: 34, height: 34)
                .background((action.type.isMemoryAction ? Color.purple : Color.blue).opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(action.summary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(action.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            actionStatus
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actionStatus: some View {
        switch action.status {
        case .pending:
            HStack(spacing: 8) {
                Button { onReject() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)

                Button { onApprove() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 30, height: 30)
                        .background(Color.green.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
        case .approved, .executing:
            ProgressView().scaleEffect(0.75)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .rejected:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.systemGray3))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }
}

// MARK: - Memory Proposal Row

struct MemoryProposalRow: View {
    let proposal: MemoryProposal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(Color.purple.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.memory.summary)
                    .font(.subheadline.weight(.medium))
                Text("Remember for later")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
