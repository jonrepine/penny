import Foundation

/// Read-only facts about the host Mac that influence Penny's defaults.
enum SystemInfo {
    /// Installed RAM, in gigabytes (rounded down). Used to recommend a
    /// reasonable Whisper model size on first run.
    static func totalRAMGigabytes() -> Double {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return Double(bytes) / (1024 * 1024 * 1024)
    }
}
