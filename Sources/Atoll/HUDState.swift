import Combine

enum HUDKind: Equatable {
    case volume
    case brightness
}

final class HUDState: ObservableObject {
    @Published var kind: HUDKind = .volume
    @Published var value: Double = 0
    @Published var muted = false
    @Published var visible = false
}
