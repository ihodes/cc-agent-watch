import Foundation
@testable import AgentWatchLib

@MainActor
func runSessionTests() {
    suite("Session Tests")

    test("Parse valid session JSON") {
        let json = """
        {"session_id":"abc123","project":"my-app","cwd":"/Users/test/my-app","status":"idle","timestamp":1742567890}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        try expectEqual(session.sessionId, "abc123")
        try expectEqual(session.project, "my-app")
        try expectEqual(session.cwd, "/Users/test/my-app")
        try expectEqual(session.status, .idle)
        try expectEqual(session.timestamp, 1742567890)
    }

    test("Parse all status values") {
        for status in ["started", "running", "idle"] {
            let json = """
            {"session_id":"s1","project":"p","cwd":"/tmp","status":"\(status)","timestamp":100}
            """
            let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
            try expectEqual(session.status.rawValue, status)
        }
    }

    test("Reject malformed JSON") {
        let garbage = Data("not json at all".utf8)
        let session = try? JSONDecoder().decode(Session.self, from: garbage)
        try expectNil(session)
    }

    test("Reject JSON with missing fields") {
        let json = """
        {"session_id":"abc","project":"p"}
        """
        let session = try? JSONDecoder().decode(Session.self, from: Data(json.utf8))
        try expectNil(session)
    }

    test("Reject unknown status value") {
        let json = """
        {"session_id":"s1","project":"p","cwd":"/tmp","status":"unknown","timestamp":100}
        """
        let session = try? JSONDecoder().decode(Session.self, from: Data(json.utf8))
        try expectNil(session)
    }

    test("Stale running session detected") {
        let oldTimestamp = Int(Date().timeIntervalSince1970) - 600
        let json = """
        {"session_id":"s1","project":"p","cwd":"/tmp","status":"running","timestamp":\(oldTimestamp)}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        try expect(session.isStale, "expected stale")
    }

    test("Recent running session not stale") {
        let recentTimestamp = Int(Date().timeIntervalSince1970) - 10
        let json = """
        {"session_id":"s1","project":"p","cwd":"/tmp","status":"running","timestamp":\(recentTimestamp)}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        try expect(!session.isStale, "expected not stale")
    }

    test("Idle session never stale") {
        let oldTimestamp = Int(Date().timeIntervalSince1970) - 600
        let json = """
        {"session_id":"s1","project":"p","cwd":"/tmp","status":"idle","timestamp":\(oldTimestamp)}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        try expect(!session.isStale, "idle should never be stale")
    }

    test("Load session from file") {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let json = """
        {"session_id":"file-test","project":"proj","cwd":"/tmp","status":"idle","timestamp":100}
        """
        let file = tmpDir.appendingPathComponent("file-test.json")
        try json.write(to: file, atomically: true, encoding: .utf8)

        let session = try expectNotNil(Session.load(from: file))
        try expectEqual(session.sessionId, "file-test")
    }

    test("Load returns nil for nonexistent file") {
        let url = URL(fileURLWithPath: "/nonexistent/path/session.json")
        try expectNil(Session.load(from: url))
    }
}
