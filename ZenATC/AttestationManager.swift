//
//  AttestationManager.swift
//  ZenATC
//

import CryptoKit
import DeviceCheck
import Foundation
import Observation
import Security

enum AttestationError: LocalizedError {
    case unsupported
    case challengeFetchFailed(Error)
    case invalidChallengeToken
    case keyGenerationFailed(Error)
    case signingKeyCreationFailed(Error)
    case signingKeyUnavailable
    case signingFailed(Error)
    case keychainFailure(OSStatus)
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
        case .signingKeyCreationFailed(let e):
            return "Could not create signing key: \(e.localizedDescription)"
        case .signingKeyUnavailable:
            return "Local signing key is missing — re-registering."
        case .signingFailed(let e):
            return "Failed to sign request: \(e.localizedDescription)"
        case .keychainFailure(let status):
            return "Keychain error (status \(status))."
        case .attestationFailed(let e):
            return "Apple attestation failed: \(e.localizedDescription)"
        case .verificationRejected:
            return "Backend rejected the attestation."
        case .keyNotFound:
            return "Signing key not found on server — re-registering."
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .invalidStreamURL:
            return "Backend returned an invalid stream URL."
        }
    }
}

@Observable
final class AttestationManager {
    let backendBaseURL: URL

    private static let keyIDDefaultsKey         = "tech.bedson.zenatc.attestation.keyID"
    private static let keyRegisteredDefaultsKey = "tech.bedson.zenatc.attestation.keyRegistered"
    private static let signingKeyTag            = "tech.bedson.zenatc.requestSigningKey"

    init(backendBaseURL: URL) {
        self.backendBaseURL = backendBaseURL
    }

    // MARK: - Public API

    // Returns a short-lived signed CDN URL for the given stream ID.
    //
    // First call ever (or after the local/server key is lost): runs the one-time
    // attestation, which contacts Apple once to attest an App Attest key whose
    // attestation binds a second, app-generated Secure Enclave signing key.
    // Every subsequent call asserts the request by signing with that second key —
    // no Apple contact and no `generateAssertion`.
    func requestStreamURL(for streamID: String) async throws -> URL {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AttestationError.unsupported }

        if !UserDefaults.standard.bool(forKey: Self.keyRegisteredDefaultsKey) {
            try await attestAndRegister(service: service)
        }

