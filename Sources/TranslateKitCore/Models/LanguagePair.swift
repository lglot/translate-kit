import Foundation
import NaturalLanguage

/// A configured pair of languages. Detection picks which member the text is in,
/// and translation always targets the other member.
public struct LanguagePair: Equatable, Sendable {
    public let first: Language
    public let second: Language

    public init(first: Language, second: Language) {
        self.first = first
        self.second = second
    }

    /// Detects which pair member `text` is written in.
    /// Falls back to `first` when detection is inconclusive.
    public func detectSource(of text: String) -> Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [
            NLLanguage(rawValue: first.rawValue),
            NLLanguage(rawValue: second.rawValue)
        ]
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage,
              let detected = Language(rawValue: dominant.rawValue) else {
            return first
        }
        return detected == second ? second : first
    }

    /// The other member of the pair.
    public func target(for source: Language) -> Language {
        source == second ? first : second
    }

    /// Convenience: detect source and return the (source, target) direction for `text`.
    public func direction(for text: String) -> (source: Language, target: Language) {
        let source = detectSource(of: text)
        return (source, target(for: source))
    }
}
