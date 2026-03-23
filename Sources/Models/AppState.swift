import SwiftUI
import AppKit
import Combine

@Observable
@MainActor
public final class AppState {
    public var projects: [ProjectState] = []
    /// Tracks which projects were idle last time we checked, for transition detection.
    private var previouslyIdle: Set<String> = []
    public var monitorDirectory: String {
        didSet {
            UserDefaults.standard.set(monitorDirectory, forKey: "monitorDirectory")
        }
    }
    public private(set) var projectSettings: [String: ProjectSettings] = [:] {
        didSet {
            persistProjectSettings()
        }
    }
    public var isConfigWindowVisible = false
    public var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "isPaused")
        }
    }

    /// Projects that are enabled, not hidden, and have active sessions — used for menubar rendering.
    public var enabledProjects: [ProjectState] {
        if isPaused { return [] }
        return projects.filter { $0.settings.enabled && !$0.settings.hidden && $0.sessionCount > 0 }.sorted { $0.name < $1.name }
    }

    public init() {
        let defaultDir = NSHomeDirectory() + "/.claude-monitor/sessions"
        self.monitorDirectory = UserDefaults.standard.string(forKey: "monitorDirectory") ?? defaultDir
        self.isPaused = UserDefaults.standard.bool(forKey: "isPaused")
        self.projectSettings = Self.loadProjectSettings()
    }

    // MARK: - Session file loading

    /// Stale sessions older than this (in seconds) are auto-deleted.
    private static let staleCleanupThreshold: Double = 600 // 10 minutes

    public func loadSessions() {
        let url = URL(fileURLWithPath: monitorDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            projects = rebuildProjects(from: [])
            return
        }

        let jsonFiles = contents
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }

        var liveSessions: [Session] = []
        let now = Date().timeIntervalSince1970

        for file in jsonFiles {
            guard let session = Session.load(from: file) else { continue }
            // Auto-cleanup: remove session files stuck in running/started for too long
            if (session.status == .running || session.status == .started)
                && now - Double(session.timestamp) > Self.staleCleanupThreshold {
                try? FileManager.default.removeItem(at: file)
            } else {
                liveSessions.append(session)
            }
        }

        let oldIdle = previouslyIdle
        projects = rebuildProjects(from: liveSessions)
        syncAgentConfigs()
        refreshProjectSettings()
        playIdleSounds(previouslyIdle: oldIdle)
    }

    private func rebuildProjects(from sessions: [Session]) -> [ProjectState] {
        var grouped: [String: [Session]] = [:]
        for session in sessions {
            grouped[session.project, default: []].append(session)
        }

        // Preserve previously-seen projects (they persist until app restart)
        var projectNames = Set(grouped.keys)
        for existing in projects {
            projectNames.insert(existing.name)
        }

        return projectNames.sorted().map { name in
            let settings = projectSettings[name] ?? ProjectSettings()
            return ProjectState(
                name: name,
                sessions: grouped[name] ?? [],
                settings: settings
            )
        }
    }

    // MARK: - Project settings

    public func togglePause() {
        isPaused.toggle()
    }

    public func toggleSound(named name: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.soundEnabled.toggle()
        projectSettings[name] = settings
        refreshProjectSettings()
        if settings.soundEnabled {
            playSound(settings.soundName)
        }
    }

    public func setSound(for name: String, sound: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.soundName = sound
        settings.soundEnabled = true
        projectSettings[name] = settings
        refreshProjectSettings()
        playSound(sound)
    }

    public static let systemSounds = [
        "Glass", "Ping", "Tink", "Pop", "Purr", "Hero",
        "Blow", "Bottle", "Frog", "Funk", "Morse",
        "Sosumi", "Submarine", "Basso"
    ]

    public func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func playIdleSounds(previouslyIdle oldIdle: Set<String>) {
        guard !isPaused else {
            previouslyIdle = Set(projects.filter { $0.isIdle }.map(\.name))
            return
        }
        let nowIdle = Set(projects.filter { $0.isIdle && $0.settings.enabled }.map(\.name))
        let newlyIdle = nowIdle.subtracting(oldIdle)
        for name in newlyIdle {
            let settings = projectSettings[name] ?? ProjectSettings()
            if settings.soundEnabled {
                playSound(settings.soundName)
            }
        }
        previouslyIdle = nowIdle
    }

    public func toggleProject(named name: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.enabled.toggle()
        projectSettings[name] = settings
        refreshProjectSettings()
    }

    /// Remove a project from the list (deletes its session files). It'll reappear if hooks fire again.
    public func removeProject(named name: String) {
        // Delete session files for this project
        let dir = URL(fileURLWithPath: monitorDirectory)
        for project in projects where project.name == name {
            for session in project.sessions {
                let file = dir.appendingPathComponent("\(session.sessionId).json")
                try? FileManager.default.removeItem(at: file)
            }
        }
        // Remove from in-memory list
        projects.removeAll { $0.name == name }
    }

    /// Permanently hide a project. It won't show in the main list but appears in settings.
    public func hideProject(named name: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.hidden = true
        projectSettings[name] = settings
        refreshProjectSettings()
    }

    /// Unhide a previously hidden project.
    public func unhideProject(named name: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.hidden = false
        projectSettings[name] = settings
        refreshProjectSettings()
    }

    /// Projects that are not hidden, for the main popover.
    public var visibleProjects: [ProjectState] {
        projects.filter { !$0.settings.hidden }.sorted { $0.name < $1.name }
    }

    /// Projects that are hidden, for the settings window.
    public var hiddenProjects: [ProjectState] {
        projects.filter { $0.settings.hidden }.sorted { $0.name < $1.name }
    }

    public func setColor(for name: String, hex: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.color = hex
        projectSettings[name] = settings
        refreshProjectSettings()
        writeAgentConfigIfExists(for: name, hex: hex)
    }

    public func setColor(for name: String, color: Color) {
        let hex = color.toHex() ?? "#34D058"
        setColor(for: name, hex: hex)
    }

    // MARK: - .agent-config.yaml

    /// Returns the git root path for a project by checking its sessions' cwd.
    private func projectRoot(for name: String) -> String? {
        guard let cwd = projects.first(where: { $0.name == name })?.sessions.first?.cwd else {
            return nil
        }
        return cwd
    }

    /// Read color from .agent-config.yaml if it exists at the project root.
    private func readAgentConfig(for name: String) -> String? {
        guard let root = projectRoot(for: name) else { return nil }
        let configPath = (root as NSString).appendingPathComponent(".agent-config.yaml")
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        // Parse "color: \"#hex\"" from YAML
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("color:") {
                let value = trimmed.dropFirst("color:".count).trimmingCharacters(in: .whitespaces)
                // Strip quotes
                let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if hex.hasPrefix("#") { return hex }
            }
        }
        return nil
    }

    /// Write color to .agent-config.yaml only if the file already exists.
    private func writeAgentConfigIfExists(for name: String, hex: String) {
        guard let root = projectRoot(for: name) else { return }
        let configPath = (root as NSString).appendingPathComponent(".agent-config.yaml")
        guard FileManager.default.fileExists(atPath: configPath) else { return }
        let content = "color: \"\(hex)\"\n"
        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Apply .agent-config.yaml colors for all projects that have the file.
    private func syncAgentConfigs() {
        for project in projects {
            if let hex = readAgentConfig(for: project.name),
               hex != projectSettings[project.name]?.color {
                var settings = projectSettings[project.name] ?? ProjectSettings()
                settings.color = hex
                projectSettings[project.name] = settings
            }
        }
    }

    private func refreshProjectSettings() {
        projects = projects.map { project in
            var p = project
            p.settings = projectSettings[p.name] ?? ProjectSettings()
            return p
        }
    }

    // MARK: - Persistence

    private static func loadProjectSettings() -> [String: ProjectSettings] {
        guard let data = UserDefaults.standard.data(forKey: "projectSettings"),
              let dict = try? JSONDecoder().decode([String: ProjectSettings].self, from: data)
        else { return [:] }
        return dict
    }

    private func persistProjectSettings() {
        if let data = try? JSONEncoder().encode(projectSettings) {
            UserDefaults.standard.set(data, forKey: "projectSettings")
        }
    }
}
