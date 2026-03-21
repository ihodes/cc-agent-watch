import Foundation

@MainActor var totalTests = 0
@MainActor var passedTests = 0
@MainActor var failedTests = 0

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int
    var description: String { "\(file):\(line): \(message)" }
}

@MainActor
func suite(_ name: String) {
    print("\n=== \(name) ===")
}

@MainActor
func test(_ name: String, _ body: () throws -> Void) {
    totalTests += 1
    do {
        try body()
        passedTests += 1
        print("  PASS: \(name)")
    } catch {
        failedTests += 1
        print("  FAIL: \(name) — \(error)")
    }
}

func expect(
    _ condition: Bool,
    _ message: String = "assertion failed",
    file: String = #file,
    line: Int = #line
) throws {
    guard condition else {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String = "",
    file: String = #file,
    line: Int = #line
) throws {
    guard actual == expected else {
        let msg = message.isEmpty ? "expected \(expected), got \(actual)" : "\(message): expected \(expected), got \(actual)"
        throw TestFailure(message: msg, file: file, line: line)
    }
}

func expectNil<T>(
    _ value: T?,
    _ message: String = "expected nil",
    file: String = #file,
    line: Int = #line
) throws {
    guard value == nil else {
        throw TestFailure(message: "\(message), got \(value!)", file: file, line: line)
    }
}

func expectNotNil<T>(
    _ value: T?,
    _ message: String = "expected non-nil",
    file: String = #file,
    line: Int = #line
) throws -> T {
    guard let v = value else {
        throw TestFailure(message: message, file: file, line: line)
    }
    return v
}

@MainActor
func runAllTests() {
    runSessionTests()
    runProjectStateTests()
    runHexLayoutTests()
    runAppStateTests()

    print("\n===========================================")
    print("Results: \(passedTests) passed, \(failedTests) failed out of \(totalTests) tests")
    print("===========================================")

    if failedTests > 0 {
        exit(1)
    }
}

@main
struct TestEntryPoint {
    static func main() async {
        await MainActor.run {
            runAllTests()
        }
    }
}
