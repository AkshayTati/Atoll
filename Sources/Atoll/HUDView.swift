import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState

    private let segmentCount = 16

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(neon)
                .frame(width: 16)

            segments

            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                )
        )
        .shadow(color: neon.opacity(0.28), radius: 8)
        .opacity(state.visible ? 1 : 0)
        .scaleEffect(state.visible ? 1 : 0.96)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.value)
        .animation(.easeOut(duration: 0.12), value: state.visible)
    }

    private var displayValue: Double {
        state.muted ? 0 : min(max(state.value, 0), 1)
    }

    private var label: String {
        if state.muted { return "Mute" }
        return "\(Int(round(state.value * 100)))%"
    }

    private var iconName: String {
        if state.muted { return "speaker.slash.fill" }

        if state.kind == .volume {
            if state.value <= 0.001 { return "speaker.fill" }
            if state.value < 0.34 { return "speaker.wave.1.fill" }
            if state.value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
        return "sun.max.fill"
    }

    private var segments: some View {
        let level = displayValue * Double(segmentCount)

        return HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let fill = min(max(level - Double(index), 0), 1)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(neon.opacity(0.12 + 0.83 * fill))
                    .frame(width: 7.5, height: 8)
                    .shadow(color: neon.opacity(fill > 0 ? 0.4 : 0), radius: 2)
            }
        }
        .frame(width: 150, height: 8)
    }

    private var neon: Color {
        if state.muted {
            return Color(red: 1.0, green: 0.22, blue: 0.28)
        }
        return state.kind == .volume
            ? Color(red: 0.12, green: 0.85, blue: 1.0)
            : Color(red: 1.0, green: 0.7, blue: 0.2)
    }
}
