import Foundation
import XCTest

final class CLIIntegrationTests: XCTestCase {
    func testRootConfigOptionDrivesRealConfigurationWorkflow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-cli-integration-\(UUID().uuidString)", isDirectory: true)
        let configurationURL = directory.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: directory) }

        let initialized = try runTKit([
            "--config", configurationURL.path,
            "config", "init"
        ])
        XCTAssertEqual(initialized.status, 0, initialized.stderr)
        XCTAssertEqual(initialized.stdout, configurationURL.path + "\n")

        let set = try runTKit([
            "--config", configurationURL.path,
            "config", "set", "translation.provider", "libretranslate"
        ])
        XCTAssertEqual(set.status, 0, set.stderr)

        let get = try runTKit([
            "--config", configurationURL.path,
            "config", "get", "translation.provider"
        ])
        XCTAssertEqual(get.status, 0, get.stderr)
        XCTAssertEqual(get.stdout, "libretranslate\n")

        let show = try runTKit([
            "--config", configurationURL.path,
            "config", "show", "--json"
        ])
        XCTAssertEqual(show.status, 0, show.stderr)
        let shown = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(show.stdout.utf8)) as? [String: Any]
        )
        XCTAssertNotNil(shown["configuration"])
        XCTAssertNotNil(shown["providers"])

        let providers = try runTKit([
            "--config", configurationURL.path,
            "providers", "list", "--json"
        ])
        XCTAssertEqual(providers.status, 0, providers.stderr)
        let providerList = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(providers.stdout.utf8)) as? [[String: Any]]
        )
        XCTAssertEqual(providerList.count, 6)

        let unset = try runTKit([
            "--config", configurationURL.path,
            "config", "unset", "translation.provider"
        ])
        XCTAssertEqual(unset.status, 0, unset.stderr)
        let resetProvider = try runTKit([
            "--config", configurationURL.path,
            "config", "get", "translation.provider"
        ])
        XCTAssertEqual(resetProvider.stdout, "apple\n")

        let discovery = try runTKit(["config", "discover", "apple", "--json"])
        XCTAssertEqual(discovery.status, 0, discovery.stderr)
        XCTAssertTrue(discovery.stdout.contains(#""provider" : "apple""#))

        let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testRealCLIUsesUsageExitCodeForUnknownOption() throws {
        let result = try runTKit(["--unknown-option"])

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("Unknown option"))
        XCTAssertTrue(result.stdout.isEmpty)
    }

    func testRealCLIReadsStdinAndWritesStructuredErrorsOnlyToStderr() throws {
        let missingConfiguration = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-missing-\(UUID().uuidString).toml")

        let result = try runTKit(
            ["--config", missingConfiguration.path, "translate", "--json"],
            stdin: "Hello from stdin\n"
        )

        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.stdout.isEmpty)
        let error = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stderr.utf8)) as? [String: Any]
        )
        XCTAssertEqual(error["exit_code"] as? Int, 3)
        XCTAssertNotNil(error["error"] as? String)
        XCTAssertFalse(result.stderr.contains("Hello from stdin"))
    }

    func testRealCLIHelpIsSuccessful() throws {
        let result = try runTKit(["--help"])

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("USAGE: tkit"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    private func runTKit(_ arguments: [String], stdin input: String? = nil) throws -> (
        status: Int32,
        stdout: String,
        stderr: String
    ) {
        let executable = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("tkit")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: executable.path),
            "Missing tkit test executable at \(executable.path)"
        )

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        let standardInput = input.map { _ in Pipe() }
        if let standardInput { process.standardInput = standardInput }
        try process.run()
        if let input, let standardInput {
            standardInput.fileHandleForWriting.write(Data(input.utf8))
            try standardInput.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
