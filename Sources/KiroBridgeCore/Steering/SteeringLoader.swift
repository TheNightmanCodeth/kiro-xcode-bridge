import Foundation

/// Loads Kiro steering files and provides them for injection into system prompts.
///
/// Steering files are Markdown files in `.kiro/steering/` (project) and
/// `~/.kiro/steering/` (global). Files with `inclusion: manual` in their
/// front matter are skipped. All others are concatenated and returned.
///
/// Hot-reload: changes take effect on the next request without restarting.
final class SteeringLoader: @unchecked Sendable {
    let projectPath: String

    private var cachedRules: String = ""
    private let lock = NSLock()
    private var watcher: FileWatcher?

    init(projectPath: String) {
        self.projectPath = projectPath
        refreshCache()
        setupWatcher()
    }

    /// Returns the current steering rules (concatenated Markdown, front matter stripped).
    var rules: String {
        lock.lock()
        defer { lock.unlock() }
        return cachedRules
    }

    // MARK: - Private

    private func setupWatcher() {
        let w = FileWatcher { [weak self] in self?.refreshCache() }

        let global = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kiro/steering")
        let workspace = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".kiro/steering")

        if FileManager.default.fileExists(atPath: global.path) {
            w.watch(directory: global)
        }
        if FileManager.default.fileExists(atPath: workspace.path) {
            w.watch(directory: workspace)
        }

        watcher = w
    }

    private func refreshCache() {
        let rules = load()
        lock.lock()
        cachedRules = rules
        lock.unlock()
    }

    private func load() -> String {
        var parts: [String] = []

        // Global steering first
        let globalDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kiro/steering")
        parts.append(contentsOf: loadDir(globalDir))

        // Workspace steering second (can override/extend global)
        let workspaceDir = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".kiro/steering")
        parts.append(contentsOf: loadDir(workspaceDir))

        return parts.joined(separator: "\n\n---\n\n")
    }

    private func loadDir(_ dir: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        return files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> String? in
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let fm = FrontMatterParser.parse(raw)
                // Skip manual-only files
                if fm.inclusion == "manual" { return nil }
                return fm.body.isEmpty ? nil : fm.body
            }
    }
}
