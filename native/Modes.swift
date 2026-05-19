import Foundation

/// One row in the picker. Loaded at runtime from `~/.penny/modes.json`
/// (with defaults at `<repo>/config/modes.default.json`). Editable in the
/// preferences window.
struct Mode: Codable {
    let id: Int
    let name: String
    let detail: String
    let isCustom: Bool
    let isCancel: Bool
    let locked: Bool
    let prompt: String

    init(
        id: Int,
        name: String,
        detail: String,
        isCustom: Bool = false,
        isCancel: Bool = false,
        locked: Bool = false,
        prompt: String = ""
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.isCustom = isCustom
        self.isCancel = isCancel
        self.locked = locked
        self.prompt = prompt
    }
}

/// All modes the picker should render, in display order. Loaded once at
/// launch via `Modes.load(appDir:)` and re-loaded whenever the preferences
/// window saves changes.
enum Modes {
    nonisolated(unsafe) static var all: [Mode] = []

    static func load(appDir: String) {
        let candidates = [
            userPath(),
            defaultPath(appDir: appDir),
        ]
        for path in candidates {
            if let loaded = try? read(from: path), !loaded.isEmpty {
                all = loaded
                return
            }
        }
        all = []
        log("Modes: failed to load from any candidate path")
    }

    static func userPath() -> String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".penny/modes.json")
    }

    static func defaultPath(appDir: String) -> String {
        (appDir as NSString).appendingPathComponent("config/modes.default.json")
    }

    static func save(_ modes: [Mode]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(modes)

        let url = URL(fileURLWithPath: userPath())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        all = modes
    }

    private static func read(from path: String) throws -> [Mode] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([Mode].self, from: data)
    }
}
