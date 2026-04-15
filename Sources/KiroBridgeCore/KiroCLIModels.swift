import Foundation

/// Fetches available models from `kiro-cli chat --list-models`.
/// Returns nil if kiro-cli is not installed or the output can't be parsed.
enum KiroCLIModels {
    static func fetch(verbose: Bool = false) -> [OpenAIModel]? {
        guard let kiroPath = findKiroCLI() else {
            if verbose { fputs("kiro-bridge: kiro-cli not found, using built-in model list\n", stderr) }
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kiroPath)
        process.arguments = ["chat", "--list-models"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            if verbose { fputs("kiro-bridge: kiro-cli failed to run: \(error)\n", stderr) }
            return nil
        }

        guard process.terminationStatus == 0 else {
            if verbose { fputs("kiro-bridge: kiro-cli exited \(process.terminationStatus)\n", stderr) }
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let models = parse(output)
        if models.isEmpty { return nil }
        return models
    }

    // MARK: - Private

    private static func parse(_ output: String) -> [OpenAIModel] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip header and blank lines
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Available") else { return nil }
            // Strip leading "* " default marker
            let rest = trimmed.hasPrefix("*")
                ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                : trimmed
            // First whitespace-delimited token is the model ID
            let id = rest.components(separatedBy: .whitespaces).first ?? ""
            return id.isEmpty ? nil : OpenAIModel(id: id)
        }
    }

    private static func findKiroCLI() -> String? {
        // Common install locations (including Homebrew and ~/.local/bin)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let candidates = [
            "\(home)/.local/bin/kiro-cli",
            "/usr/local/bin/kiro-cli",
            "/opt/homebrew/bin/kiro-cli",
            "/usr/bin/kiro-cli",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        // Fall back to `which`
        let pipe = Pipe()
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["kiro-cli"]
        which.standardOutput = pipe
        which.standardError = Pipe()
        try? which.run()
        which.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }
}
