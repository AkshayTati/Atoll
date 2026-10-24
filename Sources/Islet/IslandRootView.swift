import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService
    @ObservedObject var calendar: CalendarService

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
                    calendar: calendar
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            } else {
                CollapsedMediaView(media: media, notchWidth: state.notchWidth)
                    .transition(.opacity)
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
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService
    @ObservedObject var calendar: CalendarService

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 10)

            Group {
                switch state.activeModule {
                case .media:
                    MediaModuleView(media: media, audio: audio)
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
        .padding(.top, notchHeight + 10)
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
                Button {
                    state.activeModule = module
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: module.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(module.title.lowercased())
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(state.activeModule == module ? 0.8 : 0.22))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(state.activeModule == module ? 0.08 : 0))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

private struct CollapsedMediaView: View {
    @ObservedObject var media: MediaService
    let notchWidth: CGFloat

    private let wingWidth: CGFloat = 28

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
        .opacity(media.hasTrack ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: media.hasTrack)
    }

    private var leftWing: some View {
        Group {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rightWing: some View {
        Image(systemName: media.isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Media

private struct MediaModuleView: View {
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService

    var body: some View {
        VStack(spacing: 8) {
            mediaCard
            outputBar
            sourcesStrip
        }
    }

    private var mediaCard: some View {
        HStack(alignment: .center, spacing: 16) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(media.hasTrack ? media.title : "Nothing playing")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(media.hasTrack ? 0.95 : 0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(media.hasTrack ? media.artist : "Music, Spotify, Firefox, or a browser tab")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if media.duration > 0 {
                    progressBar

                    HStack {
                        Text(timeString(media.elapsed))
                        Spacer()
                        Text(timeString(media.duration))
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 1)
                }

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

    // MARK: Sources

    @ViewBuilder
    private var sourcesStrip: some View {
        let items = Array(displaySources.prefix(8))
        if !items.isEmpty {
            HStack(spacing: 7) {
                Text("AUDIO")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.22))

                ForEach(items) { source in
                    sourceIcon(source)
                }

                Spacer(minLength: 0)
            }
            .frame(height: 20)
        }
    }

    private var displaySources: [AudioService.Source] {
        var list = audio.sources
        if !media.sourceBundleID.isEmpty,
           !list.contains(where: { $0.bundleID == media.sourceBundleID }) {
            list.insert(
                AudioService.Source(
                    id: media.sourceBundleID,
                    pid: 0,
                    name: media.sourceName.isEmpty ? media.sourceBundleID : media.sourceName,
                    icon: media.sourceIcon
                ),
                at: 0
            )
        }
        return list
    }

    private func sourceIcon(_ source: AudioService.Source) -> some View {
        let active = source.bundleID == media.sourceBundleID
        let producing = audio.sources.contains(where: { $0.bundleID == source.bundleID })

        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = source.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(active ? 0.55 : 0.12), lineWidth: 1)
            )

            Circle()
                .fill(producing ? Color.green : Color.white.opacity(0.25))
                .frame(width: 4, height: 4)
                .offset(x: 1, y: 1)
        }
        .frame(width: 20, height: 20)
        .help(source.name)
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Calendar

private struct CalendarModuleView: View {
    @ObservedObject var calendar: CalendarService

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        Group {
            switch calendar.status {
            case .notDetermined:
                connectCard
            case .denied, .restricted, .writeOnly:
                deniedCard
            case .fullAccess, .authorized:
                agenda
            @unknown default:
                connectCard
            }
        }
    }

    private var connectCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("Connect your calendar")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text("Shows the next events from calendars already in Calendar.app.")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
            Button(action: calendar.requestAccess) {
                Text(calendar.loading ? "Requesting…" : "Allow access")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .disabled(calendar.loading)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(cardBackground)
    }

    private var deniedCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("Calendar access is off")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text("Allow Islet under Privacy & Security › Calendars.")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
            Button(action: openCalendarSettings) {
                Text("Open Settings")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(cardBackground)
    }

    private var agenda: some View {
        VStack(spacing: 6) {
            if calendar.events.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(cardBackground)
            } else {
                ForEach(calendar.events) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: CalendarService.Event) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(subtitle(for: event))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let url = event.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Join meeting")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    private func subtitle(for event: CalendarService.Event) -> String {
        let day: String
        if Calendar.current.isDateInToday(event.start) {
            day = "Today"
        } else if Calendar.current.isDateInTomorrow(event.start) {
            day = "Tomorrow"
        } else {
            day = Self.weekdayFormatter.string(from: event.start)
        }

        let time = event.isAllDay ? "All day" : Self.timeFormatter.string(from: event.start)
        var parts = [day, time]
        if !event.calendarTitle.isEmpty {
            parts.append(event.calendarTitle)
        }
        return parts.joined(separator: " · ")
    }

    private func openCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
