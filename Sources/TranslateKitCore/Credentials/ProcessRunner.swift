import Foundation

public protocol ProcessRunning: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String
}

public actor ProcessRunner: ProcessRunning {
    private let environment: [String: String]
    private let maximumOutputBytes: Int

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        maximumOutputBytes: Int = 64 * 1024
    ) {
        self.environment = environment
        self.maximumOutputBytes = maximumOutputBytes
    }

    public func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 5
    ) async throws -> String {
        guard let executableURL = locate(executable) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(executable)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        if process.isRunning {
            process.terminate()
            throw ProcessRunnerError.timedOut(executable)
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= maximumOutputBytes else {
            throw ProcessRunnerError.outputTooLarge(executable)
        }
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(executable, process.terminationStatus)
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw ProcessRunnerError.invalidOutput(executable)
        }
        return value
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
