import AppKit
import Combine
import EventKit
import os

/// Reads the user's calendars through EventKit and exposes a day-centric
/// agenda: selected day, a 3-week window, a day summary, and the next event.
final class CalendarService: ObservableObject {
    struct Event: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor
        let calendarTitle: String
        let accountTitle: String
        let location: String?
        let notes: String?
        let attendeeCount: Int
        let joinURL: URL?
        let calendarAppURL: URL?

        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
        var isInProgress: Bool { start <= Date() && end > Date() }
        var isEnded: Bool { end <= Date() }
    }

    struct DaySummary {
        let count: Int
        let busy: TimeInterval
    }

    struct CalendarInfo: Identifiable {
        let id: String
        let title: String
        let color: NSColor
        let accountTitle: String
        let accountType: String
    }

    struct CalendarGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let calendars: [CalendarInfo]
    }

    @Published private(set) var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published private(set) var selectedEvents: [Event] = []
    @Published private(set) var nextEvent: Event?
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var calendarGroups: [CalendarGroup] = []

    private let store = EKEventStore()
    private let settings = AtollSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var windowEvents: [Event] = []
    private var windowStart = Date.distantPast
    private var windowEnd = Date.distantFuture
    private var started = false
    private var changeObserver: NSObjectProtocol?
    private var minuteTimer: Timer?

    // MARK: - Derived state

    var selectedDaySummary: DaySummary {
        DaySummary(count: selectedEvents.count, busy: busyDuration(on: selectedDate))
    }

    var nextEventOnSelectedDay: Event? {
        if Calendar.current.isDateInToday(selectedDate) {
            return selectedEvents.first { $0.end > Date() }
        }
        return selectedEvents.first
    }

    func hasEvents(on date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return false
        }
        return windowEvents.contains { $0.start < dayEnd && $0.end > dayStart }
    }

    var hasCollapsedEvent: Bool {
        guard let nextEvent else { return false }
        return nextEvent.start < Date().addingTimeInterval(7 * 24 * 3600)
    }

    var canMoveBack: Bool {
        selectedDate > windowStart
    }

    var canMoveForward: Bool {
        selectedDate < windowEnd.addingTimeInterval(-86400)
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        status = EKEventStore.authorizationStatus(for: .event)

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadCalendars()
            self?.loadWindow()
        }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer

        settings.$calendarFilterEnabled
            .combineLatest(settings.$selectedCalendarIDs)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.loadWindow()
            }
            .store(in: &cancellables)

        settings.$calendarShowAllDay
            .dropFirst()
            .sink { [weak self] _ in
                self?.loadWindow()
            }
            .store(in: &cancellables)

        if status == .fullAccess || status == .authorized {
            loadCalendars()
            loadWindow()
        }
    }

    func requestAccess() {
        guard !loading else { return }
        loading = true

        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.status = EKEventStore.authorizationStatus(for: .event)

                if let error {
                    self.errorMessage = error.localizedDescription
                    Logger.app.info("calendar: \(error.localizedDescription, privacy: .public)")
                }
                Logger.app.info(
                    "calendar: granted=\(granted, privacy: .public) status=\(self.status.rawValue, privacy: .public)"
                )
                if granted {
                    self.loadCalendars()
                    self.loadWindow()
                }
            }
        }
    }

    func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .authorized {
            loadCalendars()
            loadWindow()
        }
    }

    // MARK: - Navigation

    func select(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != selectedDate else { return }
        selectedDate = day

        if day < windowStart || day >= windowEnd {
            loadWindow()
        } else {
            applySelectedDay()
        }
    }

    func moveDay(by offset: Int) {
        let calendar = Calendar.current
        guard let target = calendar.date(byAdding: .day, value: offset, to: selectedDate) else {
            return
        }
        select(target)
    }

    func goToday() {
        select(Date())
    }

    // MARK: - Loading

    func loadCalendars() {
        let calendars = store.calendars(for: .event)
        var grouped: [String: (title: String, subtitle: String, calendars: [EKCalendar])] = [:]

        for calendar in calendars {
            let source = calendar.source
            let identifier = source?.sourceIdentifier ?? source?.title ?? "other"
            let title = source?.title ?? "Other"
            let subtitle = Self.accountTypeName(source?.sourceType)
            grouped[identifier, default: (title, subtitle, [])].calendars.append(calendar)
        }

        calendarGroups = grouped
            .map { identifier, value in
                let items = value.calendars
                    .map { calendar in
                        CalendarInfo(
                            id: calendar.calendarIdentifier,
                            title: calendar.title.isEmpty ? "Untitled" : calendar.title,
                            color: calendar.color,
                            accountTitle: value.title,
                            accountType: value.subtitle
                        )
                    }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

                return CalendarGroup(
                    id: identifier,
                    title: value.title,
                    subtitle: value.subtitle,
                    calendars: items
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        Logger.app.info(
            "calendar: \(self.calendarGroups.count, privacy: .public) account groups, \(calendars.count, privacy: .public) calendars"
        )
    }

    private static func accountTypeName(_ type: EKSourceType?) -> String {
        guard let type else { return "Calendar" }
        switch type {
        case .local: return "On My Mac"
        case .exchange: return "Exchange"
        case .calDAV: return "CalDAV"
        case .mobileMe: return "iCloud"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        @unknown default: return "Calendar"
        }
    }

    private func selectedCalendars() -> [EKCalendar]? {
        guard settings.calendarFilterEnabled else { return nil }
        let selected = settings.selectedCalendarIDs
        return store.calendars(for: .event).filter {
            selected.contains($0.calendarIdentifier)
        }
    }

    private func loadWindow() {
        let current = EKEventStore.authorizationStatus(for: .event)
        guard current == .fullAccess || current == .authorized else {
            status = current
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -7, to: today),
              let end = calendar.date(byAdding: .day, value: 15, to: today) else {
            return
        }

        windowStart = start
        windowEnd = end
        loading = true

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: selectedCalendars()
        )
        let showAllDay = settings.calendarShowAllDay

        DispatchQueue.global(qos: .userInitiated).async { [store] in
            let found = store.events(matching: predicate)
            let mapped = found.compactMap { Self.makeEvent(from: $0, showAllDay: showAllDay) }
                .sorted { $0.start < $1.start }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.windowEvents = mapped
                self.loading = false
                self.applySelectedDay()
                Logger.app.info("calendar: loaded \(mapped.count, privacy: .public) events in window")
            }
        }
    }

    private func applySelectedDay() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return
        }

        selectedEvents = windowEvents
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                if lhs.start != rhs.start {
                    return lhs.start < rhs.start
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        updateNextEvent()
        Logger.app.info(
            "calendar: \(self.selectedEvents.count, privacy: .public) events on \(self.selectedDate.formatted(date: .abbreviated, time: .omitted), privacy: .public)"
        )
    }

    private func updateNextEvent() {
        let now = Date()
        nextEvent = windowEvents
            .filter { $0.end > now }
            .min { $0.start < $1.start }
        Logger.app.info(
            "calendar: next=\(self.nextEvent?.title ?? "none", privacy: .public) at \(self.nextEvent?.start.formatted(date: .abbreviated, time: .shortened) ?? "none", privacy: .public)"
        )
    }

    // MARK: - Summary

    private func busyDuration(on day: Date) -> TimeInterval {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return 0
        }

        let intervals = selectedEvents
            .filter { !$0.isAllDay }
            .map { (max($0.start, dayStart), min($0.end, dayEnd)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }

        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?

        for (start, end) in intervals {
            if let existingEnd = currentEnd, start <= existingEnd {
                currentEnd = max(existingEnd, end)
            } else {
                if let currentStart, let currentEnd {
                    total += currentEnd.timeIntervalSince(currentStart)
                }
                currentStart = start
                currentEnd = end
            }
        }

        if let currentStart, let currentEnd {
            total += currentEnd.timeIntervalSince(currentStart)
        }
        return total
    }

    // MARK: - Mapping

    private static func makeEvent(from event: EKEvent, showAllDay: Bool) -> Event? {
        guard event.status != .canceled else { return nil }
        if event.isAllDay && !showAllDay { return nil }

        if let me = event.attendees?.first(where: { $0.isCurrentUser }),
           me.participantStatus == .declined {
            return nil
        }

        let calendar = event.calendar
        let identifier = event.eventIdentifier ?? UUID().uuidString

        return Event(
            id: identifier,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: calendar?.color ?? .systemBlue,
            calendarTitle: calendar?.title ?? "",
            accountTitle: calendar?.source.title ?? "",
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
            attendeeCount: event.attendees?.count ?? 0,
            joinURL: joinURL(for: event),
            calendarAppURL: calendarAppURL(for: event)
        )
    }

    private static let linkRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"']+"#,
        options: []
    )

    private static func joinURL(for event: EKEvent) -> URL? {
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        var links: [URL] = []

        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in linkRegex.matches(in: text, range: range) {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let raw = String(text[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ").,;"))
                if let url = URL(string: raw) {
                    links.append(url)
                }
            }
        }

        let preferredHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"]
        return links.first(where: { url in
            preferredHosts.contains(where: { url.host?.contains($0) == true })
        }) ?? links.first
    }

    private static func calendarAppURL(for event: EKEvent) -> URL? {
        guard let identifier = event.eventIdentifier,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
    }
}
