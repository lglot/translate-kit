import Darwin
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

    func testCancellationTerminatesAndReapsRunningSubprocess() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-process-cancel-\(UUID().uuidString)")
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-process-pid-\(UUID().uuidString)")
        let runner = ProcessRunner(
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/tmp"]
        )
        let script = """
        import os, signal, sys, time

        pid_file, marker_file = sys.argv[1], sys.argv[2]

        def handle_term(_signal, _frame):
            with open(marker_file, "w") as marker:
                marker.write("terminated")

        signal.signal(signal.SIGTERM, handle_term)
        temporary_pid_file = f"{pid_file}.{os.getpid()}.tmp"
        with open(temporary_pid_file, "w") as handle:
            handle.write(str(os.getpid()))
        os.replace(temporary_pid_file, pid_file)

        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            pass
        """
        let task = Task {
            try await runner.run(
                "/usr/bin/python3",
                arguments: ["-c", script, pidFile.path, marker.path],
                timeout: 30
            )
        }
        defer {
            try? FileManager.default.removeItem(at: marker)
            try? FileManager.default.removeItem(at: pidFile)
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard
            let rawPID = try? String(contentsOf: pidFile, encoding: .utf8),
            let parsedPID = pid_t(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)),
            parsedPID > 0
        else {
            task.cancel()
            _ = try? await task.value
            XCTFail("Subprocess did not report its PID")
            return
        }

        let clock = ContinuousClock()
        let cancellationStarted = clock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThan(cancellationStarted.duration(to: clock.now), .seconds(1))
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        for _ in 0..<100 where isProcessRunning(parsedPID) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let childExitedPromptly = !isProcessRunning(parsedPID)
        XCTAssertTrue(
            childExitedPromptly,
            "Cancelled subprocess PID \(parsedPID) is still alive"
        )
        if !childExitedPromptly {
            for _ in 0..<400 where isProcessRunning(parsedPID) {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        XCTAssertFalse(
            isProcessRunning(parsedPID),
            "Self-limiting test subprocess PID \(parsedPID) did not exit"
        )
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

private func isProcessRunning(_ pid: pid_t) -> Bool {
    errno = 0
    if Darwin.kill(pid, 0) == 0 { return true }
    return errno == EPERM
}
