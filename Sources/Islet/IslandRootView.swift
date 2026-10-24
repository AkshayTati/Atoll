import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaService
    @ObservedObject var audio: AudioService
    @ObservedObject var calendar: CalendarService

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
                ExpandedContent(
                    notchHeight: state.notchHeight,
                    state: state,
                    media: media,
                    audio: audio,
                    calendar: calendar
                )
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
                    MediaModuleView(media: media)
                case .sound:
                    SoundModuleView(audio: audio)
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
                if let icon = media.sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(media.sourceName.isEmpty ? state.activeModule.title.uppercased() : media.sourceName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.28))
                    .lineLimit(1)
            }
        }
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

// MARK: - Media

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

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Sound

private struct SoundModuleView: View {
    @ObservedObject var audio: AudioService

    private var currentSymbol: String {
        audio.outputs.first(where: { $0.id == audio.currentOutputID })?.symbol ?? "hifispeaker.fill"
    }

    var body: some View {
        VStack(spacing: 9) {
            currentCard
            deviceGrid
        }
    }

    private var currentCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 38, height: 38)
                Image(systemName: currentSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(audio.currentOutputName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text("OUTPUT")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Image(systemName: audio.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Slider(
                    value: Binding(
                        get: { audio.volume },
                        set: { audio.setVolume($0) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .tint(.white.opacity(0.85))
                .frame(width: 128)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var deviceGrid: some View {
        Group {
            if audio.outputs.isEmpty {
                Text("No output devices")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(Array(audio.outputs.prefix(6))) { device in
                        deviceButton(device)
                    }
                }
            }
        }
    }

    private func deviceButton(_ device: AudioService.Device) -> some View {
        let active = device.id == audio.currentOutputID
        return Button {
            audio.setOutput(device)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: device.symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(device.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(active ? 0.9 : 0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(active ? 0.1 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(active ? 0.16 : 0.05), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
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
