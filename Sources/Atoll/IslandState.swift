import Combine
import CoreGraphics

enum IslandModule: String, CaseIterable {
    case media
    case calendar

    var title: String {
        switch self {
        case .media: return "Media"
        case .calendar: return "Calendar"
        }
    }

    var icon: String {
        switch self {
        case .media: return "play.circle.fill"
        case .calendar: return "calendar"
        }
    }
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var peeking = false
    @Published var notchHeight: CGFloat = 32
    @Published var notchWidth: CGFloat = 179
    @Published var activeModule: IslandModule = .media
}
