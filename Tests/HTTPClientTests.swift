import Foundation
import XCTest
@testable import TranslateKitCore

final class HTTPClientTests: XCTestCase {
    func testPerformPreservesTaskCancellation() async {
        await XCTAssertThrowsErrorAsyncHTTP {
            _ = try await TranslateKitCore.perform(
                URLRequest(url: URL(string: "https://example.com")!),
                using: ThrowingHTTPClient(error: CancellationError())
            )
        } verify: { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testPerformClassifiesURLSessionCancellationSeparatelyFromNetworkFailure() async {
        await XCTAssertThrowsErrorAsyncHTTP {
            _ = try await TranslateKitCore.perform(
                URLRequest(url: URL(string: "https://example.com")!),
                using: ThrowingHTTPClient(error: URLError(.cancelled))
            )
        } verify: { error in
            XCTAssertEqual(error as? TranslationError, .cancelled)
        }
    }
}

private struct ThrowingHTTPClient: HTTPClient {
    let error: any Error

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw error
    }
}

private func XCTAssertThrowsErrorAsyncHTTP<T>(
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
