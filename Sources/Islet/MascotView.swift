import AppKit
import SwiftUI

final class MascotModel: ObservableObject {
    @Published var action: CatAction = .idle
    @Published var facing: CatFacing = .east
    @Published var actionEpoch = Date()
    @Published var hovered = false
}

struct MascotView: View {
    @ObservedObject var model: MascotModel

    var body: some View {
        CatSpriteView(model: model)
            .frame(width: 48, height: 48)
    }
}

private struct CatSpriteView: View {
    @ObservedObject var model: MascotModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let elapsed = timeline.date.timeIntervalSince(model.actionEpoch)
            let frames = CatSpriteLibrary.shared.frames(for: model.action, facing: model.facing)
            let count = max(frames.count, 1)
            let rawIndex = Int(elapsed * model.action.fps)
            let index = model.action.loops ? rawIndex % count : min(count - 1, rawIndex)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 22, height: 3)
                    .blur(radius: 2)
                    .offset(y: 22)

                if frames.indices.contains(index) {
                    Image(nsImage: frames[index])
                        .interpolation(.none)
                        .frame(width: 48, height: 48)
                        .scaleEffect(breathScale(time: time), anchor: .bottom)
                }

                overlays(time: time)
            }
            .frame(width: 48, height: 48)
            .shadow(color: .white.opacity(model.hovered ? 0.22 : 0), radius: 5)
        }
    }

    private func breathScale(time: TimeInterval) -> CGFloat {
        switch model.action {
        case .idle, .sit:
            return 1 + sin(time * 1.8) * 0.012
        case .sleep, .flat:
            return 1 + sin(time * 1.1) * 0.01
        default:
            return 1
        }
    }

    @ViewBuilder
    private func overlays(time: TimeInterval) -> some View {
        if model.action == .sleep {
            ForEach(0..<3, id: \.self) { index in
                Text("z")
                    .font(.system(size: CGFloat(5 + index), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .offset(
                        x: 10 + CGFloat(index) * 4,
                        y: -10 - CGFloat(index) * 4 - CGFloat(sin(time * 2 + Double(index))) * 1.5
                    )
            }
        }

        if model.action == .love || model.action == .greet {
            Image(systemName: "heart.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.62))
                .offset(x: 9, y: -12 - CGFloat(sin(time * 3.0)) * 2)
                .opacity(0.9)
        }

        if model.action == .play || model.action == .chase {
            Image(systemName: "sparkle")
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .offset(x: -10, y: -10 - CGFloat(sin(time * 4.0)) * 2)
        }
    }
}
