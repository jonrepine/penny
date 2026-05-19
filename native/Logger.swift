import Foundation

/// Append `message` to the user's penny.log file. We write directly
/// rather than through `print` because Swift's stdout is block-buffered when
/// the process isn't attached to a tty, and even `fflush(stdout)` was
/// proving unreliable when the daemon was launched directly outside launchd.
func log(_ message: String) {
    let line = message + "\n"
    let logPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".penny/refiner.log")
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        let dir = (logPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}
