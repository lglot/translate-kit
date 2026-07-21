import XCTest
@testable import TranslateKitCore

final class LanguagePairTests: XCTestCase {
    let pair = LanguagePair(first: .italian, second: .english)

    func testDetectsItalian() {
        XCTAssertEqual(pair.detectSource(of: "Ciao, come stai? Oggi andiamo al mare con gli amici."), .italian)
    }

    func testDetectsEnglish() {
        XCTAssertEqual(pair.detectSource(of: "Hello, how are you? Today we are going to the beach."), .english)
    }

    func testTargetFlipsWithinPair() {
        XCTAssertEqual(pair.target(for: .italian), .english)
        XCTAssertEqual(pair.target(for: .english), .italian)
    }

    func testTargetForNonMemberFallsBackToSecond() {
        XCTAssertEqual(pair.target(for: .german), .english)
    }

    func testDirectionForItalianText() {
        let direction = pair.direction(for: "Buongiorno a tutti, questo è un testo di prova per il rilevamento.")
        XCTAssertEqual(direction.source, .italian)
        XCTAssertEqual(direction.target, .english)
    }

    func testDirectionForEnglishText() {
        let direction = pair.direction(for: "Good morning everyone, this is a sample text for detection.")
        XCTAssertEqual(direction.source, .english)
        XCTAssertEqual(direction.target, .italian)
    }

    func testDetectionMapsBaseLanguageToRegionalPairMember() {
        let regionalPair = LanguagePair(
            first: .english,
            second: Language(rawValue: "pt-BR")!
        )

        XCTAssertEqual(
            regionalPair.detectSource(
                of: "Olá, como você está? Hoje vamos passear pela cidade com nossos amigos."
            ),
            Language(rawValue: "pt-BR")!
        )
    }
}
