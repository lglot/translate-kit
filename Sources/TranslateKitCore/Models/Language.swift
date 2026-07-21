import Foundation

public struct Language: RawRepresentable, Hashable, Identifiable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value == "auto" {
            self.rawValue = value
            return
        }

        let canonical = Locale.canonicalLanguageIdentifier(from: value)
        let subtags = canonical.split(separator: "-", omittingEmptySubsequences: false)
        guard let language = subtags.first,
              (2...8).contains(language.count),
              language.allSatisfy({ $0.isASCII && $0.isLetter }),
              subtags.dropFirst().allSatisfy({
                  (1...8).contains($0.count) && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
              }) else {
            return nil
        }

        self.rawValue = canonical
    }

    public init?(localeLanguage: Locale.Language) {
        var identifier = localeLanguage.minimalIdentifier
        if let region = localeLanguage.region?.identifier,
           !identifier.split(separator: "-").contains(Substring(region)) {
            identifier += "-\(region)"
        }
        self.init(rawValue: identifier)
    }

    public var id: String { rawValue }
    public var isValidTarget: Bool { self != .auto }
    var baseLanguageCode: String {
        String(rawValue.split(separator: "-", maxSplits: 1)[0]).lowercased()
    }

    public var displayName: String {
        if self == .auto { return "Auto-detect" }
        if rawValue.contains("-"), let localized = Locale.current.localizedString(forIdentifier: rawValue) {
            return localized
        }
        return Locale.current.localizedString(forLanguageCode: rawValue) ?? rawValue
    }

    public var flag: String {
        Self.flags[rawValue] ?? "🌐"
    }

    public var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }

    public static let auto = Language(rawValue: "auto")!
    public static let italian = Language(rawValue: "it")!
    public static let english = Language(rawValue: "en")!
    public static let french = Language(rawValue: "fr")!
    public static let german = Language(rawValue: "de")!
    public static let spanish = Language(rawValue: "es")!
    public static let portuguese = Language(rawValue: "pt")!
    public static let russian = Language(rawValue: "ru")!
    public static let chinese = Language(rawValue: "zh")!
    public static let japanese = Language(rawValue: "ja")!
    public static let korean = Language(rawValue: "ko")!
    public static let arabic = Language(rawValue: "ar")!
    public static let dutch = Language(rawValue: "nl")!
    public static let polish = Language(rawValue: "pl")!
    public static let turkish = Language(rawValue: "tr")!
    public static let ukrainian = Language(rawValue: "uk")!
    public static let czech = Language(rawValue: "cs")!
    public static let danish = Language(rawValue: "da")!
    public static let finnish = Language(rawValue: "fi")!
    public static let greek = Language(rawValue: "el")!
    public static let hindi = Language(rawValue: "hi")!
    public static let hungarian = Language(rawValue: "hu")!
    public static let indonesian = Language(rawValue: "id")!
    public static let norwegian = Language(rawValue: "no")!
    public static let romanian = Language(rawValue: "ro")!
    public static let swedish = Language(rawValue: "sv")!
    public static let thai = Language(rawValue: "th")!
    public static let vietnamese = Language(rawValue: "vi")!

    public static var targetLanguages: [Language] {
        Locale.LanguageCode.isoLanguageCodes
            .compactMap { Language(rawValue: $0.identifier) }
            .filter(\.isValidTarget)
            .filter { !["mis", "mul", "und", "zxx"].contains($0.rawValue) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static let flags: [String: String] = [
        "ar": "🇸🇦", "cs": "🇨🇿", "da": "🇩🇰", "de": "🇩🇪", "el": "🇬🇷",
        "en": "🇬🇧", "es": "🇪🇸", "fi": "🇫🇮", "fr": "🇫🇷", "hi": "🇮🇳",
        "hu": "🇭🇺", "id": "🇮🇩", "it": "🇮🇹", "ja": "🇯🇵", "ko": "🇰🇷",
        "nl": "🇳🇱", "no": "🇳🇴", "pl": "🇵🇱", "pt": "🇵🇹", "ro": "🇷🇴",
        "ru": "🇷🇺", "sv": "🇸🇪", "th": "🇹🇭", "tr": "🇹🇷", "uk": "🇺🇦",
        "vi": "🇻🇳", "zh": "🇨🇳"
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let language = Language(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid BCP-47 language code: \(value)"
            )
        }
        self = language
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
