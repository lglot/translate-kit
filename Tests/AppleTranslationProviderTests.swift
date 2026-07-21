import XCTest
@testable import TranslateKitApple
@testable import TranslateKitCore

@MainActor
final class AppleTranslationProviderTests: XCTestCase {
    func testRequestTimeoutCoversWaitingForHostedSession() async {
        let provider = AppleTranslationProvider(
            requestTimeout: .milliseconds(20),
            hostsWindow: false
        )

        do {
            _ = try await provider.translate("Hello", from: nil, to: .italian)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .apiError("Apple Translation timed out")
            )
        }
    }

    func testCallerCancellationRemovesQueuedRequest() async {
        let provider = AppleTranslationProvider(
            requestTimeout: .seconds(1),
            hostsWindow: false
        )
        let request = Task { @MainActor in
            try await provider.translate("Hello", from: nil, to: .italian)
        }
        _ = await waitForHostedSession(provider)

        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testStaleSessionCannotConsumeRequestFromNewGeneration() async throws {
        let provider = AppleTranslationProvider(
            requestTimeout: .milliseconds(100),
            hostsWindow: false
        )
        let firstRequest = Task { @MainActor in
            try await provider.translate("first", from: nil, to: .italian)
        }
        let firstHosted = await waitForHostedSession(provider)
        let firstDrain = Task { @MainActor in
            await provider.runHostedSession(firstHosted) { _ in
                try await Task.sleep(for: .seconds(5))
                return AppleTranslationOutput(text: "stale", sourceLanguage: .english)
            }
        }

        do {
            _ = try await firstRequest.value
            XCTFail("Expected first request to time out")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .apiError("Apple Translation timed out")
            )
        }
        await firstDrain.value

        let secondRequest = Task { @MainActor in
            try await provider.translate("second", from: nil, to: .italian)
        }
        let secondHosted = await waitForHostedSession(
            provider,
            excluding: firstHosted.generation
        )

        await provider.runHostedSession(firstHosted) { _ in
            XCTFail("Stale session translator must not run")
            return AppleTranslationOutput(text: "stale", sourceLanguage: .english)
        }
        await provider.runHostedSession(secondHosted) { _ in
            AppleTranslationOutput(text: "fresh", sourceLanguage: .english)
        }

        let output = try await secondRequest.value
        XCTAssertEqual(output.text, "fresh")
        XCTAssertEqual(output.sourceLanguage, .english)
    }

    func testCancellingInFlightRequestRestartsSamePairForQueuedRequest() async throws {
        let provider = AppleTranslationProvider(
            requestTimeout: .seconds(1),
            hostsWindow: false
        )
        let firstRequest = Task { @MainActor in
            try await provider.translate("first", from: nil, to: .italian)
        }
        let secondRequest = Task { @MainActor in
            try await provider.translate("second", from: nil, to: .italian)
        }
        let firstHosted = await waitForHostedSession(provider)
        let firstDrain = Task { @MainActor in
            await provider.runHostedSession(firstHosted) { text in
                XCTAssertEqual(text, "first")
                try await Task.sleep(for: .seconds(5))
                return AppleTranslationOutput(text: "stale", sourceLanguage: .english)
            }
        }
        try await Task.sleep(for: .milliseconds(10))

        firstRequest.cancel()
        do {
            _ = try await firstRequest.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        await firstDrain.value

        let secondHosted = await waitForHostedSession(
            provider,
            excluding: firstHosted.generation
        )
        XCTAssertNotEqual(secondHosted.generation, firstHosted.generation)
        await provider.runHostedSession(secondHosted) { text in
            XCTAssertEqual(text, "second")
            return AppleTranslationOutput(text: "fresh", sourceLanguage: .english)
        }

        let output = try await secondRequest.value
        XCTAssertEqual(output.text, "fresh")
    }

    private func waitForHostedSession(
        _ provider: AppleTranslationProvider,
        excluding generation: UUID? = nil
    ) async -> HostedAppleTranslationSession {
        for _ in 0..<100 {
            if let hosted = provider.hostedSession,
               hosted.generation != generation {
                return hosted
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Hosted session was not created")
        fatalError("Hosted session was not created")
    }
}
