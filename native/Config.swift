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
    var whisperModel: String

    enum CodingKeys: String, CodingKey {
        case llmProvider = "llm_provider"
        case model
        case maxTokens = "max_tokens"
        case timeoutSeconds = "timeout_seconds"
        case saveHistory = "save_history"
        case historyLimit = "history_limit"
        case showToasts = "show_notifications"
        case whisperModel = "whisper_model"
    }

    static var defaults: AppConfig {
        AppConfig(
            llmProvider: "anthropic",
            model: "claude-sonnet-4-6",
            maxTokens: 1024,
            timeoutSeconds: 45,
            saveHistory: true,
            historyLimit: 50,
            showToasts: true,
            whisperModel: WhisperModels.defaultForCurrentMac().id
        )
    }

    init(
        llmProvider: String,
        model: String,
        maxTokens: Int,
        timeoutSeconds: Int,
        saveHistory: Bool,
        historyLimit: Int,
        showToasts: Bool,
        whisperModel: String
    ) {
        self.llmProvider = llmProvider
        self.model = model
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
        self.saveHistory = saveHistory
        self.historyLimit = historyLimit
        self.showToasts = showToasts
        self.whisperModel = whisperModel
    }

    /// Decoder that tolerates older configs missing newer keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.defaults
        llmProvider     = (try? container.decode(String.self, forKey: .llmProvider))     ?? d.llmProvider
        model           = (try? container.decode(String.self, forKey: .model))           ?? d.model
        maxTokens       = (try? container.decode(Int.self,    forKey: .maxTokens))       ?? d.maxTokens
        timeoutSeconds  = (try? container.decode(Int.self,    forKey: .timeoutSeconds))  ?? d.timeoutSeconds
        saveHistory     = (try? container.decode(Bool.self,   forKey: .saveHistory))     ?? d.saveHistory
        historyLimit    = (try? container.decode(Int.self,    forKey: .historyLimit))    ?? d.historyLimit
        showToasts      = (try? container.decode(Bool.self,   forKey: .showToasts))      ?? d.showToasts
        whisperModel    = (try? container.decode(String.self, forKey: .whisperModel))    ?? d.whisperModel
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