        do {
            return try await assertStreamURL(for: streamID)
        } catch AttestationError.keyNotFound, AttestationError.signingKeyUnavailable {
            clearRegistration()
            try await attestAndRegister(service: service)
            return try await assertStreamURL(for: streamID)
        }
    }

    // Re-runs the assertion to refresh the short-lived access cookie during
    // playback. The new Set-Cookie lands in the shared cookie store, so AVPlayer's
    // ongoing segment requests pick it up without recreating the player. The
    // returned URL is unused — only the cookie side effect matters.
    func refreshStreamAccess(for streamID: String) async throws {
        _ = try await requestStreamURL(for: streamID)
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

    // MARK: - Attestation (one-time)

    // Creates the app-generated signing key, attests an App Attest key whose
    // clientDataHash commits to SHA256(challenge || signingPublicKey), and
    // registers the signing public key with the backend. After this, Apple is
    // out of the loop forever and all requests use the assertion path.
    private func attestAndRegister(service: DCAppAttestService) async throws {
        let token = try await fetchChallengeToken()
        let challenge = try decodeChallenge(from: token)

        // Second key — a general-purpose Secure Enclave signing key. The private
        // half never leaves the enclave; we persist only the opaque wrapped blob.
        let signingKey = try makeSigningKey()
        let publicKeyData = signingKey.publicKey.rawRepresentation
        try Keychain.save(signingKey.dataRepresentation, tag: Self.signingKeyTag)

        let keyID = try await generateAttestKey(service: service)

        // The binding: commit the signing key's public bytes into clientDataHash.
        // The backend recomputes this exact construction and confirms it equals
        // the nonce inside Apple's attestation.
        var clientData = Data(challenge.utf8)
        clientData.append(publicKeyData)
        let clientDataHash = Data(SHA256.hash(data: clientData))

        let attestation: Data
        do {
            attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            throw AttestationError.attestationFailed(error)
        }

        let endpoint = backendBaseURL.appendingPathComponent("attest-key")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AttestKeyRequest(
            challengeToken: token,
            keyID: keyID,
            attestationObject: attestation.base64EncodedString(),
            publicKey: publicKeyData.base64EncodedString()
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

    // MARK: - Assertion

    // Asserts a request by signing (streamID || challenge) with the registered
    // Secure Enclave signing key, then exchanges the signature for a signed CDN
    // URL. No Apple contact.
    private func assertStreamURL(for streamID: String) async throws -> URL {
        guard let keyID = UserDefaults.standard.string(forKey: Self.keyIDDefaultsKey) else {
            throw AttestationError.signingKeyUnavailable
        }
        let signingKey = try loadSigningKey()

        let token = try await fetchChallengeToken()
        let challenge = try decodeChallenge(from: token)

        // P256.Signing signs SHA256(message) internally; the backend verifies the
        // DER signature against SHA256(streamID || challenge).
        var message = Data(streamID.utf8)
        message.append(Data(challenge.utf8))
        let signature: Data
        do {
            signature = try signingKey.signature(for: message).derRepresentation
        } catch {
            throw AttestationError.signingFailed(error)
        }

        let endpoint = backendBaseURL.appendingPathComponent("assert-and-stream")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AssertRequest(
            challengeToken: token,
            keyID: keyID,
            signature: signature.base64EncodedString(),
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

    // Generates a fresh App Attest key and stores its ID. The App Attest key is
    // used only once, to attest the signing key during attestation.
    private func generateAttestKey(service: DCAppAttestService) async throws -> String {
        do {
            let keyID = try await service.generateKey()
            UserDefaults.standard.set(keyID, forKey: Self.keyIDDefaultsKey)
            return keyID
        } catch {
            throw AttestationError.keyGenerationFailed(error)
        }
    }

    // Creates a device-bound Secure Enclave signing key. Accessible only while the
    // device is unlocked and never synced off-device; no biometry so streaming
    // never prompts the user.
    private func makeSigningKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            &accessError
        ) else {
            throw AttestationError.signingKeyCreationFailed(accessError!.takeRetainedValue())
        }
        do {
            return try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        } catch {
            throw AttestationError.signingKeyCreationFailed(error)
        }
    }

    private func loadSigningKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard let blob = try Keychain.load(tag: Self.signingKeyTag) else {
            throw AttestationError.signingKeyUnavailable
        }
        do {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
        } catch {
            throw AttestationError.signingKeyUnavailable
        }
    }

    private func markRegistered() {
        UserDefaults.standard.set(true, forKey: Self.keyRegisteredDefaultsKey)
    }

    private func clearRegistration() {
        UserDefaults.standard.removeObject(forKey: Self.keyRegisteredDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.keyIDDefaultsKey)
        Keychain.delete(tag: Self.signingKeyTag)
    }
}

// MARK: - Keychain

private enum Keychain {
    static func save(_ data: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AttestationError.keychainFailure(status) }
    }

    static func load(tag: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AttestationError.keychainFailure(status) }
        return item as? Data
    }

    static func delete(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
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
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case challengeToken    = "challenge_token"
        case keyID             = "key_id"
        case attestationObject = "attestation_object"
        case publicKey         = "public_key"
    }
}

private struct AssertRequest: Encodable {
    let challengeToken: String
    let keyID: String
    let signature: String
    let streamID: String

    enum CodingKeys: String, CodingKey {
        case challengeToken = "challenge_token"
        case keyID          = "key_id"
        case signature      = "signature"
        case streamID       = "stream_id"
    }
}

private struct StreamURLResponse: Decodable {
    let streamURL: String

    enum CodingKeys: String, CodingKey {
        case streamURL = "stream_url"
    }
}
