import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var multiMedia: MultiMediaService

    var body: some View {
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: state.expanded ? 26 : 10)
                .fill(Color.black)
                .overlay(
                    IslandShape(bottomRadius: state.expanded ? 26 : 10)
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
                ExpandedContent(
                    notchHeight: state.notchHeight,
                    state: state,
                    media: media,
                    audio: audio,
                    calendar: calendar,
                    multiMedia: multiMedia
                )
                .transition(.identity)
            } else {
                CollapsedMediaView(media: media, calendar: calendar, notchWidth: state.notchWidth)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .animation(.timingCurve(0.2, 0.9, 0.25, 1.0, duration: 0.16), value: state.expanded)
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
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var multiMedia: MultiMediaService

    @State private var hoveredModule: IslandModule?

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: notchHeight)
                .padding(.bottom, 8)

            Group {
                switch state.activeModule {
                case .media:
                    MediaModuleView(media: media, audio: audio, multi: multiMedia)
                case .calendar:
                    CalendarModuleView(calendar: calendar)
                }
            }
            .transition(.opacity)
            .animation(.easeOut(duration: 0.16), value: state.activeModule)

            Spacer(minLength: 8)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 10)
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
            HStack(spacing: 5) {
                if state.activeModule == .media, let icon = media.sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(headerLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.28))
                    .lineLimit(1)
            }
        }
    }

    private var headerLabel: String {
        if state.activeModule == .media, !media.sourceName.isEmpty {
            return media.sourceName.uppercased()
        }
        return state.activeModule.title.uppercased()
    }

    private var footer: some View {
        HStack(spacing: 4) {
            ForEach(IslandModule.allCases, id: \.self) { module in
                let active = state.activeModule == module
                let hovered = hoveredModule == module

                Button {
                    Haptics.select()
                    state.activeModule = module
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: module.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(module.title.lowercased())
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(active ? 0.8 : (hovered ? 0.5 : 0.22)))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(active ? 0.08 : (hovered ? 0.035 : 0)))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredModule = isHovering ? module : nil
                }
            }
            Spacer()
        }
    }
}

private struct CollapsedMediaView: View {
    @ObservedObject var media: MediaService
    @ObservedObject var calendar: CalendarService
    let notchWidth: CGFloat

    private let wingWidth: CGFloat = 28

