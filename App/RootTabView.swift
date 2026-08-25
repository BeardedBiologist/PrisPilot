import SwiftUI
import UIKit

struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: RootTab = .chat
    @State private var showOnboarding = false
    @State private var measuredTabBarHeight: CGFloat = 100
    @Namespace private var tabBarNamespace

    enum RootTab: Hashable {
        case shopping
        case prices
        case chat
        case recipes
        case profile
    }

    var body: some View {
        // Floating overlay, not flow layout: Liquid Glass needs content
        // behind it to actually refract/blur, and a flow-layout bar (with
        // flat app background directly behind it) renders as visually flat.
        // Unlike the earlier floating attempts, clearance is not left to
        // ancestor `.safeAreaInset` propagation across each tab's own
        // `NavigationStack` (proven unreliable — see
        // LIQUID_GLASS_REDESIGN_LOG.md). Instead the bar's *actual* rendered
        // height is measured live and handed down via
        // `\.floatingTabBarInset`; every feature view is responsible for
        // reserving that space itself, at the point where its own scrollable
        // content lives.
        ZStack(alignment: .bottom) {
            currentTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.floatingTabBarInset, measuredTabBarHeight)
                .environment(\.switchToChatTab) { selectTab(.chat) }

            customTabBar
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    measuredTabBarHeight = newHeight
                }
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
        ZStack(alignment: .top) {
            GlassEffectContainer(spacing: GlassTheme.containerSpacing) {
                Color.clear
                    .frame(height: 92)
                    .glassEffect(.regular, in: RaisedTabBarBackground())
            }

            HStack(alignment: .center, spacing: 2) {
                tabButton(.shopping, title: "Shopping", systemImage: "cart", selectedImage: "cart.fill")
                tabButton(.prices, title: "Prices", systemImage: "tag", selectedImage: "tag.fill")

                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .accessibilityHidden(true)

                tabButton(.recipes, title: "Recipes", systemImage: "fork.knife", selectedImage: "fork.knife")
                tabButton(.profile, title: "Profile", systemImage: "person.circle", selectedImage: "person.circle.fill")
            }
            .padding(.horizontal, 12)
            .padding(.top, 28)
            .padding(.bottom, 6)

            chatTabButton
                .frame(width: 84, height: 72)
                .zIndex(1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: RootTab, title: String, systemImage: String, selectedImage: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectTab(tab)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(GlassTheme.tint.opacity(0.16))
                            .frame(width: 44, height: 30)
                            .matchedGeometryEffect(id: "tabSelection", in: tabBarNamespace)
                    }
                    Image(systemName: isSelected ? selectedImage : systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 25)
                }
                .frame(height: 30)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? GlassTheme.tint : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var chatTabButton: some View {
        let isSelected = selectedTab == .chat
        return Button {
            selectTab(.chat)
        } label: {
            // No caption under this one — the bubble is bigger than the
            // other icons and raised above the row on its own, which is
            // enough to read as "the main tab" without a label. A label
            // would need to sit far below the raised icon to clear it,
            // which reads as a stray floating word (see log).
            MainChatTabIcon(isSelected: isSelected)
                .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectTab(_ tab: RootTab) {
        guard tab != selectedTab else { return }
        guard !reduceMotion else {
            selectedTab = tab
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(GlassTheme.motionSpring) {
            selectedTab = tab
        }
    }
}

private struct RaisedTabBarBackground: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 36
        let barTop: CGFloat = 26
        let bumpRadius = min(rect.width * 0.13, 42)
        let bumpCenter = CGPoint(x: rect.midX, y: 40)

        let barRect = CGRect(
            x: rect.minX,
            y: rect.minY + barTop,
            width: rect.width,
            height: rect.height - barTop
        )

        var path = Path()
        path.addRoundedRect(in: barRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        path.addEllipse(in: CGRect(
            x: bumpCenter.x - bumpRadius,
            y: bumpCenter.y - bumpRadius,
            width: bumpRadius * 2,
            height: bumpRadius * 2
        ))
        return path
    }
}

struct MainChatTabIcon: View {
    var isSelected = true

    var body: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(isSelected ? .white : GlassTheme.tint)
            .frame(width: 64, height: 64)
            .glassEffect(
                isSelected ? .regular.tint(GlassTheme.tint).interactive() : .regular.interactive(),
                in: Circle()
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}

#Preview {
    RootTabView()
        .environment(AppStore.shared)
        .environment(AuthStore.shared)
}
