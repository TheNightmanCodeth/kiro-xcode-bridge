import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thread-safe token lifecycle manager.
/// Handles proactive refresh before expiry, with fallback to device code flow.
actor TokenManager {
    private(set) var method: AuthMethod
    private let region: String

    // Static API key — no refresh needed
    private var staticToken: String?

    // Dynamic credentials
    private var credentials: KiroCredentials?

    // MARK: - Init

    init(staticToken: String, method: AuthMethod, region: String) {
        self.staticToken = staticToken
        self.method = method
        self.region = region
    }

    init(credentials: KiroCredentials, method: AuthMethod, region: String) {
        self.credentials = credentials
        self.method = method
        self.region = region
    }

    // MARK: - Public API

    /// The profile ARN from the loaded credentials (for Kiro API requests).
    var profileArn: String? {
        credentials?.profileArn
    }

    /// The auth type of the loaded credentials.
    var authType: AuthType {
        credentials?.authType ?? .kiroDesktop
    }

    /// Returns a valid bearer token, refreshing if needed.
    func getValidToken() async throws -> String {
        if let token = staticToken {
            return token
        }

        guard var creds = credentials else {
            throw KiroBridgeError.noCredentials("No credentials loaded in TokenManager")
        }

        // Refresh proactively if expiring within threshold
        if creds.expiresAt.timeIntervalSinceNow < KiroConfig.tokenRefreshThreshold {
            do {
                creds = try await refresh(creds)
                credentials = creds
                persist(creds)
            } catch {
                // If refresh failed and token is still valid, use it with a warning
                if creds.expiresAt > Date() {
                    writeStderr("kiro-bridge: warning: token refresh failed, using existing token. Error: \(error)\n")
                } else {
                    throw error
                }
            }
        }

        return creds.accessToken
    }

    /// Forces a refresh (called on 401/403 from Kiro API).
    func forceRefresh() async throws -> String {
        guard var creds = credentials else {
            throw KiroBridgeError.noCredentials("No credentials for forced refresh")
        }
        creds = try await refresh(creds)
        credentials = creds
        persist(creds)
        return creds.accessToken
    }

    // MARK: - Refresh

    private func refresh(_ creds: KiroCredentials) async throws -> KiroCredentials {
        switch creds.authType {
        case .kiroDesktop:
            return try await refreshViaKiroDesktop(creds)
        case .awsSSOOIDC:
            return try await refreshViaOIDC(creds)
        }
    }

    private func refreshViaKiroDesktop(_ creds: KiroCredentials) async throws -> KiroCredentials {
        let url = KiroConfig.kiroDesktopRefreshURL(region: creds.region)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("KiroIDE-0.7.45", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": creds.refreshToken])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode != 200 {
            throw KiroBridgeError.tokenRefreshFailed("HTTP \(httpResponse.statusCode) from Kiro Desktop refresh")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["accessToken"] as? String else {
            throw KiroBridgeError.tokenRefreshFailed("Missing accessToken in refresh response")
        }

        let expiresIn = json["expiresIn"] as? Double ?? 3600
        var updated = creds
        updated.accessToken = newAccess
        updated.refreshToken = json["refreshToken"] as? String ?? creds.refreshToken
        updated.expiresAt = Date(timeIntervalSinceNow: expiresIn - 60)
        if let arn = json["profileArn"] as? String { updated.profileArn = arn }
        return updated
    }

    private func refreshViaOIDC(_ creds: KiroCredentials) async throws -> KiroCredentials {
        guard let clientId = creds.clientId, let clientSecret = creds.clientSecret else {
            throw KiroBridgeError.tokenRefreshFailed("Missing clientId/clientSecret for OIDC refresh")
        }

        let url = KiroConfig.awsSSOOIDCURL(region: creds.region)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "grantType": "refresh_token",
            "clientId": clientId,
            "clientSecret": clientSecret,
            "refreshToken": creds.refreshToken,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode != 200 {
            throw KiroBridgeError.tokenRefreshFailed("HTTP \(httpResponse.statusCode) from OIDC refresh")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["accessToken"] as? String else {
            throw KiroBridgeError.tokenRefreshFailed("Missing accessToken in OIDC refresh response")
        }

        let expiresIn = json["expiresIn"] as? Double ?? 3600
        var updated = creds
        updated.accessToken = newAccess
        updated.refreshToken = json["refreshToken"] as? String ?? creds.refreshToken
        updated.expiresAt = Date(timeIntervalSinceNow: expiresIn - 60)
        return updated
    }

    // MARK: - Persistence

    private func persist(_ creds: KiroCredentials) {
        // Write back to source (SQLite or file)
        if creds.sourceDBPath != nil {
            KiroCLIReader.writeBack(credentials: creds)
        } else if let fileURL = creds.sourceCacheFile {
            let file = SSOCacheFile(
                accessToken: creds.accessToken,
                refreshToken: creds.refreshToken,
                expiresAt: ISO8601DateFormatter().string(from: creds.expiresAt),
                region: creds.region,
                clientId: creds.clientId,
                clientSecret: creds.clientSecret,
                startUrl: nil
            )
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: fileURL)
            }
        } else {
            // Bridge-managed credentials → write to bridge cache
            TokenStore.save(credentials: creds)
        }
    }
}
