import ArgumentParser
import Darwin
import Foundation

struct TKitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tkit",
        abstract: "Translate text and configure TranslateKit.",
        version: "0.1.0",
        subcommands: [TranslateCommand.self, ConfigCommand.self, ProvidersCommand.self]
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        throw CleanExit.helpRequest()
    }
}

@main
enum TKitMain {
    static func main() async {
        do {
            var command = try await TKitCommand.asyncParseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let clean as CleanExit {
            TKitCommand.exit(withError: clean)
        } catch let reported as CLIReportedError {
            render(reported)
            Darwin.exit(reported.code)
        } catch {
            switch CLIParserDisposition(error) {
            case .success:
                CLIOutput.stdout(TKitCommand.fullMessage(for: error))
                Darwin.exit(EXIT_SUCCESS)
            case .usage:
                CLIOutput.stderr(TKitCommand.fullMessage(for: error))
                Darwin.exit(CLIExitCode.usage)
            case .application:
                let reported = CLIReportedError(error, json: false)
                render(reported)
                Darwin.exit(reported.code)
            }
        }
    }

    private static func render(_ error: CLIReportedError) {
        if error.json, let data = try? CLIErrorRenderer.json(message: error.message, code: error.code) {
            CLIOutput.stderr(String(decoding: data, as: UTF8.self))
        } else {
            CLIOutput.stderr("Error: \(error.message)")
        }
    }
}

enum CLIParserDisposition: Equatable {
    case success
    case usage
    case application

    init(_ error: Error) {
        switch TKitCommand.exitCode(for: error) {
        case .success: self = .success
        case .validationFailure: self = .usage
        default: self = .application
        }
    }
}
