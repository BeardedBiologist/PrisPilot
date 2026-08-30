import SwiftUI

/// Shared tokens for the Liquid Glass redesign. Keep these referenced from
/// every new glass control so spacing, tint, and shape stay consistent
/// across the tab bar, headers, and floating controls.
enum GlassTheme {
    /// Accent tint applied to interactive glass controls app-wide.
    static let tint = Color.blue

    /// `GlassEffectContainer` spacing for a cluster of related controls
    /// (tab bar icons, header button groups, chip rows). Matches or exceeds
    /// the interior layout spacing so shapes blend while morphing and stay
    /// visually separate at rest.
    static let containerSpacing: CGFloat = 20

    /// Corner radius for glass surfaces that aren't a `Capsule`.
    static let cornerRadius: CGFloat = 20

    /// Standard spring used for glass morphing / selection transitions.
    static let motionSpring: Animation = .spring(duration: 0.4, bounce: 0.2)
}

extension View {
    /// Applies `transform` only when Reduce Motion is off, otherwise returns
    /// the view unchanged. Use around large-motion additions (matched
    /// geometry, zoom transitions, phase/keyframe animators) so accessibility
    /// users get a static or cross-fade fallback instead of the full effect.
    @ViewBuilder
    func motionSensitive<Content: View>(
        reduceMotion: Bool,
        @ViewBuilder _ transform: (Self) -> Content
    ) -> some View {
        if reduceMotion {
            self
        } else {
            transform(self)
        }
    }
}

extension EnvironmentValues {
    /// The floating glass tab bar's actual rendered height (measured live by
    /// `RootTabView`, not a hand-maintained constant). Zero when no tab bar
    /// is present (e.g. previews). Feature views read this directly instead
    /// of relying on the tab bar's ancestor `NavigationStack` to propagate a
    /// safe-area reservation — that propagation proved unreliable for
    /// `ScrollView`-based content and for non-scrolling bottom bars (see
    /// `LIQUID_GLASS_REDESIGN_LOG.md`), so every tab explicitly reserves
    /// this amount of space itself.
    @Entry var floatingTabBarInset: CGFloat = 0

    /// Lets a feature tab (Shopping, Prices, Meals) jump the user straight to
    /// Chat — e.g. an "Ask AI" entry point on a tab's overview screen. Set by
    /// `RootTabView` to its own tab-switching logic; defaults to a no-op so
    /// previews and any view rendered outside `RootTabView` don't crash.
    @Entry var switchToChatTab: () -> Void = {}

    /// Same idea as `switchToChatTab`, but for Settings — used by read-only
    /// settings readouts (e.g. Shopping's optimization controls) that link
    /// out to where the value is actually editable instead of duplicating
    /// editable controls in two places.
    @Entry var switchToSettingsTab: () -> Void = {}

    /// Lets any scrollable feature view request that the floating tab bar be
    /// shown or hidden. RootTabView wires this to its own visibility state;
    /// defaults to a no-op so previews don't crash.
    @Entry var setTabBarVisible: (Bool) -> Void = { _ in }

    /// Current visibility of the floating tab bar. Scroll modifiers read this
    /// so manual reveals from RootTabView don't leave stale local state behind.
    @Entry var floatingTabBarVisible: Bool = true
}

private struct HideTabBarOnScrollDown: ViewModifier {
    @Environment(\.setTabBarVisible) private var setTabBarVisible
    @Environment(\.floatingTabBarVisible) private var tabBarVisible
    /// Y offset at the point the last hide/show was triggered (or at the
    /// point the user reversed direction while visible). Comparing against
    /// this baseline — rather than the previous frame — prevents the 5pt-
    /// per-frame accumulation that caused constant flickering.
    @State private var baselineY: CGFloat = 0
    @State private var scrollPhase: ScrollPhase = .idle

    private let hideThreshold: CGFloat = 80
    private let showThreshold: CGFloat = 120
    private let topRestoreThreshold: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, newPhase, context in
                scrollPhase = newPhase

                if newPhase == .tracking || newPhase == .interacting || newPhase == .idle {
                    baselineY = context.geometry.contentOffset.y
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, new in
                // Near top: always restore and reset baseline (handles bouncing).
                if new < topRestoreThreshold {
                    if !tabBarVisible {
                        setTabBarVisible(true)
                    }
                    baselineY = new
                    return
                }

                let displacement = new - baselineY

                if tabBarVisible {
                    if displacement >= hideThreshold {
                        baselineY = new
                        setTabBarVisible(false)
                    } else if displacement < 0 {
                        baselineY = new // Track upward movement while visible
                    }
                } else {
                    if scrollPhase == .interacting && displacement <= -showThreshold {
                        baselineY = new
                        setTabBarVisible(true)
                    } else if displacement > 0 {
                        baselineY = new // Advance baseline when scrolling deeper while hidden
                    }
                }
            }
    }
}

extension View {
    /// Hides the floating tab bar when the user scrolls down, reveals it when
    /// they scroll back up. Apply to the top-level `List` or `ScrollView` of
    /// each main tab.
    func hideTabBarOnScrollDown() -> some View {
        modifier(HideTabBarOnScrollDown())
    }
}

private struct ReservesFloatingTabBarSpace: ViewModifier {
    @Environment(\.floatingTabBarInset) private var inset

    func body(content: Content) -> some View {
        // `.safeAreaInset(edge:)` with actual accessory content makes `List`
        // treat that region as a toolbar-like accessory and draw its own
        // background/edge-effect chrome behind it — visible as a stray
        // bar-shaped surface even when the accessory content is
        // `Color.clear`. `.safeAreaPadding` reserves the same space as inert
        // padding, with no accessory slot for the system to decorate.
        content.safeAreaPadding(.bottom, inset)
    }
}

extension View {
    /// Reserves bottom clearance for the floating glass tab bar on a
    /// `List`/`ScrollView` so its content isn't hidden behind it. Applied at
    /// the same view that owns the scrollable content — not on an ancestor —
    /// so there's no `NavigationStack` boundary for the reservation to fail
    /// to cross.
    func reservesFloatingTabBarSpace() -> some View {
        modifier(ReservesFloatingTabBarSpace())
    }
}

private struct ZoomTransitionIfAvailable<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        // Zoom is large motion — Reduce Motion falls back to the default
        // push transition, same as the "no matching namespace" case below.
        if let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// Applies `.navigationTransition(.zoom(sourceID:in:))` only when a
    /// namespace is actually provided and Reduce Motion is off. Use on a
    /// destination view that may be reached from more than one place (e.g. a
    /// row push and a separate activity-tag detail sheet) — only the entry
    /// point that owns a matching `matchedTransitionSource` should pass a
    /// real namespace; every other entry point passes `nil` and falls back
    /// to the default push transition instead of misbehaving with an
    /// unmatched source.
    func zoomTransition<ID: Hashable>(id: ID, namespace: Namespace.ID?) -> some View {
        modifier(ZoomTransitionIfAvailable(id: id, namespace: namespace))
    }
}
