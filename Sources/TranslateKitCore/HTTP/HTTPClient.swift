import Foundation

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let url: URL
    public let headers: [String: String]

    public init(
        statusCode: Int,
        data: Data,
        url: URL,
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.data = data
        self.url = url
        self.headers = headers
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    public static let shared = URLSessionHTTPClient()

    private let redirectDelegate: SameHostRedirectDelegate
    private let session: URLSession

    public init() {
        let redirectDelegate = SameHostRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        session = URLSession(
            configuration: .ephemeral,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let url = response.url else {
            throw TranslationError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else { return }
            result[key] = value
        }
        return HTTPResponse(
            statusCode: response.statusCode,
            data: data,
            url: url,
            headers: headers
        )
    }

}

private final class SameHostRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard
            let originalURL = task.originalRequest?.url,
            let redirectedURL = request.url,
            originalURL.scheme?.lowercased() == redirectedURL.scheme?.lowercased(),
            originalURL.host?.lowercased() == redirectedURL.host?.lowercased()
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

func perform(_ request: URLRequest, using client: any HTTPClient) async throws -> HTTPResponse {
    do {
        return try await client.send(request)
    } catch let error as TranslationError {
        throw error
    } catch is CancellationError {
        throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
        if Task.isCancelled { throw CancellationError() }
        throw TranslationError.cancelled
    } catch {
        throw TranslationError.noInternet
    }
}
