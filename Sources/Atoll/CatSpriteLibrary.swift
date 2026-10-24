import AppKit
import os

enum CatFacing: Equatable {
    case east
    case west

    var folder: String {
        self == .east ? "east" : "west"
    }
}

enum CatAction: String, Equatable, CaseIterable {
    case idle
    case sit
    case walk
    case sneak
    case run
    case pounce
    case peek
    case sleep
    case groom
    case stretch
    case yawn
    case love
    case greet
    case surprised
    case play
    case chase
    case flat
    case wake
    case jump
    case land

    var usesFacing: Bool {
        switch self {
        case .walk, .sneak, .run, .pounce, .peek, .surprised, .chase:
            return true
        default:
            return false
        }
    }

    var loops: Bool {
        switch self {
        case .idle, .sit, .walk, .sneak, .run, .peek, .sleep, .groom, .play, .chase, .flat:
            return true
        default:
            return false
        }
    }

    var fps: Double {
        switch self {
        case .idle, .sit:
            return 1
        case .walk:
            return 10
        case .sneak:
            return 8
        case .run:
            return 14
        case .pounce:
            return 12
        case .peek:
            return 6
        case .sleep:
            return 4
        case .groom:
            return 6
        case .stretch, .yawn, .love, .greet:
            return 6
        case .surprised:
            return 10
        case .play, .chase:
            return 8
        case .flat:
            return 4
        case .wake:
            return 8
        case .jump:
            return 10
        case .land:
            return 8
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .pounce:
            return 8.0 / fps
        case .surprised:
            return 8.0 / fps
        case .stretch, .yawn, .love, .greet:
            return 8.0 / fps
        case .wake:
            return 8.0 / fps
        case .jump:
            return 4.0 / fps
        case .land:
            return 2.0 / fps
        default:
            return nil
        }
    }
}

final class CatSpriteLibrary {
    static let shared = CatSpriteLibrary()

    private var cache: [String: [NSImage]] = [:]
    private let root: URL?

    private init() {
        let fm = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("CatSprites"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/CatSprites")
        ].compactMap { $0 }

        root = candidates.first { fm.fileExists(atPath: $0.path) }

        if let root {
            Logger.app.info("cat sprites: \(root.path, privacy: .public)")
        } else {
            Logger.app.error("cat sprites missing")
        }
    }

    func frames(for action: CatAction, facing: CatFacing) -> [NSImage] {
        let direction = action.usesFacing ? facing.folder : "south"
        let key = "\(action.rawValue)/\(direction)"

        if let cached = cache[key] {
            return cached
        }

        guard let root else { return [] }
        let directory = root.appendingPathComponent(key)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            Logger.app.error("cat sprites missing \(key, privacy: .public)")
            return []
        }

        let images = files
            .filter { $0.hasSuffix(".png") }
            .sorted()
            .compactMap { NSImage(contentsOfFile: directory.appendingPathComponent($0).path) }

        cache[key] = images
        return images
    }

    func preload() {
        for action in CatAction.allCases {
            if action.usesFacing {
                _ = frames(for: action, facing: .east)
                _ = frames(for: action, facing: .west)
            } else {
                _ = frames(for: action, facing: .east)
            }
        }
    }
}
