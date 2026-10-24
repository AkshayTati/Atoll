import AppKit
import SwiftUI

struct CalendarModuleView: View {
    @ObservedObject var calendar: CalendarService
    @State private var selectedEvent: CalendarService.Event?
    @State private var hoveredEventID: String?

    var body: some View {
        Group {
            switch calendar.status {
            case .notDetermined:
                connectCard
            case .denied, .restricted, .writeOnly:
                deniedCard
            case .fullAccess, .authorized:
                calendarContent
                    .onAppear { calendar.refresh() }
            @unknown default:
                connectCard
            }
        }
        .onChange(of: calendar.selectedDate) { _, _ in
            selectedEvent = nil
        }
    }

    // MARK: - Granted

    private var calendarContent: some View {
        VStack(spacing: 3) {
            header

            CalendarDateWheel(calendar: calendar)
                .frame(maxWidth: .infinity)
                .frame(height: 40)

            if let event = selectedEvent {
                EventDetailView(event: event) {
                    selectedEvent = nil
                }
            } else {
                CalendarSummaryView(calendar: calendar)

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    DayTimelineBar(
                        events: calendar.selectedEvents,
                        date: calendar.selectedDate,
                        now: context.date
                    )
                }
                .frame(height: 5)

                if calendar.selectedEvents.isEmpty {
                    CalendarEmptyView(date: calendar.selectedDate)
                } else {
                    eventList
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(monthYear)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 4)

            navButton("chevron.left", enabled: calendar.canMoveBack) {
                calendar.moveDay(by: -1)
            }

            if !Calendar.current.isDateInToday(calendar.selectedDate) {
                Button {
                    calendar.goToday()
                } label: {
                    Text("Today")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            navButton("chevron.right", enabled: calendar.canMoveForward) {
                calendar.moveDay(by: 1)
            }
        }
        .frame(height: 16)
    }

    private var monthYear: String {
        calendar.selectedDate
            .formatted(.dateTime.month(.abbreviated).year())
            .uppercased()
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
    }

    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(calendar.selectedEvents) { event in
                        eventRow(event)
                            .id(event.id)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
            .onAppear { scrollToNext(proxy) }
            .onChange(of: calendar.selectedEvents.map(\.id)) { _, _ in
                scrollToNext(proxy)
            }
            .onChange(of: calendar.selectedDate) { _, _ in
                scrollToNext(proxy)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func scrollToNext(_ proxy: ScrollViewProxy) {
        let now = Date()
        guard let target = calendar.selectedEvents.first(where: { $0.end > now })
            ?? calendar.selectedEvents.first else {
            return
        }
        DispatchQueue.main.async {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    private func eventRow(_ event: CalendarService.Event) -> some View {
        let hovered = hoveredEventID == event.id

        return Button {
            Haptics.select()
            selectedEvent = event
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.color))
                    .frame(width: 3, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if event.isInProgress {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4, height: 4)
                        }
                        Text(event.title)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }

                    Text(subtitle(for: event))
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.33))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    if event.isAllDay {
                        Text("All day")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    } else {
                        Text(event.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        Text(event.end.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .foregroundStyle(.white.opacity(0.65))
                .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.06 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(hovered ? 0.07 : 0.04), lineWidth: 1)
            )
            .opacity(event.isEnded ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredEventID = isHovering ? event.id : nil
        }
    }

    private func subtitle(for event: CalendarService.Event) -> String {
        var parts: [String] = []
        if let location = event.location, !location.isEmpty {
            parts.append(location)
        }
        if !event.calendarTitle.isEmpty {
            parts.append(event.calendarTitle)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Permission states

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .multilineTextAlignment(.center)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    private func openCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Date wheel

private struct CalendarDateWheel: View {
    @ObservedObject var calendar: CalendarService
    @State private var scrollID: Int?
    @State private var centeredOffset: Int?
    @State private var programmaticScroll = false
    @State private var pendingSelection: DispatchWorkItem?

    private let past = 7
    private let future = 14

    var body: some View {
        ZStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(-past...future, id: \.self) { offset in
                        dayCell(offset)
                            .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollPosition(id: $scrollID, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 245, for: .scrollContent)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: 38, height: 38)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            scrollToSelectedDate(animated: false)
        }
        .onChange(of: calendar.selectedDate) { _, _ in
            scrollToSelectedDate(animated: true)
        }
        .onChange(of: scrollID) { _, newValue in
            guard let newValue else { return }
            centeredOffset = newValue

            guard !programmaticScroll else { return }
            pendingSelection?.cancel()

            let work = DispatchWorkItem {
                let target = date(for: newValue)
                if !Calendar.current.isDate(target, inSameDayAs: calendar.selectedDate) {
                    calendar.select(target)
                }
            }
            pendingSelection = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    private func scrollToSelectedDate(animated: Bool) {
        let target = offset(for: calendar.selectedDate)
        centeredOffset = target
        guard scrollID != target else { return }

        programmaticScroll = true
        pendingSelection?.cancel()

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollID = target
            }
        } else {
            scrollID = target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            programmaticScroll = false
        }
    }

    private func dayCell(_ dayOffset: Int) -> some View {
        let date = date(for: dayOffset)
        let selectedOffset = centeredOffset ?? offset(for: calendar.selectedDate)
        let isSelected = dayOffset == selectedOffset
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            Haptics.select()
            calendar.select(date)
        } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(isSelected ? 0.8 : 0.32))

                ZStack {
                    Circle()
                        .fill(isToday ? Color.white.opacity(0.9) : Color.clear)
                        .frame(width: 20, height: 20)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? .black : .white.opacity(isSelected ? 0.95 : 0.5))
                }

                Circle()
                    .fill(Color.white.opacity(isSelected ? 0.7 : 0.3))
                    .frame(width: 3, height: 3)
                    .opacity(calendar.hasEvents(on: date) ? 1 : 0)
            }
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.09) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func offset(for date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return min(max(days, -past), future)
    }

    private func date(for offset: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
}

// MARK: - Summary

private struct CalendarSummaryView: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let summary = calendar.selectedDaySummary
            HStack(spacing: 4) {
                if summary.count == 0 {
                    Text("Free day")
                } else {
                    Text("\(summary.count) \(summary.count == 1 ? "event" : "events")")
                    Text("·")
                    if summary.busy > 0 {
                        Text("\(durationText(summary.busy)) busy")
                    } else {
                        Text("all-day")
                    }
                }

                Spacer(minLength: 4)

                if let next = calendar.nextEventOnSelectedDay {
                    if next.isAllDay {
                        Text("Next all-day")
                    } else {
                        Text("Next \(next.start.formatted(date: .omitted, time: .shortened))")
                        if Calendar.current.isDateInToday(next.start) {
                            Text("· \(relativeText(next.start, now: context.date))")
                        }
                    }
                }
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.35))
            .lineLimit(1)
        }
        .frame(height: 10)
    }
}