    private var showMedia: Bool { media.isPlaying }
    private var showCalendar: Bool {
        !showMedia && calendar.hasCollapsedEvent && calendar.nextEvent != nil
    }
    private var visible: Bool { showMedia || showCalendar }

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wingWidth)

            Color.clear
                .frame(width: notchWidth)

            rightWing
                .frame(width: wingWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: visible)
    }

    @ViewBuilder
    private var leftWing: some View {
        if showMedia {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else if showCalendar {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if showMedia {
            Image(systemName: media.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        } else if let next = calendar.nextEvent, showCalendar {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(countdown(for: next, now: context.date))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func countdown(for event: CalendarService.Event, now: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let eventDay = calendar.startOfDay(for: event.start)
        let dayDelta = calendar.dateComponents([.day], from: today, to: eventDay).day ?? 0

        if event.isAllDay {
            if dayDelta <= 0 { return "Today" }
            if dayDelta == 1 { return "1d" }
            return "\(dayDelta)d"
        }

        if event.start <= now && event.end > now {
            return "Now"
        }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 1 {
            return "Now"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }
        return "\(max(1, dayDelta))d"
    }
}

// MARK: - Media

private struct MediaModuleView: View {
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService
    @ObservedObject var multi: MultiMediaService

    var body: some View {
        VStack(spacing: 8) {
            if multi.sources.isEmpty || singleSource != nil {
                singleMediaCard(singleSource)
            } else {
                clientList
            }
            outputBar
        }
    }

    /// One client (or one actively playing client) gets the large card.
    /// Two or more simultaneously playing clients get the compact list.
    private var singleSource: MultiMediaService.Source? {
        let playing = multi.sources.filter { $0.client.isPlaying }
        if playing.count <= 1 {
            return playing.first ?? multi.sources.first
        }
        return nil
    }

    private func singleMediaCard(_ source: MultiMediaService.Source?) -> some View {
        let active = source == nil || media.sourceBundleID.isEmpty || source?.client.bundle == media.sourceBundleID
        let title = active && !media.title.isEmpty ? media.title : (source?.client.title ?? media.title)
        let artist = active && !media.artist.isEmpty ? media.artist : (source?.client.artist ?? media.artist)
        let album = active && !media.album.isEmpty ? media.album : (source?.client.album ?? media.album)
        let artwork = active
            ? (media.artwork ?? source?.artwork ?? source?.appIcon)
            : (source?.artwork ?? source?.appIcon)
        let playing = active ? media.isPlaying : (source?.client.isPlaying ?? false)
        let duration = active ? media.duration : (source?.client.duration ?? 0)
        let elapsed = active ? media.elapsed : (source?.client.elapsed ?? 0)
        let hasTrack = !title.isEmpty
        let accent = Color(nsColor: media.accentColor)
        let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

        return ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.25), .black.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.22), .black.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Circle()
                .fill(accent.opacity(0.28))
                .frame(width: 190, height: 190)
                .blur(radius: 45)
                .offset(x: -170, y: 40)

            HStack(spacing: 16) {
                singleArtwork(artwork, accent: accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(hasTrack ? title : "Nothing playing")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(hasTrack ? 0.96 : 0.7))
                        .lineLimit(1)

                    Text(hasTrack ? artist : "Music, Spotify, Firefox, or a browser tab")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)

                    if hasTrack, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if duration > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                Capsule()
                                    .fill(accent)
                                    .frame(width: max(2, geo.size.width * progress))
                            }
                        }
                        .frame(height: 3)

                        HStack {
                            Text(timeString(elapsed))
                            Spacer()
                            Text(timeString(duration))
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    }

                    Spacer(minLength: 2)

                    singleControls(hasTrack: hasTrack, playing: playing, active: active)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(16)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(hasTrack ? 0.22 : 0.08), lineWidth: 1)
        )
    }

    private func singleArtwork(_ image: NSImage?, accent: Color) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.35), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                )
            }
        }
        .frame(width: 124, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.45), radius: 18, y: 6)
    }

    private func singleControls(hasTrack: Bool, playing: Bool, active: Bool) -> some View {
        HStack(spacing: 20) {
            Button {
                Haptics.select()
                if active { media.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.select()
                if active { media.togglePlayPause() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: playing ? 0 : 1)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.select()
                if active { media.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .disabled(!active || !hasTrack)
        .opacity(active && hasTrack ? 1 : 0.3)
    }

    // MARK: Audio output

    private var currentSymbol: String {
        audio.outputs.first(where: { $0.id == audio.currentOutputID })?.symbol ?? "hifispeaker.fill"
    }

    private var outputBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(audio.outputs) { device in
                    Button {
                        audio.setOutput(device)
                    } label: {
                        Label(
                            device.name,
                            systemImage: device.id == audio.currentOutputID ? "checkmark" : device.symbol
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentSymbol)
                        .font(.system(size: 10, weight: .medium))
                    Text(audio.currentOutputName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 150, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 8)

            Image(systemName: audio.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            Slider(
                value: Binding(
                    get: { audio.volume },
                    set: { audio.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(.white.opacity(0.8))
            .frame(width: 90)
        }
        .frame(height: 24)
    }

    // MARK: Multi-media list

    private var clientList: some View {
        VStack(spacing: 5) {
            ForEach(multi.sources) { source in
                clientRow(source)
            }
        }
    }

    private func clientRow(_ source: MultiMediaService.Source) -> some View {
        let client = source.client
        let active = client.bundle == media.sourceBundleID
        let playing = active ? media.isPlaying : client.isPlaying
        let duration = active ? media.duration : (client.duration ?? 0)
        let elapsed = active ? media.elapsed : (client.elapsed ?? 0)
        let progress = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        let title = (client.title?.isEmpty == false ? client.title : nil) ?? source.appName
        let artist = (client.artist?.isEmpty == false ? client.artist : nil) ?? source.appName

        return HStack(spacing: 10) {
            clientArtwork(source, active: active)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if playing {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(artist)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)

                    if duration > 0 {
                        Text("· \(timeString(elapsed))/\(timeString(duration))")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }

                if duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: max(2, geo.size.width * progress))
                        }
                    }
                    .frame(height: 2)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 4)

            clientControls(source, playing: playing, active: active)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(active ? 0.075 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(active ? 0.13 : 0.05), lineWidth: 1)
        )
        .help(active ? "" : "macOS only allows transport control for the active player")
    }

    private func clientArtwork(_ source: MultiMediaService.Source, active: Bool) -> some View {
        Group {
            if active, let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let artwork = source.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let icon = source.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 36, height: 36)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func clientControls(_ source: MultiMediaService.Source, playing: Bool, active: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                if active { media.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!active)
            .opacity(active ? 1 : 0.25)

            Button {
                if active { media.togglePlayPause() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: playing ? 0 : 0.5)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!active)
            .opacity(active ? 1 : 0.25)

            Button {
                if active { media.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!active)
            .opacity(active ? 1 : 0.25)
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
