import Foundation

extension String {
    var describesUnsupportedLanguage: Bool {
        let normalized = lowercased()
        let referencesLanguage = normalized.contains("language")
            || normalized.contains("source_lang")
            || normalized.contains("target_lang")
        let rejectsValue = normalized.contains("not supported")
            || normalized.contains("unsupported")
            || normalized.contains("invalid")
        return referencesLanguage && rejectsValue
    }

    func describesLibreTranslateUnsupportedLanguage(
        sourceCode: String,
        targetCode: String
    ) -> Bool {
        let normalized = lowercased()
        let rejectsLanguage = normalized.contains(" is not supported")
            || normalized.contains("not available as a target language")
            || normalized.contains("not available as a source language")
        guard rejectsLanguage else { return false }

        let tokens = normalized.split { character in
            !character.isLetter && !character.isNumber && character != "-"
        }
        let languageCodes = [sourceCode, targetCode]
            .map { $0.lowercased() }
            .filter { $0 != "auto" }
        return languageCodes.contains { code in
            tokens.contains { $0 == Substring(code) }
        }
    }
}
