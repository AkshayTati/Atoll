import Combine
import SwiftUI

enum MascotMood: Equatable {
    case idle
    case playing
    case expanded
    case sleeping
}

enum MascotAction: Equatable {
    case walk
    case sit
    case sleep
    case groom
    case peek
}

final class MascotModel: ObservableObject {
    @Published var mood: MascotMood = .idle
    @Published var action: MascotAction = .sit
    @Published var blink = false
    @Published var hop = false
    @Published var look: CGFloat = 0
    @Published var direction: CGFloat = 1
    @Published var peekOffset: CGFloat = 0
}

struct MascotView: View {
    @ObservedObject var model: MascotModel

    var body: some View {
        ZStack {
            if model.action == .peek {
                PeekCatView(model: model)
            } else {
                CatBodyView(model: model)
            }

            if model.action == .sleep {
                Text("z")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .offset(x: 10, y: -10)
            }
        }
        .frame(width: 34, height: 34)
        .offset(y: model.hop ? -5 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.hop)
    }
}

// MARK: - Full body

private struct CatBodyView: View {
    @ObservedObject var model: MascotModel

    private let cream = Color(red: 0.97, green: 0.84, blue: 0.66)
    private let orange = Color(red: 0.92, green: 0.58, blue: 0.28)
    private let pink = Color(red: 0.95, green: 0.62, blue: 0.64)
    private let dark = Color.black.opacity(0.55)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                draw(context: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 34, height: 34)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let flip = model.direction < 0
        context.translateBy(x: flip ? size.width : 0, y: 0)
        context.scaleBy(x: flip ? -1 : 1, y: 1)

        if model.action == .sleep {
            drawSleeping(context: &context)
            return
        }

        let action = model.action
        let walking = action == .walk
        let sitting = action == .sit || action == .groom
        let phase = time * 6.0
        let bob = walking ? sin(phase * 2) * 0.6 : 0
        let bodyY = 20.0 + bob + (sitting ? 1.0 : 0)
        let headY = bodyY - 8.0 + (action == .groom ? 2.5 : 0)

        // Tail, attached at the rear haunch and drawn behind the body.
        let sway = sin(time * (walking ? 3.0 : 1.4)) * 1.6
        var tail = Path()
        tail.move(to: CGPoint(x: 8, y: bodyY + 1))
        tail.addCurve(
            to: CGPoint(x: 2 + sway, y: 8 + bob),
            control1: CGPoint(x: 1, y: bodyY - 2),
            control2: CGPoint(x: sway, y: 13 + bob)
        )
        context.stroke(tail, with: .color(dark), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
        context.stroke(tail, with: .color(orange), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))

        // Legs behind the body.
        let angles: [CGFloat] = walking
            ? [
                sin(phase) * 0.4,
                sin(phase + 0.5) * 0.4,
                sin(phase + .pi) * 0.4,
                sin(phase + .pi + 0.5) * 0.4
            ]
            : [0, 0, 0, 0]
        let hips: [CGPoint] = [
            CGPoint(x: 11, y: bodyY + 5),
            CGPoint(x: 15, y: bodyY + 5),
            CGPoint(x: 20, y: bodyY + 5),
            CGPoint(x: 24, y: bodyY + 5)
        ]
        for (index, hip) in hips.enumerated() {
            let length: CGFloat = (sitting && index < 2) ? 3.2 : 6.0
            drawLeg(context: &context, hip: hip, angle: angles[index], length: length)
        }

