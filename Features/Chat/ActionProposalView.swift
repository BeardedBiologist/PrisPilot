import SwiftUI

// MARK: - Proposal Alert

private enum ProposalAlert: Identifiable {
    case highRiskAction(UUID, String)
    case highRiskApproveAll(Int)

    var id: String {
        switch self {
        case .highRiskAction(let id, _): return id.uuidString
        case .highRiskApproveAll: return "approveAll"
        }
    }
}

// MARK: - Action Group

private struct ActionGroup: Identifiable {
    let domain: ActionDomain
    let actions: [ProposedAction]
    var id: String { domain.rawValue }
}

// MARK: - Action Proposal View

struct ActionProposalView: View {
    let intro: String?
    var assumptions: [String] = []
    let actions: [ProposedAction]
    let memoryProposals: [MemoryProposal]
    var onApproveAll: () -> Void
    var onApprove: (UUID) -> Void
    var onReject: (UUID) -> Void
    var onRejectAll: () -> Void
    var onEdit: ((UUID, ProposedActionPayload, String) -> Void)? = nil

    @State private var editingAction: ProposedAction?
    @State private var activeAlert: ProposalAlert?

    private var hasPending: Bool {
        actions.contains { $0.status == .pending } || !memoryProposals.isEmpty
    }

    private var highRiskPendingCount: Int {
        actions.filter { $0.status == .pending && $0.riskLevel == .high }.count
    }

    private var groupedActions: [ActionGroup] {
        var groups: [ActionDomain: [ProposedAction]] = [:]
        var order: [ActionDomain] = []
        for action in actions {
            let domain = action.type.domain
            if groups[domain] == nil {
                groups[domain] = []
                order.append(domain)
            }
            groups[domain]!.append(action)
        }
        return order.map { ActionGroup(domain: $0, actions: groups[$0]!) }
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

            if !assumptions.isEmpty {
                AssumptionSummaryView(assumptions: assumptions)
            }

            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                Divider().opacity(0.6)
                actionRowsGrouped
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
                        let count = highRiskPendingCount
                        if count > 0 {
                            activeAlert = .highRiskApproveAll(count)
                        } else {
                            onApproveAll()
                        }
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .sheet(item: $editingAction) { action in
            ProposalEditorSheet(action: action) { newPayload, newSummary in
                onEdit?(action.id, newPayload, newSummary)
            }
        }
        .alert(item: $activeAlert) { (alert: ProposalAlert) -> Alert in
            switch alert {
            case .highRiskAction(let id, let summary):
                return Alert(
                    title: Text("Confirm Action"),
                    message: Text("\"\(summary)\" is high-risk and may be difficult to reverse."),
                    primaryButton: .destructive(Text("Proceed Anyway")) { onApprove(id) },
                    secondaryButton: .cancel()
                )
            case .highRiskApproveAll(let count):
                let s = count == 1 ? "" : "s"
                return Alert(
                    title: Text("Approve All Actions"),
                    message: Text("This batch contains \(count) high-risk action\(s). Some may be difficult to reverse."),
                    primaryButton: .destructive(Text("Approve All")) { onApproveAll() },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: - Card Header

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

    // MARK: - Grouped Action Rows

    @ViewBuilder
    private var actionRowsGrouped: some View {
        let groups = groupedActions
        let showDomains = groups.count > 1

        ForEach(Array(groups.enumerated()), id: \.element.id) { groupIdx, group in
            if showDomains {
                if groupIdx > 0 { Divider().opacity(0.6) }
                domainHeader(group.domain)
            }
            ForEach(Array(group.actions.enumerated()), id: \.element.id) { actionIdx, action in
                VStack(spacing: 0) {
                    if showDomains || actionIdx > 0 {
                        Divider().padding(.leading, 58).opacity(0.6)
                    }
                    ActionRow(
                        action: action,
                        onApprove: {
                            if action.riskLevel == .high {
                                activeAlert = .highRiskAction(action.id, action.summary)
                            } else {
                                onApprove(action.id)
                            }
                        },
                        onReject: { onReject(action.id) },
                        onEdit: onEdit != nil ? { editingAction = action } : nil
                    )
                }
            }
        }
    }

    private func domainHeader(_ domain: ActionDomain) -> some View {
        HStack(spacing: 6) {
            Image(systemName: domain.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(domain.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Memory Rows

    private var memoryRows: some View {
        ForEach(memoryProposals) { proposal in
            VStack(spacing: 0) {
                Divider().padding(.leading, 58).opacity(0.6)
                MemoryProposalRow(proposal: proposal)
            }
        }
    }
}

private struct AssumptionSummaryView: View {
    let assumptions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Assumptions", systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(assumptions, id: \.self) { assumption in
                Text(assumption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Action Row

struct ActionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: ProposedAction
    var onApprove: () -> Void
    var onReject: () -> Void
    var onEdit: (() -> Void)? = nil

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
                if let onEdit {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(action.type.displayName)")
                }

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
                    Image(systemName: action.riskLevel == .high ? "exclamationmark.triangle.fill" : "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(action.riskLevel == .high ? .orange : .green)
                        .frame(width: 26, height: 26)
                        .background((action.riskLevel == .high ? Color.orange : Color.green).opacity(0.12), in: Circle())
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
