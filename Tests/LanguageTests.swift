import XCTest
@testable import TranslateKitCore

final class LanguageTests: XCTestCase {
    func testAcceptsRegionalBCP47Code() {
        XCTAssertNotNil(Language(rawValue: "pt-BR"))
    }

    func testFoundationCatalogContainsMoreThanLegacySet() {
        XCTAssertGreaterThan(Language.targetLanguages.count, 100)
    }
}
