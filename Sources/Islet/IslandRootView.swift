import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState

    var body: some View {
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: state.expanded ? 26 : 14)
                .fill(Color.black)
                .overlay(
                    IslandShape(bottomRadius: state.expanded ? 26 : 14)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                        .opacity(state.expanded ? 1 : 0)
                )

            if state.expanded {
                ExpandedContent(notchHeight: state.notchHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.32), value: state.expanded)
    }
}

struct IslandShape: Shape, InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct ExpandedContent: View {
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("ISLET")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Text("phase 0")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }

            HStack(spacing: 10) {
                ModuleCard(icon: "play.circle.fill", title: "Media", subtitle: "next")
                ModuleCard(icon: "speaker.wave.2.fill", title: "Sound", subtitle: "next")
                ModuleCard(icon: "calendar", title: "Calendar", subtitle: "next")
            }

            Spacer(minLength: 0)

            Text("shell is alive")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 18)
        .padding(.top, notchHeight + 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ModuleCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
