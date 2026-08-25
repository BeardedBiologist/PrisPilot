import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .chat
    @State private var showOnboarding = false

    enum RootTab: Hashable {
        case shopping
        case prices
        case chat
        case recipes
        case profile
    }

    var body: some View {
        VStack(spacing: 0) {
            currentTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            customTabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                selectedTab = .chat
            }
            .environment(store)
        }
        .onAppear {
            store.ensureDefaultChatSession()
            if !store.settings.onboardingCompleted {
                if store.resumeAIOnboardingChatIfAvailable() {
                    selectedTab = .chat
                } else {
                    showOnboarding = true
                }
            }
        }
        .task {
            await AuthStore.shared.checkExistingCredential()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.persistNow()
            }
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch selectedTab {
        case .shopping:
            ShoppingView()
        case .prices:
            PricesView()
        case .chat:
            ChatView()
        case .recipes:
            RecipesView()
        case .profile:
            SettingsView()
        }
    }

    private var customTabBar: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.shopping, title: "Shopping", systemImage: "cart.fill")
            tabButton(.prices, title: "Prices", systemImage: "tag.fill")
            chatTabButton
            tabButton(.recipes, title: "Recipes", systemImage: "fork.knife")
            tabButton(.profile, title: "Profile", systemImage: "person.circle.fill")
        }
        .frame(height: 82)
        .padding(.horizontal, 18)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabButton(_ tab: RootTab, title: String, systemImage: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(height: 25)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selectedTab == tab ? .blue : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var chatTabButton: some View {
        Button {
            selectedTab = .chat
        } label: {
            VStack(spacing: 2) {
                MainChatTabIcon(isSelected: selectedTab == .chat)
                Text("Chat")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat")
    }
}

struct MainChatTabIcon: View {
    var isSelected = true

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.blue.opacity(0.8), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isSelected ? .white : .blue)
        }
        .frame(width: 50, height: 50)
        .accessibilityHidden(true)
    }
}

#Preview {
    RootTabView()
        .environment(AppStore.shared)
        .environment(AuthStore.shared)
}
