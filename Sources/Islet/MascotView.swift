import Combine
import SwiftUI

enum MascotMood: Equatable {
    case idle
    case playing
    case expanded
    case sleeping
}

final class MascotModel: ObservableObject {
    @Published var mood: MascotMood = .idle
    @Published var blink = false
    @Published var hop = false
    @Published var look: CGFloat = 0
}

struct MascotView: View {
    @ObservedObject var model: MascotModel
    @State private var tailUp = false
    @State private var bob = false

    private let cream = Color(red: 0.97, green: 0.84, blue: 0.66)
    private let orange = Color(red: 0.92, green: 0.58, blue: 0.28)
    private let pink = Color(red: 0.95, green: 0.62, blue: 0.64)
    private let dark = Color.black.opacity(0.55)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: 16, height: 3.5)
                .blur(radius: 1.5)
                .offset(y: 11)

            Capsule()
                .fill(orange)
                .frame(width: 2.5, height: 10)
                .rotationEffect(.degrees(tailUp ? 24 : -12), anchor: .bottom)
                .offset(x: 8, y: 5)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(cream)
                .frame(width: 14, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(dark.opacity(0.35), lineWidth: 0.6)
                )
                .offset(y: 3)

            HStack(spacing: 3) {
                Capsule().fill(orange).frame(width: 3.5, height: 2)
                Capsule().fill(orange).frame(width: 3.5, height: 2)
            }
            .offset(y: 9)

            ZStack {
                Triangle()
                    .fill(orange)
                    .frame(width: 5, height: 5)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -4.5, y: -8)

                Triangle()
                    .fill(orange)
                    .frame(width: 5, height: 5)
                    .rotationEffect(.degrees(12))
                    .offset(x: 4.5, y: -8)

                Circle()
                    .fill(cream)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(dark.opacity(0.35), lineWidth: 0.6))

                HStack(spacing: 3.5) {
                    eye
                    eye
                }
                .offset(y: -1)

                Circle()
                    .fill(pink)
                    .frame(width: 1.8, height: 1.4)
                    .offset(y: 3)
            }
            .offset(y: -5)

            if model.mood == .sleeping {
                Text("z")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .offset(x: 9, y: -12)
            }
        }
        .frame(width: 24, height: 24)
        .offset(y: model.hop ? -4 : (bob ? -0.8 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.hop)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bob)
        .animation(.easeInOut(duration: tailDuration).repeatForever(autoreverses: true), value: tailUp)
        .onAppear {
            tailUp = true
            bob = true
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .frame(width: 34, height: 34)
    }

    private var eye: some View {
        Ellipse()
            .fill(Color.black.opacity(0.85))
            .frame(width: 2, height: model.blink || model.mood == .sleeping ? 0.4 : 2.6)
            .offset(x: model.look)
    }

    private var tailDuration: Double {
        switch model.mood {
        case .playing: return 0.8
        case .sleeping: return 2.2
        default: return 1.4
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
