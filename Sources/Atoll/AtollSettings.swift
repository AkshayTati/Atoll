import Combine
import Foundation

enum CatBehaviorPace: String, CaseIterable, Identifiable {
    case calm
    case normal
    case playful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .normal: return "Normal"
        case .playful: return "Playful"
        }
    }

    var interval: ClosedRange<Double> {
        switch self {
        case .calm: return 7.0...13.0
        case .normal: return 4.0...8.0
        case .playful: return 2.5...5.5
        }
    }
}

enum CatSleepDelay: String, CaseIterable, Identifiable {
    case never
    case thirtySeconds
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .thirtySeconds: return 30
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        }
    }
}

final class AtollSettings: ObservableObject {
    static let shared = AtollSettings()

    private let defaults = UserDefaults.standard

    @Published var showIntroOnLaunch: Bool {
        didSet { defaults.set(showIntroOnLaunch, forKey: Keys.showIntroOnLaunch) }
    }

    @Published var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Keys.expandOnHover) }
    }

    @Published var defaultModule: IslandModule {
        didSet { defaults.set(defaultModule.rawValue, forKey: Keys.defaultModule) }
    }

    @Published var showMediaInCollapsed: Bool {
        didSet { defaults.set(showMediaInCollapsed, forKey: Keys.showMediaInCollapsed) }
    }

    @Published var showCalendarInCollapsed: Bool {
        didSet { defaults.set(showCalendarInCollapsed, forKey: Keys.showCalendarInCollapsed) }
    }

    @Published var showAllMediaClients: Bool {
        didSet { defaults.set(showAllMediaClients, forKey: Keys.showAllMediaClients) }
    }

    @Published var hudEnabled: Bool {
        didSet { defaults.set(hudEnabled, forKey: Keys.hudEnabled) }
    }

    @Published var hudShowVolume: Bool {
        didSet { defaults.set(hudShowVolume, forKey: Keys.hudShowVolume) }
    }

    @Published var hudShowBrightness: Bool {
        didSet { defaults.set(hudShowBrightness, forKey: Keys.hudShowBrightness) }
    }

    @Published var hudShowMute: Bool {
        didSet { defaults.set(hudShowMute, forKey: Keys.hudShowMute) }
    }

    @Published var hudDuration: Double {
        didSet { defaults.set(hudDuration, forKey: Keys.hudDuration) }
    }

    @Published var catEnabled: Bool {
        didSet { defaults.set(catEnabled, forKey: Keys.showMascot) }
    }

    @Published var catBehaviorPace: CatBehaviorPace {
        didSet { defaults.set(catBehaviorPace.rawValue, forKey: Keys.catBehaviorPace) }
    }

    @Published var catPeekWhilePlaying: Bool {
        didSet { defaults.set(catPeekWhilePlaying, forKey: Keys.catPeekWhilePlaying) }
    }

    @Published var catHoverGreeting: Bool {
        didSet { defaults.set(catHoverGreeting, forKey: Keys.catHoverGreeting) }
    }

    @Published var catSleepDelay: CatSleepDelay {
        didSet { defaults.set(catSleepDelay.rawValue, forKey: Keys.catSleepDelay) }
    }

    @Published var catShortcut: KeyboardShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(catShortcut) {
                defaults.set(data, forKey: Keys.catShortcut)
            }
        }
    }

    @Published var calendarFilterEnabled: Bool {
        didSet { defaults.set(calendarFilterEnabled, forKey: Keys.calendarFilterEnabled) }
    }

    @Published var selectedCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(selectedCalendarIDs).sorted(), forKey: Keys.selectedCalendarIDs)
        }
    }

    @Published var calendarShowAllDay: Bool {
        didSet { defaults.set(calendarShowAllDay, forKey: Keys.calendarShowAllDay) }
    }

    private init() {
        let defaults = UserDefaults.standard

        showIntroOnLaunch = defaults.object(forKey: Keys.showIntroOnLaunch) as? Bool ?? true
        expandOnHover = defaults.object(forKey: Keys.expandOnHover) as? Bool ?? true

        let moduleRaw = defaults.string(forKey: Keys.defaultModule) ?? IslandModule.media.rawValue
        defaultModule = IslandModule(rawValue: moduleRaw) ?? .media

        showMediaInCollapsed = defaults.object(forKey: Keys.showMediaInCollapsed) as? Bool ?? true
        showCalendarInCollapsed = defaults.object(forKey: Keys.showCalendarInCollapsed) as? Bool ?? true
        showAllMediaClients = defaults.object(forKey: Keys.showAllMediaClients) as? Bool ?? true

        hudEnabled = defaults.object(forKey: Keys.hudEnabled) as? Bool ?? true
        hudShowVolume = defaults.object(forKey: Keys.hudShowVolume) as? Bool ?? true
        hudShowBrightness = defaults.object(forKey: Keys.hudShowBrightness) as? Bool ?? true
        hudShowMute = defaults.object(forKey: Keys.hudShowMute) as? Bool ?? true
        hudDuration = defaults.object(forKey: Keys.hudDuration) as? Double ?? 1.1

        catEnabled = defaults.object(forKey: Keys.showMascot) as? Bool ?? true

        let paceRaw = defaults.string(forKey: Keys.catBehaviorPace) ?? CatBehaviorPace.normal.rawValue
        catBehaviorPace = CatBehaviorPace(rawValue: paceRaw) ?? .normal
        catPeekWhilePlaying = defaults.object(forKey: Keys.catPeekWhilePlaying) as? Bool ?? true
        catHoverGreeting = defaults.object(forKey: Keys.catHoverGreeting) as? Bool ?? true

        let sleepRaw = defaults.string(forKey: Keys.catSleepDelay) ?? CatSleepDelay.oneMinute.rawValue
        catSleepDelay = CatSleepDelay(rawValue: sleepRaw) ?? .oneMinute

        if let data = defaults.data(forKey: Keys.catShortcut),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            catShortcut = shortcut
        } else {
            catShortcut = .defaultCatToggle
        }

        calendarFilterEnabled = defaults.object(forKey: Keys.calendarFilterEnabled) as? Bool ?? false
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Keys.selectedCalendarIDs) ?? [])
        calendarShowAllDay = defaults.object(forKey: Keys.calendarShowAllDay) as? Bool ?? true
    }

    func reset() {
        showIntroOnLaunch = true
        expandOnHover = true
        defaultModule = .media
        showMediaInCollapsed = true
        showCalendarInCollapsed = true
        showAllMediaClients = true
        hudEnabled = true
        hudShowVolume = true
        hudShowBrightness = true
        hudShowMute = true
        hudDuration = 1.1
        catEnabled = true
        catBehaviorPace = .normal
        catPeekWhilePlaying = true
        catHoverGreeting = true
        catSleepDelay = .oneMinute
        catShortcut = .defaultCatToggle
        calendarFilterEnabled = false
        selectedCalendarIDs = []
        calendarShowAllDay = true
    }

    private enum Keys {
        static let showIntroOnLaunch = "atoll.showIntroOnLaunch"
        static let expandOnHover = "atoll.expandOnHover"
        static let defaultModule = "atoll.defaultModule"
        static let showMediaInCollapsed = "atoll.showMediaInCollapsed"
        static let showCalendarInCollapsed = "atoll.showCalendarInCollapsed"
        static let showAllMediaClients = "atoll.showAllMediaClients"
        static let hudEnabled = "atoll.hudEnabled"
        static let hudShowVolume = "atoll.hudShowVolume"
        static let hudShowBrightness = "atoll.hudShowBrightness"
        static let hudShowMute = "atoll.hudShowMute"
        static let hudDuration = "atoll.hudDuration"
        static let showMascot = "showMascot"
        static let catBehaviorPace = "atoll.catBehaviorPace"
        static let catPeekWhilePlaying = "atoll.catPeekWhilePlaying"
        static let catHoverGreeting = "atoll.catHoverGreeting"
        static let catSleepDelay = "atoll.catSleepDelay"
        static let catShortcut = "atoll.catShortcut"
        static let calendarFilterEnabled = "atoll.calendarFilterEnabled"
        static let selectedCalendarIDs = "atoll.selectedCalendarIDs"
        static let calendarShowAllDay = "atoll.calendarShowAllDay"
    }
}
