import Combine
import CoreGraphics

enum IslandModule: String, CaseIterable {
    case media
    case sound
    case calendar

    var title: String {
        switch self {
        case .media: return "Media"
        case .sound: return "Sound"
        case .calendar: return "Calendar"
        }
    }

    var icon: String {
        switch self {
        case .media: return "play.circle.fill"
        case .sound: return "speaker.wave.2.fill"
        case .calendar: return "calendar"
        }
    }
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var notchHeight: CGFloat = 32
    @Published var activeModule: IslandModule = .media
}
