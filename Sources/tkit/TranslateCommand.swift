import ArgumentParser
import Darwin
import Foundation
import TranslateKitCore

struct TranslateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "translate",
        abstract: "Translate text using the selected provider."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Text to translate. Reads stdin when omitted.")
    var text: [String] = []

    @Option(name: .long, help: "Source BCP-47 language code.")
    var from: String?

    @Option(name: .long, help: "Target BCP-47 language code.")
    var to: String?

    @Option(name: .long, help: "Provider ID.")
    var provider: String?

    @Flag(name: .long, help: "Emit a JSON object.")
    var json = false

    mutating func run() async throws {
        do {
            let sourceText = try inputText()
            let configuration = try global.store.load()
            let source = try from.map(parseLanguage)
            let target = try to.map(parseLanguage)
            let selectedProvider = try provider.map(parseProvider)
                ?? ProviderID(rawValue: configuration.translation.provider)!
            let result = try await CLIEnvironment.translationService().translate(
                TranslationRequest(
                    text: sourceText,
                    source: source,
                    target: target,
                    provider: selectedProvider
                ),
                configuration: configuration
            )
            if json {
                CLIOutput.stdout(try CLITranslationRenderer.json(result, provider: selectedProvider))
            } else {
                CLIOutput.stdout(CLITranslationRenderer.plain(result))
            }
        } catch {
            throw CLIReportedError(error, json: json)
        }
    }

    private func inputText() throws -> String {
        if !text.isEmpty { return text.joined(separator: " ") }
        guard isatty(STDIN_FILENO) == 0 else { throw CLIInputError.missingText }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines), !value.isEmpty else {
            throw CLIInputError.missingText
        }
        return value
    }

    private func parseLanguage(_ value: String) throws -> Language {
        guard let language = Language(rawValue: value) else {
            throw CLIInputError.invalidLanguage(value)
        }
        return language
    }

    private func parseProvider(_ value: String) throws -> ProviderID {
        guard let provider = ProviderID(rawValue: value) else {
            throw CLIInputError.invalidProvider(value)
        }
        return provider
    }
}
