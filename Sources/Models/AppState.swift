import SwiftUI
import Combine

@Observable
@MainActor
public final class AppState {
    public var projects: [ProjectState] = []
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

    /// Projects that are enabled, sorted alphabetically — used for menubar rendering.
    public var enabledProjects: [ProjectState] {
        projects.filter { $0.settings.enabled }.sorted { $0.name < $1.name }
    }

    public init() {
        let defaultDir = NSHomeDirectory() + "/.claude-monitor/sessions"
        self.monitorDirectory = UserDefaults.standard.string(forKey: "monitorDirectory") ?? defaultDir
        self.projectSettings = Self.loadProjectSettings()
    }

    // MARK: - Session file loading

    public func loadSessions() {
        let url = URL(fileURLWithPath: monitorDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            projects = rebuildProjects(from: [])
            return
        }

        let sessions = contents
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { Session.load(from: $0) }

        projects = rebuildProjects(from: sessions)
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

    public func toggleProject(named name: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.enabled.toggle()
        projectSettings[name] = settings
        refreshProjectSettings()
    }

    public func setColor(for name: String, hex: String) {
        var settings = projectSettings[name] ?? ProjectSettings()
        settings.color = hex
        projectSettings[name] = settings
        refreshProjectSettings()
    }

    public func setColor(for name: String, color: Color) {
        let hex = color.toHex() ?? "#34D058"
        setColor(for: name, hex: hex)
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
