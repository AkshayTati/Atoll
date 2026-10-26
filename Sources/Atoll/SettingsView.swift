import AppKit
import EventKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case island
    case media
    case calendar
    case hud
    case cat
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .island: return "Island"
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .hud: return "HUD"
        case .cat: return "Cat"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .island: return "capsule"
        case .media: return "play.circle"
        case .calendar: return "calendar"
        case .hud: return "slider.horizontal.3"
        case .cat: return "pawprint"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AtollSettings.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @ObservedObject var calendar: CalendarService
    @ObservedObject var hud: HUDController
    let mascot: MascotController

    @State private var section: SettingsSection = .general
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showResetAlert = false

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 185)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general:
            general
        case .island:
            island
        case .media:
            media
        case .calendar:
            calendarSettings
        case .hud:
            hudSettings
        case .cat:
            catSettings
        case .shortcuts:
            shortcutSettings
        case .about:
            about
        }
    }

    private var general: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { value in
                            launchAtLogin = value
                            LaunchAtLogin.set(value)
                        }
                    )
                )

                Toggle("Show intro expansion on launch", isOn: $settings.showIntroOnLaunch)
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
            }

            Section("When opening the island") {
                Picker("Default module", selection: $settings.defaultModule) {
                    ForEach(IslandModule.allCases, id: \.self) { module in
                        Text(module.title).tag(module)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private var island: some View {
        Form {
            Section("Collapsed island") {
                Toggle("Show media wings when collapsed", isOn: $settings.showMediaInCollapsed)
                Toggle("Show calendar peek when idle", isOn: $settings.showCalendarInCollapsed)
            }

            Section {
                Text("The cat always keeps a little room on the collapsed island.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var media: some View {
        Form {
            Section("Now Playing") {
                Toggle("Show all Now Playing clients", isOn: $settings.showAllMediaClients)

                Text("macOS only allows transport commands for the active player. Other clients are displayed read-only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var calendarSettings: some View {
        Form {
            Section("Access") {
                HStack(spacing: 8) {
                    Image(systemName: calendarAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(calendarAuthorized ? .green : .orange)
                    Text(calendarAuthorized ? "Calendar access granted" : "Calendar access is not granted")
                    Spacer()
                    if !calendarAuthorized {
                        Button("Grant Access") {
                            calendar.requestAccess()
                        }
                    }
                }
            }

            Section("Events") {
                Picker("Show events from", selection: $settings.calendarFilterEnabled) {
                    Text("All calendars").tag(false)
                    Text("Selected calendars").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!calendarAuthorized)

                Toggle("Show all-day events", isOn: $settings.calendarShowAllDay)
                    .disabled(!calendarAuthorized)
            }

            if settings.calendarFilterEnabled {
                calendarPicker
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.calendarFilterEnabled) { _, enabled in
            guard enabled, settings.selectedCalendarIDs.isEmpty else { return }
            settings.selectedCalendarIDs = Set(
                calendar.calendarGroups.flatMap { $0.calendars.map(\.id) }
            )
        }
    }

    @ViewBuilder
    private var calendarPicker: some View {
        if !calendarAuthorized {
            Section("Calendars") {
                Text("Grant access to choose calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if calendar.calendarGroups.isEmpty {
            Section("Calendars") {
                Text("No calendars found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Calendars") {
                HStack {
                    Button("Select All") {
                        settings.selectedCalendarIDs = Set(
                            calendar.calendarGroups.flatMap { $0.calendars.map(\.id) }
                        )
                    }
                    Button("Clear") {
                        settings.selectedCalendarIDs = []
                    }
                    Spacer()
                }
                .buttonStyle(.borderless)
            }

            ForEach(calendar.calendarGroups) { group in
                Section {
                    ForEach(group.calendars) { item in
                        Toggle(isOn: calendarBinding(for: item.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: item.color))
                                    .frame(width: 8, height: 8)
                                Text(item.title)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(group.title)
                        Spacer()
                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(groupAllSelected(group) ? "None" : "All") {
                            var ids = settings.selectedCalendarIDs
                            if groupAllSelected(group) {
                                ids.subtract(group.calendars.map(\.id))
                            } else {
                                ids.formUnion(group.calendars.map(\.id))
                            }
                            settings.selectedCalendarIDs = ids
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var hudSettings: some View {
        Form {
            Section("HUD") {
                Toggle("Show HUD line", isOn: $settings.hudEnabled)
                Toggle("Volume", isOn: $settings.hudShowVolume)
                Toggle("Brightness", isOn: $settings.hudShowBrightness)
                Toggle("Mute", isOn: $settings.hudShowMute)

                HStack {
                    Text("Visible for")
                    Slider(value: $settings.hudDuration, in: 0.5...2.5, step: 0.1)
                    Text(String(format: "%.1fs", settings.hudDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .disabled(!settings.hudEnabled)

            Section("Accessibility") {
                HStack(spacing: 8) {
                    Image(systemName: hud.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hud.accessibilityTrusted ? .green : .orange)
                    Text(hud.accessibilityTrusted ? "Accessibility granted" : "Accessibility is required")
                    Spacer()
                    if !hud.accessibilityTrusted {
                        Button("Open Settings") {
                            hud.requestAccess()
                        }
                    }
                }

                Button("Test HUD line") {
                    hud.showTest()
                }
                .disabled(!settings.hudEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var catSettings: some View {
        Form {
            Section("Cat") {
                Toggle("Show cat", isOn: $settings.catEnabled)

                Picker("Behavior pace", selection: $settings.catBehaviorPace) {
                    ForEach(CatBehaviorPace.allCases) { pace in
                        Text(pace.title).tag(pace)
                    }
                }

                Picker("Sleep after idle", selection: $settings.catSleepDelay) {
                    ForEach(CatSleepDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }

                Toggle("Peek while media is playing", isOn: $settings.catPeekWhilePlaying)
                Toggle("Greet on hover", isOn: $settings.catHoverGreeting)
            }

            Section("Shortcut") {
                LabeledContent("Toggle cat") {
                    HStack(spacing: 10) {
                        Text(settings.catShortcut.display)
                            .font(.system(.body, design: .monospaced))
                        Button("Change…") {
                            section = .shortcuts
                        }
                    }
                }
            }

            Section {
                Button("Peek now") {
                    mascot.forcePeek()
                }
                .disabled(!settings.catEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutSettings: some View {
        Form {
            Section("Global shortcut") {
                LabeledContent("Toggle cat") {
                    ShortcutRecorder(shortcut: $settings.catShortcut)
                        .frame(width: 160, height: 28)
                }

                if let error = shortcuts.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if shortcuts.registered {
                    Label("Registered and ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Text("Click the field, then press a key combination. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to default") {
                    settings.catShortcut = .defaultCatToggle
                }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Atoll")
                            .font(.title2.weight(.semibold))
                        Text("Version \(appVersion)")
                            .foregroundStyle(.secondary)
                        Link("github.com/AkshayTati/Atoll", destination: URL(string: "https://github.com/AkshayTati/Atoll")!)
                            .font(.caption)
                    }
                }
            }

            Section("Credits") {
                Text("Cat sprites: catset by seethingswarm (CC0).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Built with AppKit, SwiftUI, EventKit, and a small private MediaRemote helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings", role: .destructive) {
                    showResetAlert = true
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset all settings?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.reset()
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        } message: {
            Text("This restores Atoll's defaults. Launch at Login is not changed.")
        }
    }

    private var calendarAuthorized: Bool {
        calendar.status == .fullAccess || calendar.status == .authorized
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func calendarBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.selectedCalendarIDs.contains(id) },
            set: { selected in
                var ids = settings.selectedCalendarIDs
                if selected {
                    ids.insert(id)
                } else {
                    ids.remove(id)
                }
                settings.selectedCalendarIDs = ids
            }
        )
    }

    private func groupAllSelected(_ group: CalendarService.CalendarGroup) -> Bool {
        !group.calendars.isEmpty && group.calendars.allSatisfy {
            settings.selectedCalendarIDs.contains($0.id)
        }
    }
}
