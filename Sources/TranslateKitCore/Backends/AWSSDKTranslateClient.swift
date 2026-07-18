import AWSSDKIdentity
import AWSTranslate
import Foundation

public final class AWSSDKTranslateClient: AmazonTranslateClient, @unchecked Sendable {
    private let client: TranslateClient

    private init(client: TranslateClient) {
        self.client = client
    }

    public static func make(
        configuration: AWSConfiguration,
        credential: ProviderCredential
    ) async throws -> AWSSDKTranslateClient {
        let selectedProfile = configuration.profile.nilIfEmpty
        let profileRegion = try selectedProfile.flatMap {
            try AWSProfileRegionReader().region(for: $0)
        }
        let region = configuration.region.nilIfEmpty ?? profileRegion
        let clientConfig: TranslateClient.TranslateClientConfig

        switch credential {
        case .awsStatic(let accessKeyID, let secretAccessKey, let sessionToken):
            let identity = AWSCredentialIdentity(
                accessKey: accessKeyID,
                secret: secretAccessKey,
                sessionToken: sessionToken
            )
            clientConfig = try await TranslateClient.TranslateClientConfig(
                awsCredentialIdentityResolver: StaticAWSCredentialIdentityResolver(identity),
                region: region
            )
        case .awsProfile(let profile):
            if let profile = profile?.nilIfEmpty ?? selectedProfile {
                clientConfig = try await TranslateClient.TranslateClientConfig(
                    awsCredentialIdentityResolver: ProfileAWSCredentialIdentityResolver(profileName: profile),
                    region: region
                )
            } else {
                clientConfig = try await TranslateClient.TranslateClientConfig(region: region)
            }
        default:
            clientConfig = try await TranslateClient.TranslateClientConfig(region: region)
        }

        return AWSSDKTranslateClient(client: TranslateClient(config: clientConfig))
    }

    public func translate(_ request: AmazonTranslateRequest) async throws -> AmazonTranslateResponse {
        do {
            let output = try await client.translateText(input: TranslateTextInput(
                sourceLanguageCode: request.sourceLanguageCode,
                targetLanguageCode: request.targetLanguageCode,
                text: request.text
            ))
            guard let translatedText = output.translatedText else {
                throw AmazonTranslateClientError.invalidResponse
            }
            return AmazonTranslateResponse(
                translatedText: translatedText,
                sourceLanguageCode: output.sourceLanguageCode,
                targetLanguageCode: output.targetLanguageCode
            )
        } catch is TooManyRequestsException {
            throw AmazonTranslateClientError.rateLimited
        } catch is LimitExceededException {
            throw AmazonTranslateClientError.quota
        } catch is UnsupportedLanguagePairException {
            throw AmazonTranslateClientError.unsupportedLanguage
        } catch is DetectedLanguageLowConfidenceException {
            throw AmazonTranslateClientError.unsupportedLanguage
        } catch is AWSCredentialIdentityResolverError {
            throw AmazonTranslateClientError.authentication
        } catch let error as AmazonTranslateClientError {
            throw error
        } catch {
            let typeName = String(reflecting: type(of: error)).lowercased()
            if typeName.contains("credential")
                || typeName.contains("accessdenied")
                || typeName.contains("expiredtoken")
                || typeName.contains("unrecognizedclient") {
                throw AmazonTranslateClientError.authentication
            }
            if typeName.contains("network") || typeName.contains("connection") || typeName.contains("timeout") {
                throw AmazonTranslateClientError.network
            }
            throw AmazonTranslateClientError.service
        }
    }
}

struct AWSProfileRegionReader: Sendable {
    private let configFileURL: URL

    init(configFileURL: URL) {
        self.configFileURL = configFileURL
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        if let override = environment["AWS_CONFIG_FILE"], !override.isEmpty {
            configFileURL = URL(fileURLWithPath: override)
        } else {
            configFileURL = homeDirectory
                .appendingPathComponent(".aws", isDirectory: true)
                .appendingPathComponent("config")
        }
    }

    func region(for profileName: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else { return nil }
        let source = try String(contentsOf: configFileURL, encoding: .utf8)
        let expectedSection = profileName == "default" ? "default" : "profile \(profileName)"
        var section: String?

        for rawLine in source.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard section == expectedSection, let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "region" else { continue }
            return line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
