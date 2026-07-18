import XCTest
@testable import TranslateKitCore

final class AWSBackendTests: XCTestCase {
    func testProfileRegionReaderUsesSelectedProfileWithoutReadingCredentials() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-aws-region-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try """
        [default]
        region = us-east-1
        [profile work]
        region = eu-west-1
        secret-looking-setting = must-not-be-returned
        """.write(to: config, atomically: true, encoding: .utf8)

        let reader = AWSProfileRegionReader(configFileURL: config)

        XCTAssertEqual(try reader.region(for: "work"), "eu-west-1")
        XCTAssertEqual(try reader.region(for: "default"), "us-east-1")
    }

    func testProfileRegionReaderHonorsAWSConfigFileOverride() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("translatekit-aws-override-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("custom-config")
        try "[profile work]\nregion = ap-southeast-2\n"
            .write(to: config, atomically: true, encoding: .utf8)

        let reader = AWSProfileRegionReader(
            environment: ["AWS_CONFIG_FILE": config.path],
            homeDirectory: directory
        )

        XCTAssertEqual(try reader.region(for: "work"), "ap-southeast-2")
    }

    func testTranslateUsesAWSLanguageCodesAndNormalizesResult() async throws {
        let client = StubAmazonTranslateClient(response: AmazonTranslateResponse(
            translatedText: "Hello",
            sourceLanguageCode: "it",
            targetLanguageCode: "en"
        ))
        let backend = AWSBackend(client: client)

        let result = try await backend.translate("Ciao", from: .auto, to: .english)
        let request = await client.capturedRequest()

        XCTAssertEqual(request?.text, "Ciao")
        XCTAssertEqual(request?.sourceLanguageCode, "auto")
        XCTAssertEqual(request?.targetLanguageCode, "en")
        XCTAssertEqual(result.translatedText, "Hello")
        XCTAssertEqual(result.sourceLanguage, .italian)
        XCTAssertEqual(result.backend, "Amazon Translate")
    }

    func testAuthenticationFailureIsSanitized() async {
        let client = StubAmazonTranslateClient(error: .authentication)
        let backend = AWSBackend(client: client)

        await XCTAssertThrowsErrorAsyncAWS {
            _ = try await backend.translate("Ciao", from: .italian, to: .english)
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .authenticationFailed("Amazon Translate"))
        }
    }

    func testUnsupportedPairIsClassified() async {
        let client = StubAmazonTranslateClient(error: .unsupportedLanguage)
        let backend = AWSBackend(client: client)

        await XCTAssertThrowsErrorAsyncAWS {
            _ = try await backend.translate("Ciao", from: .italian, to: .english)
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .unsupportedLanguage("it to en"))
        }
    }
}

private actor StubAmazonTranslateClient: AmazonTranslateClient {
    private let response: AmazonTranslateResponse?
    private let error: AmazonTranslateClientError?
    private var request: AmazonTranslateRequest?

    init(response: AmazonTranslateResponse) {
        self.response = response
        error = nil
    }

    init(error: AmazonTranslateClientError) {
        response = nil
        self.error = error
    }

    func translate(_ request: AmazonTranslateRequest) async throws -> AmazonTranslateResponse {
        self.request = request
        if let error { throw error }
        return response!
    }

    func capturedRequest() -> AmazonTranslateRequest? {
        request
    }
}

private func XCTAssertThrowsErrorAsyncAWS<T>(
    _ expression: () async throws -> T,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}