        // Body.
        let bodyRect = CGRect(x: 7, y: bodyY - 6, width: 18, height: 12)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 6)
        context.fill(bodyPath, with: .color(cream))
        context.stroke(bodyPath, with: .color(dark), lineWidth: 0.8)

        // Ears.
        drawEar(
            context: &context,
            tip: CGPoint(x: 20, y: headY - 11),
            left: CGPoint(x: 18, y: headY - 4),
            right: CGPoint(x: 24, y: headY - 7)
        )
        drawEar(
            context: &context,
            tip: CGPoint(x: 27, y: headY - 11),
            left: CGPoint(x: 25, y: headY - 4),
            right: CGPoint(x: 31, y: headY - 7)
        )

        // Head.
        let headRect = CGRect(x: 18, y: headY - 8, width: 15, height: 14)
        let headPath = Path(ellipseIn: headRect)
        context.fill(headPath, with: .color(cream))
        context.stroke(headPath, with: .color(dark), lineWidth: 0.8)

        // Face.
        let eyeHeight: CGFloat = model.blink ? 0.5 : 2.4
        let look = model.look * 0.8
        context.fill(
            Path(ellipseIn: CGRect(x: 22 + look, y: headY - 3, width: 1.8, height: eyeHeight)),
            with: .color(.black.opacity(0.85))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: 27 + look, y: headY - 3, width: 1.8, height: eyeHeight)),
            with: .color(.black.opacity(0.85))
        )

        var nose = Path()
        nose.move(to: CGPoint(x: 25, y: headY + 1))
        nose.addLine(to: CGPoint(x: 24, y: headY + 2.5))
        nose.addLine(to: CGPoint(x: 26, y: headY + 2.5))
        nose.closeSubpath()
        context.fill(nose, with: .color(pink))

        for offset in [-1.5, 1.5] {
            var whisker = Path()
            whisker.move(to: CGPoint(x: 26, y: headY + 2))
            whisker.addLine(to: CGPoint(x: 32, y: headY + 2 + offset))
            context.stroke(whisker, with: .color(dark.opacity(0.35)), lineWidth: 0.4)
        }

        if action == .groom {
            var paw = Path()
            paw.move(to: CGPoint(x: 22, y: bodyY + 2))
            paw.addLine(to: CGPoint(x: 24, y: headY + 4))
            context.stroke(paw, with: .color(dark), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
            context.stroke(paw, with: .color(orange), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }

    private func drawLeg(context: inout GraphicsContext, hip: CGPoint, angle: CGFloat, length: CGFloat) {
        let end = CGPoint(x: hip.x + sin(angle) * length, y: hip.y + cos(angle) * length)
        var leg = Path()
        leg.move(to: hip)
        leg.addLine(to: end)
        context.stroke(leg, with: .color(dark), style: StrokeStyle(lineWidth: 4.0, lineCap: .round))
        context.stroke(leg, with: .color(orange), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }

    private func drawEar(context: inout GraphicsContext, tip: CGPoint, left: CGPoint, right: CGPoint) {
        var ear = Path()
        ear.move(to: tip)
        ear.addLine(to: left)
        ear.addLine(to: right)
        ear.closeSubpath()
        context.fill(ear, with: .color(orange))
        context.stroke(ear, with: .color(dark), lineWidth: 0.6)
    }

    private func drawSleeping(context: inout GraphicsContext) {
        let body = Path(ellipseIn: CGRect(x: 6, y: 18, width: 22, height: 11))
        context.fill(body, with: .color(cream))
        context.stroke(body, with: .color(dark), lineWidth: 0.8)

        var tail = Path()
        tail.move(to: CGPoint(x: 8, y: 25))
        tail.addCurve(
            to: CGPoint(x: 27, y: 26),
            control1: CGPoint(x: 10, y: 32),
            control2: CGPoint(x: 25, y: 31)
        )
        context.stroke(tail, with: .color(dark), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
        context.stroke(tail, with: .color(orange), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))

        drawEar(
            context: &context,
            tip: CGPoint(x: 9, y: 14),
            left: CGPoint(x: 7, y: 20),
            right: CGPoint(x: 12, y: 18)
        )
        drawEar(
            context: &context,
            tip: CGPoint(x: 15, y: 14),
            left: CGPoint(x: 13, y: 18),
            right: CGPoint(x: 18, y: 20)
        )

        let head = Path(ellipseIn: CGRect(x: 7, y: 17, width: 12, height: 11))
        context.fill(head, with: .color(cream))
        context.stroke(head, with: .color(dark), lineWidth: 0.8)

        for x in [10.5, 14.0] {
            var eye = Path()
            eye.move(to: CGPoint(x: x, y: 22))
            eye.addLine(to: CGPoint(x: x + 2, y: 22))
            context.stroke(eye, with: .color(dark), lineWidth: 0.8)
        }

        var nose = Path()
        nose.move(to: CGPoint(x: 13, y: 24))
        nose.addLine(to: CGPoint(x: 12.5, y: 25))
        nose.addLine(to: CGPoint(x: 13.5, y: 25))
        nose.closeSubpath()
        context.fill(nose, with: .color(pink))
    }
}

// MARK: - Peek-a-boo head

private struct PeekCatView: View {
    @ObservedObject var model: MascotModel

    private let cream = Color(red: 0.97, green: 0.84, blue: 0.66)
    private let orange = Color(red: 0.92, green: 0.58, blue: 0.28)
    private let pink = Color(red: 0.95, green: 0.62, blue: 0.64)
    private let dark = Color.black.opacity(0.55)

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                paw
                paw
            }
            .offset(y: -10)

            ZStack {
                Triangle()
                    .fill(orange)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -6, y: -10)

                Triangle()
                    .fill(orange)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(10))
                    .offset(x: 6, y: -10)

                Circle()
                    .fill(cream)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(dark.opacity(0.4), lineWidth: 0.8))

                HStack(spacing: 5) {
                    eye
                    eye
                }
                .offset(y: -1)

                Circle()
                    .fill(pink)
                    .frame(width: 2.2, height: 1.6)
                    .offset(y: 3)
            }
            .offset(y: 3 + model.peekOffset)
        }
        .frame(width: 34, height: 34)
        .offset(y: model.hop ? -3 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.peekOffset)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.hop)
    }

    private var paw: some View {
        Capsule()
            .fill(orange)
            .frame(width: 6, height: 3.5)
            .overlay(Capsule().stroke(dark.opacity(0.3), lineWidth: 0.5))
    }

    private var eye: some View {
        Ellipse()
            .fill(Color.black.opacity(0.85))
            .frame(width: 2.2, height: model.blink ? 0.5 : 2.8)
            .offset(x: model.look)
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
