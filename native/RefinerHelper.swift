import Foundation

enum RefinerResult {
    case success(String)
    case failure(String)
}

/// Calls the Python helper that owns the prompt templates and the LLM SDK
/// calls. JSON in, JSON out. Decoupled from the rest of Swift so prompts can
/// change without recompiling the native daemon.
///
/// API keys are read from Keychain on the Swift side and pushed into the
/// subprocess via env vars, so the user only ever sees one "Always Allow"
/// Keychain prompt (for Penny itself) instead of one per Python invocation.
struct RefinerHelper {
    let pythonPath: String
    let scriptPath: String

    /// Result of an `extract_rules` action against the Python helper.
    enum ExtractionResult {
        case success([String])
        case failure(String)
    }

    /// Runs the prompt engineer's extraction prompt against the user's
    /// examples and returns the extracted rules. Persistence happens on the
    /// helper side; this just returns the rules for the UI to display.
    func extractRules(
        mode: Int,
        modeName: String,
        modeIntent: String,
        modeBasePrompt: String,
        examples: [String]
    ) -> ExtractionResult {
        let payload: [String: Any] = [
            "action": "extract_rules",
            "mode": mode,
            "mode_name": modeName,
            "mode_intent": modeIntent,
            "mode_base_prompt": modeBasePrompt,
            "examples": examples,
        ]

        let raw = runHelper(payload: payload)
        switch raw {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            if let rules = json["rules"] as? [String] {
                return .success(rules)
            }
            return .failure("Extraction returned no rules array")
        }
    }

    func run(text: String, mode: Int, customPrompt: String?) -> RefinerResult {
        var payload: [String: Any] = [
            "action": "refine",
            "text": text,
            "mode": mode,
        ]
        if let customPrompt {
            payload["custom_prompt"] = customPrompt
        }

        switch runHelper(payload: payload) {
        case .failure(let error):
            return .failure(error)
        case .success(let json):
            if json["ok"] as? Bool == true, let text = json["text"] as? String {
                return .success(text)
            }
            return .failure(json["error"] as? String ?? "Unknown refiner error.")
        }
    }

    // MARK: Private

    private enum HelperOutcome {
        case success([String: Any])
        case failure(String)
    }

    /// Shared subprocess execution path used by both `run` (refinement) and
    /// `extractRules`. Handles env-var injection, JSON serialization, and
    /// stderr capture.
    private func runHelper(payload: [String: Any]) -> HelperOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]

        var environment = ProcessInfo.processInfo.environment
        let providerEnvVars: [String: String] = [
            "anthropic": "ANTHROPIC_API_KEY",
            "openai":    "OPENAI_API_KEY",
            "gemini":    "GOOGLE_API_KEY",
        ]
        for (provider, envVar) in providerEnvVars {
            if let key = Keychain.read(account: provider), !key.isEmpty {
                environment[envVar] = key
            }
        }
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            let data = try JSONSerialization.data(withJSONObject: payload)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outputData, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                log("Helper exited \(process.terminationStatus). stdout=\(stdout) stderr=\(stderr)")
                if
                    let helperData = stdout.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: helperData) as? [String: Any],
                    let errorMessage = json["error"] as? String
                {
                    return .failure(errorMessage)
                }
                return .failure(stderr.isEmpty ? "Helper failed." : stderr)
            }

            guard let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
                log("Helper returned invalid JSON: \(stdout)")
                return .failure("Invalid helper response.")
            }
            return .success(json)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
