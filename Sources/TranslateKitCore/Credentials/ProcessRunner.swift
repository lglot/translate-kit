import Darwin
import Foundation

public protocol ProcessRunning: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String
}

public actor ProcessRunner: ProcessRunning {
    private static let supervisorScript = """
    set -m
    child=
    terminate_group() {
        trap - TERM INT
        if [ -z "$child" ]; then
            child=$(jobs -p)
        fi
        if [ -n "$child" ]; then
            kill -TERM -"$child" 2>/dev/null
            (sleep 0.2; kill -KILL -"$child" 2>/dev/null) &
            killer=$!
            wait "$child"
            kill "$killer" 2>/dev/null
            wait "$killer" 2>/dev/null
        fi
        exit 143
    }
    trap terminate_group TERM INT
    "$@" &
    child=$!
    wait "$child"
    status=$?
    trap - TERM INT
    kill -TERM -"$child" 2>/dev/null
    kill -KILL -"$child" 2>/dev/null
    exit "$status"
    """

    private static let allowedEnvironmentNames: Set<String> = [
        "HOME", "PATH", "TMPDIR", "TERM",
        "LANG", "LC_ALL", "LC_CTYPE",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        "SSL_CERT_FILE", "SSL_CERT_DIR",
        "XDG_CONFIG_HOME", "CLOUDSDK_CONFIG", "GOOGLE_APPLICATION_CREDENTIALS",
        "AZURE_CONFIG_DIR"
    ]

    private let environment: [String: String]
    private let maximumOutputBytes: Int

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        maximumOutputBytes: Int = 64 * 1024
    ) {
        self.environment = environment.filter {
            Self.allowedEnvironmentNames.contains($0.key)
        }
        self.maximumOutputBytes = maximumOutputBytes
    }

    public func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 5
    ) async throws -> String {
        try Task.checkCancellation()
        guard let executableURL = locate(executable) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }
        guard timeout > 0 else {
            throw ProcessRunnerError.timedOut(executable)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let collector = BoundedProcessOutput(maximumBytes: maximumOutputBytes)
        let stdoutReader = ProcessPipeReader(collector: collector, stream: .stdout)
        let stderrReader = ProcessPipeReader(collector: collector, stream: .stderr)
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", Self.supervisorScript, "translatekit-process", executableURL.path
        ] + arguments
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutReader.consumeAvailableData(from: handle)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrReader.consumeAvailableData(from: handle)
        }
        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(executable)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        do {
            while process.isRunning {
                if collector.exceededLimit {
                    await stop(process)
                    break
                }
                if Date() >= deadline {
                    timedOut = true
                    await stop(process)
                    break
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        } catch is CancellationError {
            cancelled = true
            await stop(process)
        }

        stdoutReader.stopAcceptingReads()
        stderrReader.stopAcceptingReads()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutReader.waitUntilIdle()
        stderrReader.waitUntilIdle()
        let drainDeadline = Date().addingTimeInterval(0.1)
        drainAvailableData(
            stdout.fileHandleForReading,
            into: collector,
            stream: .stdout,
            until: drainDeadline
        )
        drainAvailableData(
            stderr.fileHandleForReading,
            into: collector,
            stream: .stderr,
            until: drainDeadline
        )

        if cancelled { throw CancellationError() }
        guard !collector.exceededLimit else {
            throw ProcessRunnerError.outputTooLarge(executable)
        }
        if timedOut { throw ProcessRunnerError.timedOut(executable) }
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(executable, process.terminationStatus)
        }
        let data = collector.stdoutData
        guard let value = String(data: data, encoding: .utf8) else {
            throw ProcessRunnerError.invalidOutput(executable)
        }
        return value
    }

    private func stop(_ process: Process) async {
        process.terminate()
        await waitForTermination(process, until: Date().addingTimeInterval(0.5))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        await waitForTermination(process, until: Date().addingTimeInterval(0.5))
    }

    private func waitForTermination(_ process: Process, until deadline: Date) async {
        while process.isRunning, Date() < deadline {
            await Task.detached {
                try? await Task.sleep(for: .milliseconds(10))
            }.value
        }
    }

    private func drainAvailableData(
        _ handle: FileHandle,
        into collector: BoundedProcessOutput,
        stream: BoundedProcessOutput.Stream,
        until deadline: Date
    ) {
        let descriptor = handle.fileDescriptor
        let originalFlags = fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0, fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            return
        }
        defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            guard !collector.exceededLimit, Date() < deadline else { return }
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { return }
            collector.append(Data(buffer.prefix(count)), to: stream)
        }
    }

    private func locate(_ executable: String) -> URL? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? URL(fileURLWithPath: executable) : nil
        }

        var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        directories.append(contentsOf: environment["PATH"]?.split(separator: ":").map(String.init) ?? [])
        for directory in directories {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

private final class ProcessPipeReader: @unchecked Sendable {
    private let condition = NSCondition()
    private let collector: BoundedProcessOutput
    private let stream: BoundedProcessOutput.Stream
    private var acceptsReads = true
    private var activeReads = 0

    init(collector: BoundedProcessOutput, stream: BoundedProcessOutput.Stream) {
        self.collector = collector
        self.stream = stream
    }

    func consumeAvailableData(from handle: FileHandle) {
        condition.lock()
        guard acceptsReads else {
            condition.unlock()
            return
        }
        activeReads += 1
        condition.unlock()

        let data = handle.availableData
        collector.append(data, to: stream)

        condition.lock()
        activeReads -= 1
        if activeReads == 0 { condition.broadcast() }
        condition.unlock()
    }

    func stopAcceptingReads() {
        condition.lock()
        acceptsReads = false
        condition.unlock()
    }

    func waitUntilIdle() {
        condition.lock()
        while activeReads > 0 {
            condition.wait()
        }
        condition.unlock()
    }
}

private final class BoundedProcessOutput: @unchecked Sendable {
    enum Stream {
        case stdout
        case stderr
    }

    private let lock = NSLock()
    private let maximumBytes: Int
    private var standardOutput = Data()
    private var standardError = Data()
    private var exceeded = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ data: Data, to stream: Stream) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !exceeded else { return }
        guard standardOutput.count + standardError.count + data.count <= maximumBytes else {
            exceeded = true
            return
        }
        switch stream {
        case .stdout: standardOutput.append(data)
        case .stderr: standardError.append(data)
        }
    }

    var exceededLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceeded
    }

    var stdoutData: Data {
        lock.lock()
        defer { lock.unlock() }
        return standardOutput
    }
}

public enum ProcessRunnerError: LocalizedError, Equatable {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut(String)
    case outputTooLarge(String)
    case nonZeroExit(String, Int32)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "Executable not found: \(executable)"
        case .launchFailed(let executable):
            return "Could not launch executable: \(executable)"
        case .timedOut(let executable):
            return "Executable timed out: \(executable)"
        case .outputTooLarge(let executable):
            return "Executable returned too much output: \(executable)"
        case .nonZeroExit(let executable, let status):
            return "Executable failed: \(executable) (status \(status))"
        case .invalidOutput(let executable):
            return "Executable returned invalid UTF-8: \(executable)"
        }
    }
}
