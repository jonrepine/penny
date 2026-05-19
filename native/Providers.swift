import Foundation

/// Catalogue of the LLM providers Penny supports and the curated set of
/// models exposed in the preferences dropdown for each one. Keeping this
/// in one place means adding a new model is a one-line edit.
struct Provider {
    let id: String         // matches the Keychain account name + config value
    let label: String
    let envVar: String
    let placeholder: String
    let signupURL: String
    let models: [ModelOption]
}

struct ModelOption {
    let id: String         // the exact slug passed to the provider's SDK
    let label: String      // shown in the dropdown
    let blurb: String      // shown beneath the dropdown
}

enum Providers {
    static let all: [Provider] = [
        Provider(
            id: "anthropic",
            label: "Anthropic",
            envVar: "ANTHROPIC_API_KEY",
            placeholder: "sk-ant-…",
            signupURL: "https://console.anthropic.com/settings/keys",
            models: [
                ModelOption(
                    id: "claude-sonnet-4-6",
                    label: "Sonnet 4.6 · recommended",
                    blurb: "Best general-purpose balance. Strong quality, fast enough for short rewrites."
                ),
                ModelOption(
                    id: "claude-haiku-4-5-20251001",
                    label: "Haiku 4.5 · fast & cheap",
                    blurb: "About 2× faster and ~3× cheaper than Sonnet. Quality is still excellent for spelling/grammar/Slack."
                ),
                ModelOption(
                    id: "claude-opus-4-7",
                    label: "Opus 4.7 · highest quality",
                    blurb: "Best for nuanced editing or long reports. Slower and more expensive."
                ),
            ]
        ),
        Provider(
            id: "openai",
            label: "OpenAI",
            envVar: "OPENAI_API_KEY",
            placeholder: "sk-…",
            signupURL: "https://platform.openai.com/api-keys",
            models: [
                ModelOption(
                    id: "gpt-4o",
                    label: "GPT-4o · recommended",
                    blurb: "Strong general-purpose model. Comparable to Sonnet in quality."
                ),
                ModelOption(
                    id: "gpt-4o-mini",
                    label: "GPT-4o mini · fast & cheap",
                    blurb: "Fastest and cheapest in the GPT-4o family. Great for short rewrites."
                ),
                ModelOption(
                    id: "gpt-4-turbo",
                    label: "GPT-4 Turbo · high quality",
                    blurb: "Higher quality on complex tasks. Slower and more expensive."
                ),
            ]
        ),
        Provider(
            id: "gemini",
            label: "Google Gemini",
            envVar: "GOOGLE_API_KEY",
            placeholder: "AIzaSy…",
            signupURL: "https://aistudio.google.com/app/apikey",
            models: [
                ModelOption(
                    id: "gemini-2.5-flash",
                    label: "Gemini 2.5 Flash · recommended",
                    blurb: "Fast and very capable. The default Gemini choice for everyday rewrites."
                ),
                ModelOption(
                    id: "gemini-2.5-pro",
                    label: "Gemini 2.5 Pro · highest quality",
                    blurb: "Best Gemini quality. Slower."
                ),
                ModelOption(
                    id: "gemini-2.0-flash",
                    label: "Gemini 2.0 Flash · cheapest",
                    blurb: "Older flash model. Cheapest. Slightly lower quality than 2.5 Flash."
                ),
            ]
        ),
    ]

    static func provider(id: String) -> Provider? {
        all.first { $0.id == id }
    }
}

/// The Whisper models available in the dictation dropdown, plus a
/// helper that picks a sensible default based on the host's RAM.
struct WhisperModelOption {
    let id: String      // matches faster-whisper's expected names
    let label: String
    let blurb: String
    let minRAMGB: Int   // recommended minimum, used for default-picking
    let approxSizeGB: Double
}

enum WhisperModels {
    static let all: [WhisperModelOption] = [
        WhisperModelOption(
            id: "tiny.en",
            label: "Tiny (English only) · smallest",
            blurb: "~75 MB. Fastest, lowest accuracy. For very low-RAM machines.",
            minRAMGB: 4,
            approxSizeGB: 0.1
        ),
        WhisperModelOption(
            id: "base.en",
            label: "Base (English only) · light",
            blurb: "~145 MB. Light footprint, decent for short utterances.",
            minRAMGB: 6,
            approxSizeGB: 0.15
        ),
        WhisperModelOption(
            id: "small.en",
            label: "Small (English only) · balanced",
            blurb: "~470 MB. Good quality, runs comfortably on most Macs.",
            minRAMGB: 8,
            approxSizeGB: 0.5
        ),
        WhisperModelOption(
            id: "medium.en",
            label: "Medium (English only) · high quality",
            blurb: "~1.5 GB. Noticeably better punctuation and edge-case accuracy.",
            minRAMGB: 12,
            approxSizeGB: 1.5
        ),
        WhisperModelOption(
            id: "distil-large-v3",
            label: "Distil Large v3 · recommended",
            blurb: "~1.5 GB on disk (model + cache up to ~3 GB on first download). Multilingual, very accurate, still fast on Apple Silicon. Recommended if your Mac has 16 GB or more of RAM.",
            minRAMGB: 16,
            approxSizeGB: 3.0
        ),
    ]

    /// Picks a default Whisper model for the current Mac based on installed
    /// RAM. Returns the recommended option that the machine can comfortably
    /// run.
    static func defaultForCurrentMac() -> WhisperModelOption {
        let ramGB = SystemInfo.totalRAMGigabytes()
        // Highest-tier model whose minRAMGB still fits in the user's RAM.
        let recommended = all
            .filter { Double($0.minRAMGB) <= ramGB }
            .max { $0.minRAMGB < $1.minRAMGB }
        return recommended ?? all.first!
    }

    static func option(id: String) -> WhisperModelOption? {
        all.first { $0.id == id }
    }
}