// MARK: - Timeline

private struct DayTimelineBar: View {
    let events: [CalendarService.Event]
    let date: Date
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let span = max(dayEnd.timeIntervalSince(dayStart), 1)
            let width = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                ForEach(events.filter { !$0.isAllDay }) { event in
                    let start = max(event.start, dayStart)
                    let end = min(event.end, dayEnd)
                    if end > start {
                        let x = width * CGFloat(start.timeIntervalSince(dayStart) / span)
                        let segmentWidth = max(2, width * CGFloat(end.timeIntervalSince(start) / span))
                        Capsule()
                            .fill(Color(nsColor: event.color).opacity(event.end <= now ? 0.3 : 0.8))
                            .frame(width: segmentWidth)
                            .offset(x: x)
                    }
                }

                if calendar.isDateInToday(date) {
                    let x = width * CGFloat(min(max(now.timeIntervalSince(dayStart) / span, 0), 1))
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5)
                        .offset(x: x)
                }
            }
        }
        .clipShape(Capsule())
    }
}

// MARK: - Empty state

private struct CalendarEmptyView: View {
    let date: Date

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text(Calendar.current.isDateInToday(date) ? "No events today" : "No events")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            Text("Enjoy your free time!")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Event detail

private struct EventDetailView: View {
    let event: CalendarService.Event
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    Haptics.select()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(event.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer()
            }

            Text(timeText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 5) {
                Circle()
                    .fill(Color(nsColor: event.color))
                    .frame(width: 5, height: 5)
                Text(event.calendarTitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                if !event.accountTitle.isEmpty {
                    Text("· \(event.accountTitle)")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                        .lineLimit(1)
                }
                Spacer()
                if event.attendeeCount > 0 {
                    Label("\(event.attendeeCount)", systemImage: "person.2.fill")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            if let notes = event.notes, !notes.isEmpty {
                ScrollView(.vertical) {
                    Text(notes)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 38)
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                if let joinURL = event.joinURL {
                    actionButton("Join", icon: "video.fill") {
                        NSWorkspace.shared.open(joinURL)
                    }
                }
                if let calendarURL = event.calendarAppURL {
                    actionButton("Calendar", icon: "calendar") {
                        NSWorkspace.shared.open(calendarURL)
                    }
                }
                Spacer()
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var timeText: String {
        if event.isAllDay {
            return "All day"
        }
        let start = event.start.formatted(date: .abbreviated, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end) · \(durationText(event.duration))"
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.88)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formatting

private func durationText(_ duration: TimeInterval) -> String {
    let minutes = max(0, Int(duration / 60))
    if minutes < 60 {
        return "\(minutes)m"
    }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
}

private func relativeText(_ date: Date, now: Date) -> String {
    let seconds = date.timeIntervalSince(now)
    if seconds <= 0 {
        return "now"
    }
    let minutes = Int(seconds / 60)
    if minutes < 1 {
        return "in <1m"
    }
    if minutes < 60 {
        return "in \(minutes)m"
    }
    let hours = minutes / 60
    if hours < 24 {
        return "in \(hours)h"
    }
    return date.formatted(.dateTime.weekday(.abbreviated))
}
