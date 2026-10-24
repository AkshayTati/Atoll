import AppKit
import Combine
import EventKit
import os

/// Reads upcoming events from the same calendars Calendar.app uses.
final class CalendarService: ObservableObject {
    struct Event: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor
        let calendarTitle: String
        let joinURL: URL?
    }

    @Published private(set) var events: [Event] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?

    private let store = EKEventStore()
    private var started = false
    private var changeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        status = EKEventStore.authorizationStatus(for: .event)

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }

        if status == .fullAccess || status == .authorized {
            load()
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
                    print("calendar: \(error.localizedDescription)")
                }
                print("calendar: access granted=\(granted) status=\(self.status.rawValue)")
                Logger.app.info("calendar: granted=\(granted, privacy: .public) status=\(self.status.rawValue, privacy: .public)")
                if granted {
                    self.load()
                }
            }
        }
    }

    func load() {
        let current = EKEventStore.authorizationStatus(for: .event)
        guard current == .fullAccess || current == .authorized else { return }

        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 8, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        DispatchQueue.global(qos: .userInitiated).async { [store] in
            let found = store.events(matching: predicate)
            let mapped = found
                .filter { $0.status != .canceled && $0.endDate >= now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(3)
                .map { event -> Event in
                    let color = event.calendar.flatMap { NSColor(cgColor: $0.cgColor) } ?? .systemBlue
                    return Event(
                        id: event.eventIdentifier ?? UUID().uuidString,
                        title: event.title ?? "Untitled",
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        color: color,
                        calendarTitle: event.calendar?.title ?? "",
                        joinURL: Self.joinURL(for: event)
                    )
                }

            DispatchQueue.main.async { [weak self] in
                self?.events = Array(mapped)
                print("calendar: loaded \(mapped.count) upcoming events")
                Logger.app.info("calendar: loaded \(mapped.count, privacy: .public) upcoming events")
            }
        }
    }

    // MARK: - Meeting links

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
}
