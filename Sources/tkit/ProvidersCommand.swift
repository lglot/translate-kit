import ArgumentParser
import Foundation
import TranslateKitCore

struct ProvidersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "providers",
        abstract: "Inspect translation providers.",
        subcommands: [List.self]
    )

    @ParentCommand var root: TKitCommand

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        @ParentCommand var parent: ProvidersCommand
        @OptionGroup var global: GlobalOptions
        @Flag(name: .long) var json = false

        mutating func run() async throws {
            do {
                let configuration = try options.store.load()
                let states = await CLIEnvironment.registry().states(configuration: configuration)
                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    CLIOutput.stdout(try encoder.encode(states))
                } else {
                    for state in states {
                        let sources = state.credentialSources.map(\.rawValue).joined(separator: ",")
                        CLIOutput.stdout(
                            "\(state.descriptor.id.rawValue)\t\(state.descriptor.name)\tprivacy=\(state.descriptor.privacy.rawValue)\tavailable=\(state.isAvailable)\tconfigured=\(state.isConfigured)\tsources=\(sources)\n"
                        )
                    }
                }
            } catch {
                throw CLIReportedError(error, json: json)
            }
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }
}
