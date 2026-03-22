import Foundation
@testable import AgentWatchLib

private func createTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentwatch-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeSession(to dir: URL, id: String, project: String, status: String, timestamp: Int? = nil) throws {
    let ts = timestamp ?? Int(Date().timeIntervalSince1970)
    let json = """
    {"session_id":"\(id)","project":"\(project)","cwd":"/tmp/\(project)","status":"\(status)","timestamp":\(ts)}
    """
    let file = dir.appendingPathComponent("\(id).json")
    try json.write(to: file, atomically: true, encoding: .utf8)
}

@MainActor
func runAppStateTests() {
    suite("AppState Tests")

    test("Load sessions from directory") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeSession(to: dir, id: "s1", project: "alpha", status: "running")
        try writeSession(to: dir, id: "s2", project: "alpha", status: "idle")
        try writeSession(to: dir, id: "s3", project: "beta", status: "running")

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        try expectEqual(state.projects.count, 2)
        let alpha = state.projects.first { $0.name == "alpha" }
        let beta = state.projects.first { $0.name == "beta" }

        let a = try expectNotNil(alpha)
        try expectEqual(a.sessionCount, 2)
        try expect(a.isIdle, "alpha should be idle")

        let b = try expectNotNil(beta)
        try expectEqual(b.sessionCount, 1)
        try expect(!b.isIdle, "beta should not be idle")
    }

    test("Projects sorted alphabetically") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeSession(to: dir, id: "s1", project: "zebra", status: "running")
        try writeSession(to: dir, id: "s2", project: "alpha", status: "idle")
        try writeSession(to: dir, id: "s3", project: "middle", status: "running")

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        let names = state.projects.map(\.name)
        try expectEqual(names, ["alpha", "middle", "zebra"])
    }

    test("Enabled projects filter") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let projName = "zzz-disabled-\(UUID().uuidString)"
        let enabledName = "zzz-enabled-\(UUID().uuidString)"
        try writeSession(to: dir, id: "s1", project: enabledName, status: "running")
        try writeSession(to: dir, id: "s2", project: projName, status: "running")

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        // Ensure it starts enabled, then disable it
        let proj = state.projects.first { $0.name == projName }
        try expect(proj?.settings.enabled == true, "should start enabled")

        state.toggleProject(named: projName)

        let enabled = state.enabledProjects
        let enabledNames = enabled.map(\.name)
        try expect(enabledNames.contains(enabledName), "enabled project should be in list")
        try expect(!enabledNames.contains(projName), "disabled project should not be in list")
    }

    test("Ignores dotfiles") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeSession(to: dir, id: "real-session", project: "proj", status: "running")
        let dotfile = dir.appendingPathComponent(".tmp.abc123")
        try "garbage".write(to: dotfile, atomically: true, encoding: .utf8)

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        try expectEqual(state.projects.count, 1)
        try expectEqual(state.projects.first?.sessionCount, 1)
    }

    test("Empty directory produces no projects") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        try expect(state.projects.isEmpty, "expected empty")
    }

    test("Nonexistent directory produces no projects") {
        let state = AppState()
        state.monitorDirectory = "/nonexistent/path/sessions"
        state.loadSessions()

        try expect(state.projects.isEmpty, "expected empty")
    }

    test("Projects persist after sessions removed") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeSession(to: dir, id: "s1", project: "persistent-proj", status: "running")

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        try expectEqual(state.projects.count, 1)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("s1.json"))
        state.loadSessions()

        try expectEqual(state.projects.count, 1)
        try expectEqual(state.projects.first?.sessionCount, 0)
    }

    test("Stale session detection") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldTimestamp = Int(Date().timeIntervalSince1970) - 400 // 6.6 min: stale (>5m) but not cleanup (>10m)
        try writeSession(to: dir, id: "s1", project: "stale-proj", status: "running", timestamp: oldTimestamp)

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        let proj = state.projects.first { $0.name == "stale-proj" }
        try expect(proj?.hasStale == true, "expected stale")
    }

    test("Toggle project on and off") {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeSession(to: dir, id: "s1", project: "toggle-proj", status: "running")

        let state = AppState()
        state.monitorDirectory = dir.path
        state.loadSessions()

        try expect(state.projects.first?.settings.enabled == true, "initially enabled")

        state.toggleProject(named: "toggle-proj")
        try expect(state.projects.first?.settings.enabled == false, "should be disabled")

        state.toggleProject(named: "toggle-proj")
        try expect(state.projects.first?.settings.enabled == true, "should be re-enabled")
    }
}
