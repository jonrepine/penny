import Foundation

/// Settings persisted to `~/.penny/config.json`. The Python helper
/// reads the same file (with the bundled defaults as a fallback). Anything
/// the user edits in the preferences window ends up here.
struct AppConfig: Codable {
    var llmProvider: String
    var model: String
    var maxTokens: Int
    var timeoutSeconds: Int
    var saveHistory: Bool
    var historyLimit: Int
    var showToasts: Bool

    enum CodingKeys: String, CodingKey {
        case llmProvider = "llm_provider"
        case model
        case maxTokens = "max_tokens"
        case timeoutSeconds = "timeout_seconds"
        case saveHistory = "save_history"
        case historyLimit = "history_limit"
        case showToasts = "show_notifications"
    }

    static var defaults: AppConfig {
        AppConfig(
            llmProvider: "anthropic",
            model: "claude-sonnet-4-6",
            maxTokens: 1024,
            timeoutSeconds: 45,
            saveHistory: true,
            historyLimit: 50,
            showToasts: true
        )
    }
}

enum ConfigStore {
    static func userPath() -> String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".penny/config.json")
    }

    static func bundledPath(appDir: String) -> String {
        (appDir as NSString).appendingPathComponent("config/config.json")
    }

    static func load(appDir: String) -> AppConfig {
        var current = AppConfig.defaults
        for path in [bundledPath(appDir: appDir), userPath()] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            guard let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else { continue }
            current = decoded
        }
        return current
    }

    static func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let url = URL(fileURLWithPath: userPath())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
