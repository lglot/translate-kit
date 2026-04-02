import Foundation

enum Language: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case italian = "it"
    case english = "en"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case ukrainian = "uk"
    case czech = "cs"
    case danish = "da"
    case finnish = "fi"
    case greek = "el"
    case hindi = "hi"
    case hungarian = "hu"
    case indonesian = "id"
    case norwegian = "no"
    case romanian = "ro"
    case swedish = "sv"
    case thai = "th"
    case vietnamese = "vi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .italian: return "Italian"
        case .english: return "English"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .turkish: return "Turkish"
        case .ukrainian: return "Ukrainian"
        case .czech: return "Czech"
        case .danish: return "Danish"
        case .finnish: return "Finnish"
        case .greek: return "Greek"
        case .hindi: return "Hindi"
        case .hungarian: return "Hungarian"
        case .indonesian: return "Indonesian"
        case .norwegian: return "Norwegian"
        case .romanian: return "Romanian"
        case .swedish: return "Swedish"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        }
    }

    var flag: String {
        switch self {
        case .auto: return "🌐"
        case .italian: return "🇮🇹"
        case .english: return "🇬🇧"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .spanish: return "🇪🇸"
        case .portuguese: return "🇵🇹"
        case .russian: return "🇷🇺"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .arabic: return "🇸🇦"
        case .dutch: return "🇳🇱"
        case .polish: return "🇵🇱"
        case .turkish: return "🇹🇷"
        case .ukrainian: return "🇺🇦"
        case .czech: return "🇨🇿"
        case .danish: return "🇩🇰"
        case .finnish: return "🇫🇮"
        case .greek: return "🇬🇷"
        case .hindi: return "🇮🇳"
        case .hungarian: return "🇭🇺"
        case .indonesian: return "🇮🇩"
        case .norwegian: return "🇳🇴"
        case .romanian: return "🇷🇴"
        case .swedish: return "🇸🇪"
        case .thai: return "🇹🇭"
        case .vietnamese: return "🇻🇳"
        }
    }

    /// Languages available for target selection (excludes auto-detect)
    static var targetLanguages: [Language] {
        allCases.filter { $0 != .auto }
    }
}
