import SwiftUI

public struct ProjectSettings: Codable, Sendable, Equatable {
    public var enabled: Bool = true
    public var color: String = "#34D058"

    public init(enabled: Bool = true, color: String = "#34D058") {
        self.enabled = enabled
        self.color = color
    }
}

public struct ProjectState: Identifiable, Equatable, Sendable {
    public let name: String
    public var sessions: [Session]
    public var settings: ProjectSettings

    public var id: String { name }

    public var isIdle: Bool {
        sessions.contains { $0.status == .idle }
    }

    public var hasStale: Bool {
        sessions.contains { $0.isStale }
    }

    public var idleCount: Int {
        sessions.filter { $0.status == .idle }.count
    }

    public var sessionCount: Int {
        sessions.count
    }

    public var displayStatus: String {
        if sessions.isEmpty { return "no sessions" }
        let idle = idleCount
        if idle > 0 {
            return "\(idle) idle"
        }
        let running = sessions.filter { $0.status == .running || $0.status == .started }.count
        return "\(running) running"
    }

    public var resolvedColor: Color {
        Color(hex: settings.color) ?? .green
    }

    public init(name: String, sessions: [Session], settings: ProjectSettings) {
        self.name = name
        self.sessions = sessions
        self.settings = settings
    }
}
