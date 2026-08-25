import SwiftUI
import UIKit

/// User-facing appearance override, stored directly via `@AppStorage` (not
/// part of `AppSettings`/`AppStoreSnapshot`) so it never touches the
/// Codable snapshot schema those types persist — no migration risk for
/// existing saved data.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` defers entirely to the system appearance, including iOS's own
    /// time-of-day-based Automatic schedule if the user has that enabled in
    /// Settings — the app doesn't need to reimplement that scheduling.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// Applies the persisted appearance override. Call once, at the app
    /// root — presented sheets/covers inherit it from there.
    func appliesAppearanceMode() -> some View {
        modifier(AppearanceModeModifier())
    }
}

private struct AppearanceModeModifier: ViewModifier {
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var mode: AppearanceMode { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(mode.colorScheme)
            .onAppear { applyToWindows() }
            .onChange(of: appearanceModeRaw) { _, _ in applyToWindows() }
    }

    // `.preferredColorScheme` alone doesn't reliably reach the actual
    // UIWindow trait through this app's deeper custom view hierarchy
    // (GlassEffectContainer/ZStack/safeAreaInset layering) — setting
    // `overrideUserInterfaceStyle` directly operates at the OS level and
    // can't be missed by SwiftUI environment propagation.
    private func applyToWindows() {
        let style: UIUserInterfaceStyle
        switch mode {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
