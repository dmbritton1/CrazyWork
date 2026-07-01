import SwiftUI

/// The app's motion vocabulary — refined & quick. Every animation references
/// these curves and routes through `resolved` so it self-disables under
/// Reduce Motion. No ad-hoc spring literals at call sites.
enum Motion {
    static let press: Animation  = .spring(response: 0.28, dampingFraction: 0.72)
    static let state: Animation  = .snappy(duration: 0.30)
    static let appear: Animation = .smooth(duration: 0.32)

    /// Reduce-Motion gate: instant (nil) when the user prefers reduced motion.
    static func resolved(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Subtle tactile scale-down while pressed. Self-disables under Reduce Motion.
private struct PressScale: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduce ? 0.97 : 1)
            .animation(Motion.resolved(Motion.press, reduceMotion: reduce), value: pressed)
    }
}

/// Implicit animation bound to `value`, self-disabling under Reduce Motion.
private struct MotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduce), value: value)
    }
}

/// Fade + gentle rise as the view first appears, self-disabling under Reduce Motion.
private struct AppearTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                if reduce { shown = true }
                else { withAnimation(Motion.appear) { shown = true } }
            }
    }
}

extension View {
    func pressScale(_ pressed: Bool) -> some View { modifier(PressScale(pressed: pressed)) }
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
    func appearTransition() -> some View { modifier(AppearTransition()) }
}
