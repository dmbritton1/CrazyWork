import UIKit

enum ThemeAppearance {
    /// Themes UIKit-backed bars (tab + nav) to the canvas surface with hairline rules.
    /// UIKit appearance proxies are main-actor isolated, so this must be too.
    @MainActor static func configure() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Palette.canvas)
        tab.shadowColor = UIColor(Palette.hairline)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(Palette.onDark)
        UITabBar.appearance().unselectedItemTintColor = UIColor(Palette.mute)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Palette.canvas)
        nav.shadowColor = UIColor(Palette.hairline)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Palette.ink)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Palette.ink)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
