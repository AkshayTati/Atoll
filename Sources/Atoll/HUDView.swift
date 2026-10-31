import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        Capsule()
            .fill(neonGradient)
            .frame(width: lineWidth, height: 2.5)
            .shadow(color: neon.opacity(0.9), radius: 4)
            .shadow(color: neon.opacity(0.35), radius: 10)
            .frame(width: 200, height: 20)
            .opacity(state.visible ? 1 : 0)
            .scaleEffect(state.visible ? 1 : 0.96)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.value)
            .animation(.easeOut(duration: 0.12), value: state.visible)
    }

    private var neon: Color {
        if state.muted {
            return Color(red: 1.0, green: 0.22, blue: 0.28)
        }
        return state.kind == .volume
            ? Color(red: 0.12, green: 0.85, blue: 1.0)
            : Color(red: 1.0, green: 0.7, blue: 0.2)
    }

    private var lineWidth: CGFloat {
        if state.muted {
            return 42
        }
        let width = 150.0 * min(max(state.value, 0), 1)
        return CGFloat(max(10, width))
    }

    private var neonGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: neon.opacity(0), location: 0.0),
                .init(color: neon.opacity(0.75), location: 0.12),
                .init(color: .white.opacity(0.95), location: 0.5),
                .init(color: neon.opacity(0.75), location: 0.88),
                .init(color: neon.opacity(0), location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
