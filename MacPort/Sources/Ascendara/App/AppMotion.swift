import SwiftUI

enum AppMotion {
    static let Quick = Animation.easeOut(duration: 0.14)
    static let Standard = Animation.easeInOut(duration: 0.22)
    static let Spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
}

private struct MotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var MotionEnabled: Bool {
        get { self[MotionEnabledKey.self] }
        set { self[MotionEnabledKey.self] = newValue }
    }
}

struct MotionScope: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var SystemReduceMotion
    let ReduceMotion: Bool

    func body(content: Content) -> some View {
        let Enabled = !ReduceMotion && !SystemReduceMotion
        content.environment(\.MotionEnabled, Enabled)
    }
}

private struct MotionAnimationModifier<Observed: Equatable>: ViewModifier {
    @Environment(\.MotionEnabled) private var Enabled
    let Value: Observed
    let Animation: Animation

    func body(content: Content) -> some View {
        content.animation(Enabled ? Animation : nil, value: Value)
    }
}

private struct MotionTransitionModifier: ViewModifier {
    @Environment(\.MotionEnabled) private var Enabled
    let Distance: CGFloat

    func body(content: Content) -> some View {
        content.transition(Enabled ? .asymmetric(
            insertion: .opacity.combined(with: .offset(y: Distance)),
            removal: .opacity
        ) : .identity)
    }
}

private struct ButtonFeedbackModifier: ViewModifier {
    @Environment(\.MotionEnabled) private var Enabled
    @Environment(\.isEnabled) private var IsEnabled
    @State private var Hovered = false
    let Pressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(Enabled && IsEnabled && Pressed ? 0.97 : 1)
            .offset(y: Enabled && IsEnabled && Hovered && !Pressed ? -1 : 0)
            .opacity(IsEnabled ? 1 : 0.5)
            .onHover { Hovered = $0 }
            .MotionAnimation(Hovered, Animation: AppMotion.Quick)
            .MotionAnimation(Pressed, Animation: AppMotion.Quick)
    }
}

struct MotionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.ButtonFeedback(Pressed: configuration.isPressed)
    }
}

extension View {
    func MotionAnimation<Observed: Equatable>(_ Value: Observed, Animation: Animation = AppMotion.Standard) -> some View {
        modifier(MotionAnimationModifier(Value: Value, Animation: Animation))
    }

    func MotionTransition(Distance: CGFloat = 8) -> some View {
        modifier(MotionTransitionModifier(Distance: Distance))
    }

    func ButtonFeedback(Pressed: Bool) -> some View {
        modifier(ButtonFeedbackModifier(Pressed: Pressed))
    }
}
