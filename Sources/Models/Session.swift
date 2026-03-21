import Foundation

public struct Session: Codable, Sendable, Identifiable, Equatable {
    public let sessionId: String
    public let project: String
    public let cwd: String
    public let status: Status
    public let timestamp: Int

    public var id: String { sessionId }

    public enum Status: String, Codable, Sendable {
        case started
        case running
        case idle
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case project
        case cwd
        case status
        case timestamp
    }

    /// A session is stale if it has been in `running` status for over 5 minutes.
    public var isStale: Bool {
        status == .running && Date().timeIntervalSince1970 - Double(timestamp) > 300
    }

    public static func load(from url: URL) -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public init(sessionId: String, project: String, cwd: String, status: Status, timestamp: Int) {
        self.sessionId = sessionId
        self.project = project
        self.cwd = cwd
        self.status = status
        self.timestamp = timestamp
    }
}
