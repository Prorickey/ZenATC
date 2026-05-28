//
//  AttestationManager.swift
//  ZenATC
//

import CryptoKit
import DeviceCheck
import Foundation
import Observation

enum AttestationError: LocalizedError {
    case unsupported
    case challengeFetchFailed(Error)
    case invalidChallengeToken
    case keyGenerationFailed(Error)
    case attestationFailed(Error)
    case verificationRejected
    case keyNotFound
    case networkError(Error)
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "App Attest is not supported on this device."
        case .challengeFetchFailed(let e):
            return "Failed to fetch challenge: \(e.localizedDescription)"
        case .invalidChallengeToken:
            return "Backend returned an unreadable challenge token."
        case .keyGenerationFailed(let e):
            return "Could not generate attestation key: \(e.localizedDescription)"
        case .attestationFailed(let e):
            return "Apple attestation failed: \(e.localizedDescription)"
        case .verificationRejected:
            return "Backend rejected the attestation."
        case .keyNotFound:
            return "Attestation key not found on server — re-registering."
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .invalidStreamURL:
            return "Backend returned an invalid stream URL."
        }
    }
}

private struct AttestationPayload {
    let keyID: String
    let challengeToken: String
    let attestationObject: Data
}

@Observable
final class AttestationManager {
    let backendBaseURL: URL

    private static let keyIDDefaultsKey        = "tech.bedson.zenatc.attestation.keyID"
    private static let keyRegisteredDefaultsKey = "tech.bedson.zenatc.attestation.keyRegistered"

    init(backendBaseURL: URL) {
        self.backendBaseURL = backendBaseURL
    }

    // MARK: - Public API

    // Returns a short-lived signed CDN URL for the given stream ID.
    //
    // First call ever: runs full Apple attestation (contacts Apple servers once to
    // register the key), then uses the cheaper assertion path to get the URL.
    // Subsequent calls skip attestation entirely and only use assertions.
    //
    // If the server loses the key (e.g. restart), the assertion endpoint returns 404
    // and this method automatically re-registers before retrying.
    func requestStreamURL(for streamID: String) async throws -> URL {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AttestationError.unsupported }

        var keyID = try await resolvedKeyID(service: service)

        if !UserDefaults.standard.bool(forKey: Self.keyRegisteredDefaultsKey) {
            try await attestAndRegister(keyID: keyID, service: service)
            keyID = try await resolvedKeyID(service: service)
        }

