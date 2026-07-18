import ArgumentParser
import Darwin
import Foundation
import TranslateKitApple
import TranslateKitCore

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Use a configuration file at PATH.")
    var config: String?

    var configurationURL: URL {
        guard let config else { return ConfigurationStore.defaultURL }
        return URL(fileURLWithPath: NSString(string: config).expandingTildeInPath)
    }

    var store: ConfigurationStore {
        ConfigurationStore(url: configurationURL)
    }
}

enum CLIEnvironment {
    static func registry() -> ProviderRegistry {
        ProviderRegistry(appleBackendFactory: { AppleBackend() })
    }

    static func translationService() -> TranslationService {
        TranslationService(backendResolver: registry())
    }
}

enum CLIOutput {
    static func stdout(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    static func stdout(_ data: Data, trailingNewline: Bool = true) {
        FileHandle.standardOutput.write(data)
        if trailingNewline { FileHandle.standardOutput.write(Data("\n".utf8)) }
    }

    static func stderr(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
        if !string.hasSuffix("\n") { FileHandle.standardError.write(Data("\n".utf8)) }
    }
}

enum SecretInput {
    static func readOne(prompt: String) throws -> String {
        if isatty(STDIN_FILENO) == 1 {
            return try readInteractive(prompt: prompt)
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw CLIInputError.missingSecret
        }
        return value
    }

    static func readAWS() throws -> (String, String, String?) {
        if isatty(STDIN_FILENO) == 1 {
            let access = try readInteractive(prompt: "AWS access key ID: ")
            let secret = try readInteractive(prompt: "AWS secret access key: ")
            let session = try readInteractive(prompt: "AWS session token (optional): ", allowsEmpty: true)
            return (access, secret, session.isEmpty ? nil : session)
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let lines = String(decoding: data, as: UTF8.self)
            .split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline)
            .map(String.init)
        guard lines.count >= 2, !lines[0].isEmpty, !lines[1].isEmpty else {
            throw CLIInputError.invalidAWSSecretInput
        }
        let session = lines.count > 2 && !lines[2].isEmpty ? lines[2] : nil
        return (lines[0], lines[1], session)
    }

    private static func readInteractive(prompt: String, allowsEmpty: Bool = false) throws -> String {
        FileHandle.standardError.write(Data(prompt.utf8))
        var settings = termios()
        guard tcgetattr(STDIN_FILENO, &settings) == 0 else {
            throw CLIInputError.terminalUnavailable
        }
        let original = settings
        settings.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &settings) == 0 else {
            throw CLIInputError.terminalUnavailable
        }
        defer {
            var restored = original
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &restored)
            FileHandle.standardError.write(Data("\n".utf8))
        }
        guard let value = readLine(), allowsEmpty || !value.isEmpty else {
            throw CLIInputError.missingSecret
        }
        return value
    }
}

enum CLIInputError: LocalizedError {
    case missingText
    case missingSecret
    case invalidAWSSecretInput
    case terminalUnavailable
    case invalidLanguage(String)
    case invalidProvider(String)
    case unsupportedImport(String)

    var errorDescription: String? {
        switch self {
        case .missingText: "Provide TEXT or pipe text on stdin"
        case .missingSecret: "No secret was provided"
        case .invalidAWSSecretInput: "Provide AWS access key ID, secret access key, and optional session token on separate lines"
        case .terminalUnavailable: "Secure terminal input is unavailable"
        case .invalidLanguage(let value): "Invalid BCP-47 language code: \(value)"
        case .invalidProvider(let value): "Unknown provider: \(value)"
        case .unsupportedImport(let provider): "No importable long-lived API key found for \(provider)"
        }
    }
}
