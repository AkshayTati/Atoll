import Combine
import CoreGraphics

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var notchHeight: CGFloat = 32
}
