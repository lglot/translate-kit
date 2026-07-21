import Foundation
import XCTest
@testable import TranslateKitCore

final class RESTBackendTests: XCTestCase {
    func testDeepLUsesAuthorizationHeaderAndNeverPlacesKeyInBody() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"{"translations":[{"detected_source_language":"IT","text":"Hello"}]}"#.utf8),
            url: URL(string: "https://api-free.deepl.com/v2/translate")!
        ))
        let backend = DeepLBackend(
            credential: .apiKey("deepl-secret"),
            configuration: DeepLConfiguration(plan: "free"),
            httpClient: client
        )

        let result = try await backend.translate("Ciao", from: .auto, to: .english)
        let capturedRequest = await client.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!

        XCTAssertEqual(result.translatedText, "Hello")
        XCTAssertEqual(result.sourceLanguage, .italian)
        XCTAssertEqual(request.url?.host, "api-free.deepl.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key deepl-secret")
        XCTAssertFalse(body.contains("deepl-secret"))
        XCTAssertFalse(body.contains("source_lang"))
    }

    func testGoogleSupportsAPIKeyAndAutoDetection() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"{"data":{"translations":[{"translatedText":"Ciao","detectedSourceLanguage":"en"}]}}"#.utf8),
            url: URL(string: "https://translation.googleapis.com/language/translate/v2")!
        ))
        let backend = GoogleCloudBackend(credential: .apiKey("google-secret"), httpClient: client)

        let result = try await backend.translate("Hello", from: .auto, to: .italian)
        let capturedRequest = await client.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(result.sourceLanguage, .english)
        XCTAssertEqual(result.translatedText, "Ciao")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), "google-secret")
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "key" }))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testGoogleSupportsShortLivedBearerToken() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"{"data":{"translations":[{"translatedText":"Bonjour"}]}}"#.utf8),
            url: URL(string: "https://translation.googleapis.com/language/translate/v2")!
        ))
        let backend = GoogleCloudBackend(
            credential: .bearerToken("short-token", quotaProject: "billing-project"),
            httpClient: client
        )

        _ = try await backend.translate("Hello", from: .english, to: .french)
        let capturedRequest = await client.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer short-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-User-Project"), "billing-project")
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "key" }))
    }

    func testAzureUsesConfiguredRegionAndParsesDetection() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"[{"detectedLanguage":{"language":"it","score":1.0},"translations":[{"text":"Hello","to":"en"}]}]"#.utf8),
            url: URL(string: "https://api.cognitive.microsofttranslator.com/translate")!
        ))
        let configuration = AzureConfiguration(
            auth: "api-key",
            endpoint: "https://api.cognitive.microsofttranslator.com",
            region: "westeurope"
        )
        let backend = AzureBackend(
            credential: .apiKey("azure-secret"),
            configuration: configuration,
            httpClient: client
        )

        let result = try await backend.translate("Ciao", from: .auto, to: .english)
        let capturedRequest = await client.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)

        XCTAssertEqual(result.sourceLanguage, .italian)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key"), "azure-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region"), "westeurope")
        XCTAssertEqual(request.url?.path, "/translate")
    }

    func testAzureCustomDomainUsesTranslatorV3Path() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"[{"translations":[{"text":"Hello","to":"en"}]}]"#.utf8),
            url: URL(string: "https://my-translator.cognitiveservices.azure.com/translator/text/v3.0/translate")!
        ))
        let backend = AzureBackend(
            credential: .apiKey("azure-secret"),
            configuration: AzureConfiguration(
                auth: "api-key",
                endpoint: "https://my-translator.cognitiveservices.azure.com",
                region: "switzerlandnorth"
            ),
            httpClient: client
        )

        _ = try await backend.translate("Ciao", from: .italian, to: .english)
        let capturedRequest = await client.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)

        XCTAssertEqual(request.url?.path, "/translator/text/v3.0/translate")
    }

    func testLibreTranslateSendsOptionalKeyToConfiguredEndpoint() async throws {
        let endpoint = "https://translate.example.com"
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"{"translatedText":"Hello","detectedLanguage":{"confidence":92,"language":"it"}}"#.utf8),
            url: URL(string: "https://translate.example.com/translate")!
        ))
        let backend = LibreTranslateBackend(
            credential: .apiKey("libre-secret"),
            configuration: LibreTranslateConfiguration(endpoint: endpoint),
            httpClient: client
        )

        let result = try await backend.translate("Ciao", from: .auto, to: .english)
        let capturedRequest = await client.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(result.sourceLanguage, .italian)
        XCTAssertEqual(request.url?.absoluteString, "https://translate.example.com/translate")
        XCTAssertEqual(object["api_key"] as? String, "libre-secret")
    }

    func testLibreTranslateRejectsCrossHostRedirectResponseWhenKeyIsPresent() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"{"translatedText":"Hello"}"#.utf8),
            url: URL(string: "https://attacker.example/translate")!
        ))
        let backend = LibreTranslateBackend(
            credential: .apiKey("libre-secret"),
            configuration: LibreTranslateConfiguration(endpoint: "https://translate.example.com"),
            httpClient: client
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await backend.translate("Ciao", from: .italian, to: .english)
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .unsafeRedirect)
        }
    }

    func testProviderErrorsAreClassifiedWithoutResponseBodyLeakage() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 403,
            data: Data(#"{"error":"contains-sensitive-provider-details"}"#.utf8),
            url: URL(string: "https://api-free.deepl.com/v2/translate")!
        ))
        let backend = DeepLBackend(
            credential: .apiKey("secret"),
            configuration: .init(),
            httpClient: client
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await backend.translate("Ciao", from: .italian, to: .english)
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .authenticationFailed("DeepL"))
            XCTAssertFalse(error.localizedDescription.contains("contains-sensitive-provider-details"))
        }
    }

    func testMalformedSuccessResponseIsRejected() async throws {
        let client = CapturingHTTPClient(response: HTTPResponse(
            statusCode: 200,
            data: Data(#"{"unexpected":true}"#.utf8),
            url: URL(string: "https://translation.googleapis.com/language/translate/v2")!
        ))
        let backend = GoogleCloudBackend(credential: .apiKey("secret"), httpClient: client)

        await XCTAssertThrowsErrorAsync {
            _ = try await backend.translate("Hello", from: .english, to: .italian)
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .invalidResponse)
        }
    }

    func testRESTProvidersClassifyUnsupportedLanguageWithoutLeakingResponseBody() async {
        let cases: [(any TranslationBackend, String)] = [
            (
                DeepLBackend(
                    credential: .apiKey("secret"),
                    configuration: .init(),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: Data(#"{"message":"Value for 'target_lang' not supported."}"#.utf8),
                        url: URL(string: "https://api-free.deepl.com/v2/translate")!
                    ))
                ),
                "DeepL"
            ),
            (
                GoogleCloudBackend(
                    credential: .apiKey("secret"),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: Data(#"{"error":{"code":400,"message":"Invalid target language code."}}"#.utf8),
                        url: URL(string: "https://translation.googleapis.com/language/translate/v2")!
                    ))
                ),
                "Google Cloud"
            ),
            (
                AzureBackend(
                    credential: .apiKey("secret"),
                    configuration: .init(),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: Data(#"{"error":{"code":400019,"message":"Unsupported language."}}"#.utf8),
                        url: URL(string: "https://api.cognitive.microsofttranslator.com/translate")!
                    ))
                ),
                "Azure Translator"
            ),
            (
                LibreTranslateBackend(
                    credential: .none,
                    configuration: .init(),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: Data(#"{"error":"it is not supported"}"#.utf8),
                        url: URL(string: "http://localhost:5000/translate")!
                    ))
                ),
                "LibreTranslate"
            )
        ]

        for (backend, name) in cases {
            await XCTAssertThrowsErrorAsync {
                _ = try await backend.translate("Ciao", from: .italian, to: .english)
            } verify: { error in
                XCTAssertEqual(
                    error as? TranslationError,
                    .unsupportedLanguage("it to en"),
                    name
                )
            }
        }
    }

    func testRESTProvidersDoNotClassifyArbitraryBadRequestAsUnsupportedLanguage() async {
        let responseBody = Data(#"{"error":"provider detail must stay private"}"#.utf8)
        let cases: [(any TranslationBackend, String)] = [
            (
                DeepLBackend(
                    credential: .apiKey("secret"),
                    configuration: .init(),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: responseBody,
                        url: URL(string: "https://api-free.deepl.com/v2/translate")!
                    ))
                ),
                "DeepL"
            ),
            (
                GoogleCloudBackend(
                    credential: .apiKey("secret"),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: responseBody,
                        url: URL(string: "https://translation.googleapis.com/language/translate/v2")!
                    ))
                ),
                "Google Cloud"
            ),
            (
                AzureBackend(
                    credential: .apiKey("secret"),
                    configuration: .init(),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: responseBody,
                        url: URL(string: "https://api.cognitive.microsofttranslator.com/translate")!
                    ))
                ),
                "Azure Translator"
            ),
            (
                LibreTranslateBackend(
                    credential: .none,
                    configuration: .init(),
                    httpClient: CapturingHTTPClient(response: HTTPResponse(
                        statusCode: 400,
                        data: responseBody,
                        url: URL(string: "http://localhost:5000/translate")!
                    ))
                ),
                "LibreTranslate"
            )
        ]

        for (backend, name) in cases {
            await XCTAssertThrowsErrorAsync {
                _ = try await backend.translate("Ciao", from: .italian, to: .english)
            } verify: { error in
                guard let translationError = error as? TranslationError,
                      case .apiError = translationError else {
                    return XCTFail("Expected sanitized API error for \(name), got \(error)")
                }
                XCTAssertFalse(error.localizedDescription.contains("provider detail"), name)
            }
        }
    }

    func testLibreTranslateDoesNotClassifyUnsupportedFormatAsUnsupportedLanguage() async {
        let backend = LibreTranslateBackend(
            credential: .none,
            configuration: .init(),
            httpClient: CapturingHTTPClient(response: HTTPResponse(
                statusCode: 400,
                data: Data(#"{"error":"html format is not supported"}"#.utf8),
                url: URL(string: "http://localhost:5000/translate")!
            ))
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await backend.translate("Ciao", from: .italian, to: .english)
        } verify: { error in
            XCTAssertEqual(
                error as? TranslationError,
                .apiError("LibreTranslate rejected the request (HTTP 400)")
            )
        }
    }
}

private actor CapturingHTTPClient: HTTPClient {
    let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }

    func capturedRequest() -> URLRequest? {
        lastRequest
    }
}

private func XCTAssertThrowsErrorAsync<T>(
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
