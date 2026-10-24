import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.35))
                .frame(width: 214, height: 10)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 190, height: 4)

                Capsule()
                    .fill(neonGradient)
                    .frame(width: max(3, 190 * fill), height: 4)
                    .shadow(color: neon.opacity(0.9), radius: 5)
                    .shadow(color: neon.opacity(0.4), radius: 11)
            }
            .frame(width: 190, height: 4)
        }
        .frame(width: 240, height: 24)
        .opacity(state.visible ? 1 : 0)
        .scaleEffect(state.visible ? 1 : 0.94)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: state.value)
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

    private var fill: Double {
        if state.muted {
            return 0.16
        }
        return min(max(state.value, 0), 1)
    }

    private var neonGradient: LinearGradient {
        LinearGradient(
            colors: [neon.opacity(0.55), neon, .white.opacity(0.9)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
