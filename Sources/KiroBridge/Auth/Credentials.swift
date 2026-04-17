import Foundation

// MARK: - Credential types

/// How the current access token was obtained.
enum AuthMethod: CustomStringConvertible, Sendable {
    case apiKey
    case kiroCLISQLite(email: String?)
    case ssoCache(file: String)
    case deviceCode
    case bridgeCache

    var description: String {
        switch self {
        case .apiKey:
            return "API key"
        case .kiroCLISQLite(let email):
            return email.map { "kiro-cli SQLite (\($0))" } ?? "kiro-cli SQLite"
        case .ssoCache(let file):
            return "SSO cache (\(file))"
        case .deviceCode:
            return "Device code flow"
        case .bridgeCache:
            return "kiro-bridge token cache"
        }
    }
}

/// Auth flow used for token refresh.
enum AuthType: Sendable {
    /// Kiro Desktop auth: POST to auth.desktop.kiro.dev/refreshToken
    case kiroDesktop
    /// AWS SSO OIDC: POST to oidc.amazonaws.com/token
    case awsSSOOIDC
}

/// Parsed credential set, including tokens and metadata for refresh.
struct KiroCredentials: Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var profileArn: String?
    var region: String           // SSO region (for OIDC refresh endpoint)
    var authType: AuthType
    // AWS SSO OIDC fields
    var clientId: String?
    var clientSecret: String?
    var scopes: [String]?
    /// Where to write updated tokens after a refresh.
    var sourceDBPath: URL?
    var sourceDBKey: String?
    var sourceCacheFile: URL?
}

// MARK: - JSON decodable wrappers

/// JSON structure for the SQLite token blob (snake_case keys from kiro-cli Rust).
struct SQLiteTokenData: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: String?
    let profileArn: String?
    let region: String?
    let scopes: [String]?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt    = "expires_at"
        case profileArn   = "profile_arn"
        case region
        case scopes
    }
}

/// JSON structure for the SQLite device-registration blob.
struct SQLiteRegistrationData: Codable {
    let clientId: String?
    let clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case clientId     = "client_id"
        case clientSecret = "client_secret"
    }
}

/// JSON structure for SSO cache files (~/.aws/sso/cache/*.json) — camelCase.
struct SSOCacheFile: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: String?
    let region: String?
    let clientId: String?
    let clientSecret: String?
    let startUrl: String?
}

/// JSON structure for the bridge's own cache file.
typealias BridgeCacheFile = SSOCacheFile