        do {
            return try await assertStreamURL(for: streamID, keyID: keyID)
        } catch AttestationError.keyNotFound {
            clearRegistered()
            try await attestAndRegister(keyID: keyID, service: service)
            keyID = try await resolvedKeyID(service: service)
            return try await assertStreamURL(for: streamID, keyID: keyID)
        }
    }
    
    // MARK: - Challenge fetch

    private func fetchChallengeToken() async throws -> String {
        let url = backendBaseURL.appendingPathComponent("challenge")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(ChallengeTokenResponse.self, from: data).token
        } catch {
            throw AttestationError.challengeFetchFailed(error)
        }
    }

    // MARK: - Attestation

    // Runs the full Apple attestation flow and registers the public key with the backend.
    // After this succeeds, generateAssertion can be used for all future requests.
    private func attestAndRegister(keyID: String, service: DCAppAttestService) async throws {
        let payload = try await buildPayload(keyID: keyID, service: service)

        let endpoint = backendBaseURL.appendingPathComponent("attest-key")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AttestKeyRequest(
            challengeToken: payload.challengeToken,
            keyID: payload.keyID,
            attestationObject: payload.attestationObject.base64EncodedString()
        ))

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AttestationError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AttestationError.verificationRejected
        }

        markRegistered()
    }

    // Builds a payload of the key ID, challenge token, and attestation object by hashing the challenge and attesting
    // with apples servers.
    private func buildPayload(keyID: String, service: DCAppAttestService) async throws -> AttestationPayload {
        let token = try await fetchChallengeToken()
        let challenge = try decodeChallenge(from: token)
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))

        var activeKeyID = keyID
        let attestation: Data
        do {
            attestation = try await service.attestKey(activeKeyID, clientDataHash: clientDataHash)
        } catch {
            clearStoredKeyID()
            clearRegistered()
            activeKeyID = try await generateAndStoreKey(service: service)
            do {
                attestation = try await service.attestKey(activeKeyID, clientDataHash: clientDataHash)
            } catch let retryError {
                throw AttestationError.attestationFailed(retryError)
            }
        }

        return AttestationPayload(keyID: activeKeyID, challengeToken: token, attestationObject: attestation)
    }

    // MARK: - Assertion

    // Generates a lightweight App Attest assertion (no Apple server contact)
    // and exchanges it for a signed CDN URL.
    private func assertStreamURL(for streamID: String, keyID: String) async throws -> URL {
        let token = try await fetchChallengeToken()
        let challenge = try decodeChallenge(from: token)
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))

        let service = DCAppAttestService.shared
        let assertionData: Data
        do {
            assertionData = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw AttestationError.attestationFailed(error)
        }

        let endpoint = backendBaseURL.appendingPathComponent("assert-and-stream")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AssertRequest(
            challengeToken: token,
            keyID: keyID,
            assertionObject: assertionData.base64EncodedString(),
            streamID: streamID
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AttestationError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AttestationError.verificationRejected
        }

        if http.statusCode == 404 {
            throw AttestationError.keyNotFound
        }

        guard http.statusCode == 200 else {
            throw AttestationError.verificationRejected
        }

        let result = try JSONDecoder().decode(StreamURLResponse.self, from: data)
        guard let url = URL(string: result.streamURL) else {
            throw AttestationError.invalidStreamURL
        }
        return url
    }

    private func decodeChallenge(from jwt: String) throws -> String {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { throw AttestationError.invalidChallengeToken }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let payloadData = Data(base64Encoded: base64),
            let payload = try? JSONDecoder().decode(JWTChallengePayload.self, from: payloadData),
            !payload.challenge.isEmpty
        else {
            throw AttestationError.invalidChallengeToken
        }
        return payload.challenge
    }

    // MARK: - Key lifecycle

    private func resolvedKeyID(service: DCAppAttestService) async throws -> String {
        if let stored = UserDefaults.standard.string(forKey: Self.keyIDDefaultsKey) {
            return stored
        }
        return try await generateAndStoreKey(service: service)
    }

    private func generateAndStoreKey(service: DCAppAttestService) async throws -> String {
        do {
            let keyID = try await service.generateKey()
            UserDefaults.standard.set(keyID, forKey: Self.keyIDDefaultsKey)
            return keyID
        } catch {
            throw AttestationError.keyGenerationFailed(error)
        }
    }

    private func clearStoredKeyID() {
        UserDefaults.standard.removeObject(forKey: Self.keyIDDefaultsKey)
    }

    private func markRegistered() {
        UserDefaults.standard.set(true, forKey: Self.keyRegisteredDefaultsKey)
    }

    private func clearRegistered() {
        UserDefaults.standard.removeObject(forKey: Self.keyRegisteredDefaultsKey)
    }
}

// MARK: - Private network models

private struct ChallengeTokenResponse: Decodable {
    let token: String
}

private struct JWTChallengePayload: Decodable {
    let challenge: String
}

private struct AttestKeyRequest: Encodable {
    let challengeToken: String
    let keyID: String
    let attestationObject: String

    enum CodingKeys: String, CodingKey {
        case challengeToken    = "challenge_token"
        case keyID             = "key_id"
        case attestationObject = "attestation_object"
    }
}

private struct AssertRequest: Encodable {
    let challengeToken: String
    let keyID: String
    let assertionObject: String
    let streamID: String

    enum CodingKeys: String, CodingKey {
        case challengeToken  = "challenge_token"
        case keyID           = "key_id"
        case assertionObject = "assertion_object"
        case streamID        = "stream_id"
    }
}

private struct StreamURLResponse: Decodable {
    let streamURL: String

    enum CodingKeys: String, CodingKey {
        case streamURL = "stream_url"
    }
}
