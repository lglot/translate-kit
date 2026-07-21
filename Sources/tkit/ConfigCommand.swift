import ArgumentParser
import Foundation
import TranslateKitCore

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Inspect and update TranslateKit configuration.",
        subcommands: [
            Init.self, Path.self, Show.self, Get.self, Set.self, Unset.self,
            Discover.self, Import.self, SetKey.self, DeleteKey.self
        ]
    )

    @ParentCommand var root: TKitCommand

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "init")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions

        mutating func run() throws {
            _ = try options.store.loadOrCreate()
            CLIOutput.stdout(options.configurationURL.path + "\n")
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "path")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions

        mutating func run() {
            CLIOutput.stdout(options.configurationURL.path + "\n")
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Flag(name: .long) var json = false

        mutating func run() async throws {
            do {
                let configuration = try options.store.load()
                if json {
                    let states = await CLIEnvironment.registry().states(configuration: configuration)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    CLIOutput.stdout(try encoder.encode(ConfigurationView(
                        configuration: configuration,
                        providers: states
                    )))
                } else {
                    CLIOutput.stdout(try String(contentsOf: options.configurationURL, encoding: .utf8))
                }
            } catch {
                throw CLIReportedError(error, json: json)
            }
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var key: String

        mutating func run() throws {
            let configuration = try options.store.load()
            CLIOutput.stdout(try ConfigurationEditor.get(key, from: configuration) + "\n")
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var key: String
        @Argument var value: String

        mutating func run() throws {
            var configuration = try options.store.load()
            try ConfigurationEditor.set(key, value: value, in: &configuration)
            try options.store.save(configuration)
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Unset: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unset")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var key: String

        mutating func run() throws {
            var configuration = try options.store.load()
            try ConfigurationEditor.unset(key, in: &configuration)
            try options.store.save(configuration)
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Discover: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "discover")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var provider: String?
        @Flag(name: .long) var json = false

        mutating func run() async throws {
            do {
                let resolver = CredentialResolver()
                let providers = try provider.map { [try parseProvider($0)] } ?? ProviderID.allCases
                var discoveries: [CredentialDiscovery] = []
                for provider in providers {
                    discoveries.append(try await resolver.discover(provider: provider))
                }
                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    CLIOutput.stdout(try encoder.encode(discoveries))
                } else {
                    for item in discoveries {
                        let sources = item.sources.map(\.rawValue).joined(separator: ",")
                        let profiles = item.profiles.isEmpty ? "" : " profiles=\(item.profiles.joined(separator: ","))"
                        CLIOutput.stdout("\(item.provider.rawValue)\tavailable=\(item.isAvailable)\tsources=\(sources)\(profiles)\n")
                    }
                }
            } catch {
                throw CLIReportedError(error, json: json)
            }
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "import")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var provider: String

        mutating func run() async throws {
            let provider = try parseProvider(provider)
            let configuration = try options.store.load()
            let resolver = CredentialResolver()
            let credential = try await resolver.resolve(for: provider, configuration: configuration)
            guard case .apiKey(let key) = credential else {
                throw CLIInputError.unsupportedImport(provider.rawValue)
            }
            try resolver.store(key, for: provider)
        }

        private var options: GlobalOptions { global.resolved(with: parent.root.global) }
    }

    struct SetKey: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set-key")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var provider: String

        mutating func run() throws {
            let provider = try parseProvider(provider)
            let resolver = CredentialResolver()
            guard provider != .apple else {
                throw CLIInputError.unsupportedImport(provider.rawValue)
            }
            if provider == .aws {
                let values = try SecretInput.readAWS()
                try resolver.storeAWSStatic(
                    accessKeyID: values.0,
                    secretAccessKey: values.1,
                    sessionToken: values.2
                )
                return
            }
            let key = try SecretInput.readOne(prompt: "\(provider.rawValue) API key: ")
            try resolver.store(key, for: provider)
        }
    }

    struct DeleteKey: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete-key")
        @ParentCommand var parent: ConfigCommand
        @OptionGroup var global: GlobalOptions
        @Argument var provider: String

        mutating func run() throws {
            let provider = try parseProvider(provider)
            let resolver = CredentialResolver()
            if provider == .aws {
                try resolver.deleteAWSStatic()
            } else {
                try resolver.delete(for: provider)
            }
        }
    }
}

private struct ConfigurationView: Encodable {
    let configuration: TranslateKitConfiguration
    let providers: [ProviderState]
}

private func parseProvider(_ value: String) throws -> ProviderID {
    guard let provider = ProviderID(rawValue: value) else {
        throw CLIInputError.invalidProvider(value)
    }
    return provider
}
