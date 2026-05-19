import Foundation

enum RefinerResult {
    case success(String)
    case failure(String)
}

/// Calls the Python helper that owns the prompt templates and the Anthropic
/// SDK call. JSON in, JSON out. Decoupled from the rest of Swift so prompts
/// can change without recompiling the native daemon.
struct RefinerHelper {
    let pythonPath: String
    let scriptPath: String

    func run(text: String, mode: Int, customPrompt: String?) -> RefinerResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()

            var payload: [String: Any] = ["text": text, "mode": mode]
            if let customPrompt {
                payload["custom_prompt"] = customPrompt
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outputData, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                log("Refiner helper exited \(process.terminationStatus). stdout=\(stdout) stderr=\(stderr)")
                if
                    let helperData = stdout.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: helperData) as? [String: Any],
                    let errorMessage = json["error"] as? String
                {
                    return .failure(errorMessage)
                }
                return .failure(stderr.isEmpty ? "Refiner helper failed." : stderr)
            }

            guard
                let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
                let ok = json["ok"] as? Bool
            else {
                log("Refiner helper returned invalid JSON: \(stdout)")
                return .failure("Invalid refiner helper response.")
            }

            if ok, let text = json["text"] as? String {
                return .success(text)
            }
            return .failure(json["error"] as? String ?? "Unknown refiner error.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
