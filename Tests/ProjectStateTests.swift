import Foundation
@testable import AgentWatchLib

private func makeSession(id: String = "s1", status: Session.Status = .running, timestamp: Int? = nil) -> Session {
    Session(
        sessionId: id,
        project: "test-project",
        cwd: "/tmp/test-project",
        status: status,
        timestamp: timestamp ?? Int(Date().timeIntervalSince1970)
    )
}

@MainActor
func runProjectStateTests() {
    suite("ProjectState Tests")

    test("isIdle when any session is idle") {
        let project = ProjectState(
            name: "test",
            sessions: [
                makeSession(id: "s1", status: .running),
                makeSession(id: "s2", status: .idle),
                makeSession(id: "s3", status: .started)
            ],
            settings: ProjectSettings()
        )
        try expect(project.isIdle, "expected idle")
    }

    test("Not idle when all running/started") {
        let project = ProjectState(
            name: "test",
            sessions: [
                makeSession(id: "s1", status: .running),
                makeSession(id: "s2", status: .started)
            ],
            settings: ProjectSettings()
        )
        try expect(!project.isIdle, "expected not idle")
    }

    test("Idle count accuracy") {
        let project = ProjectState(
            name: "test",
            sessions: [
                makeSession(id: "s1", status: .idle),
                makeSession(id: "s2", status: .running),
                makeSession(id: "s3", status: .idle)
            ],
            settings: ProjectSettings()
        )
        try expectEqual(project.idleCount, 2)
        try expectEqual(project.sessionCount, 3)
    }

    test("Display status shows mixed counts") {
        let mixed = ProjectState(
            name: "test",
            sessions: [
                makeSession(id: "s1", status: .idle),
                makeSession(id: "s2", status: .running)
            ],
            settings: ProjectSettings()
        )
        try expectEqual(mixed.displayStatus, "1 ready / 1 running")

        let allIdle = ProjectState(
            name: "test",
            sessions: [makeSession(id: "s1", status: .idle)],
            settings: ProjectSettings()
        )
        try expectEqual(allIdle.displayStatus, "1 ready")
    }

    test("Display status shows running count") {
        let project = ProjectState(
            name: "test",
            sessions: [
                makeSession(id: "s1", status: .running),
                makeSession(id: "s2", status: .started)
            ],
            settings: ProjectSettings()
        )
        try expectEqual(project.displayStatus, "2 running")
    }

    test("Display status empty") {
        let project = ProjectState(name: "test", sessions: [], settings: ProjectSettings())
        try expectEqual(project.displayStatus, "no sessions")
    }

    test("Stale detection") {
        let oldTimestamp = Int(Date().timeIntervalSince1970) - 600
        let project = ProjectState(
            name: "test",
            sessions: [makeSession(id: "s1", status: .running, timestamp: oldTimestamp)],
            settings: ProjectSettings()
        )
        try expect(project.hasStale, "expected stale")
    }

    test("Default settings") {
        let settings = ProjectSettings()
        try expect(settings.enabled, "default enabled")
        try expectEqual(settings.color, "#34D058")
    }
}
