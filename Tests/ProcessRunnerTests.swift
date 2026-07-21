import Foundation
import XCTest
@testable import TranslateKitCore

final class ProcessRunnerTests: XCTestCase {
    func testSubprocessReceivesMinimalEnvironmentWithoutProviderSecrets() async throws {
        let runner = ProcessRunner(environment: [
            "PATH": "/usr/bin:/bin",
            "HOME": "/tmp/translatekit-process-home",
            "CLOUDSDK_CONFIG": "/tmp/translatekit-gcloud",
            "DEEPL_AUTH_KEY": "must-not-leak",
            "AWS_SECRET_ACCESS_KEY": "must-not-leak-either"
        ])

        let output = try await runner.run("/usr/bin/env", arguments: [], timeout: 2)

        XCTAssertTrue(output.contains("HOME=/tmp/translatekit-process-home"))
        XCTAssertTrue(output.contains("CLOUDSDK_CONFIG=/tmp/translatekit-gcloud"))
        XCTAssertFalse(output.contains("must-not-leak"))
        XCTAssertFalse(output.contains("AWS_SECRET_ACCESS_KEY"))
    }

    func testOutputLimitStopsChattyProcessBeforeTimeout() async {
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"],
            maximumOutputBytes: 1_024
        )
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await runner.run("/usr/bin/yes", arguments: [], timeout: 3)
            XCTFail("Expected output limit failure")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .outputTooLarge("/usr/bin/yes"))
        }

        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }

    func testCancellationTerminatesRunningSubprocess() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-process-cancel-\(UUID().uuidString)")
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"]
        )
        let command = "trap 'printf terminated > \(marker.path)' TERM; while :; do :; done"
        let task = Task {
            try await runner.run("/bin/sh", arguments: ["-c", command], timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(50))

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        try? FileManager.default.removeItem(at: marker)
    }

    func testAlreadyCancelledTaskDoesNotLaunchSubprocess() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-process-pre-cancel-\(UUID().uuidString)")
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"]
        )
        let command = "printf started > \(marker.path)"
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run("/bin/sh", arguments: ["-c", command], timeout: 2)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testZeroTimeoutDoesNotLaunchSubprocess() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-process-zero-timeout-\(UUID().uuidString)")
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"]
        )

        do {
            _ = try await runner.run(
                "/bin/sh",
                arguments: ["-c", "printf started > \(marker.path)"],
                timeout: 0
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .timedOut("/bin/sh"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCompletedCommandDoesNotWaitForDescendantHoldingOutputPipes() async throws {
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"]
        )
        let clock = ContinuousClock()
        let start = clock.now

        _ = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "sleep 5 &"],
            timeout: 1
        )

        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }

    func testFinalDrainStopsWhenDetachedDescendantKeepsWriting() async {
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"],
            maximumOutputBytes: 1_024
        )
        let script = """
        import os, time
        pid = os.fork()
        if pid == 0:
            os.setsid()
            end = time.monotonic() + 1.5
            chunk = b"x" * 4096
            while time.monotonic() < end:
                try:
                    os.write(1, chunk)
                except BrokenPipeError:
                    break
            os._exit(0)
        os._exit(0)
        """
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await runner.run("/usr/bin/python3", arguments: ["-c", script], timeout: 1)
            XCTFail("Expected output limit failure")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .outputTooLarge("/usr/bin/python3"))
        }

        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }

    func testCapturesAllOutputWrittenImmediatelyBeforeExit() async throws {
        let expected = String(repeating: "line-before-exit\n", count: 3_000)
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"],
            maximumOutputBytes: 128 * 1_024
        )

        let output = try await runner.run(
            "/usr/bin/python3",
            arguments: ["-c", "import os; os.write(1, \(String(reflecting: expected)).encode())"],
            timeout: 2
        )

        XCTAssertEqual(output, expected)
    }
}
