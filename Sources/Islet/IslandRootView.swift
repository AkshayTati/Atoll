import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaService

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
                ExpandedContent(notchHeight: state.notchHeight, media: media)
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
    @ObservedObject var media: MediaService

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 10)

            MediaModuleView(media: media)

            Spacer(minLength: 8)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, notchHeight + 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(media.isPlaying ? Color.green : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
                Text("ISLET")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text("MEDIA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            footerTab("media", icon: "play.circle.fill", active: true)
            footerTab("sound", icon: "speaker.wave.2.fill", active: false)
            footerTab("calendar", icon: "calendar", active: false)
        }
    }

    private func footerTab(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(active ? 0.7 : 0.2))
    }
}

private struct MediaModuleView: View {
    @ObservedObject var media: MediaService

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(media.hasTrack ? media.title : "Nothing playing")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(media.hasTrack ? 0.95 : 0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(media.hasTrack ? media.artist : "Music, Spotify, or a browser tab")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                progressBar

                HStack {
                    Text(timeString(media.elapsed))
                    Spacer()
                    Text(timeString(media.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 1)

                Spacer(minLength: 2)

                controls
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var artwork: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [.white.opacity(0.12), .white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                )
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: max(2, geo.size.width * media.progress))
            }
        }
        .frame(height: 3)
    }

    private var controls: some View {
        HStack(spacing: 22) {
            Button(action: media.previous) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(media.hasTrack ? 0.8 : 0.25))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!media.hasTrack)

            Button(action: media.togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(media.hasTrack ? 0.92 : 0.2))
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(media.hasTrack ? Color.black : Color.white.opacity(0.3))
                        .offset(x: media.isPlaying ? 0 : 1)
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!media.hasTrack)

            Button(action: media.next) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(media.hasTrack ? 0.8 : 0.25))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!media.hasTrack)
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
