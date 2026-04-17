import Foundation

/// Central configuration constants for kiro-bridge.
enum KiroConfig {
    /// Default port for the local HTTP server.
    static let defaultPort = 7077

    /// Default AWS region.
    static let defaultRegion = "us-east-1"

    /// Kiro backend chat endpoint (relative path).
    static let chatPath = "/generateAssistantResponse"

    /// Kiro API host template. Use `apiHost(region:)`.
    static let apiHostTemplate = "https://q.%@.amazonaws.com"

    /// CodeWhisperer runtime host template. Use `codewhispererURL(region:)`.
    static let codewhispererHostTemplate = "https://codewhisperer.%@.amazonaws.com"

    /// Kiro Desktop Auth refresh URL template.
    static let kiroDesktopRefreshTemplate = "https://prod.%@.auth.desktop.kiro.dev/refreshToken"

    /// AWS SSO OIDC token URL template.
    static let awsSSOOIDCTemplate = "https://oidc.%@.amazonaws.com/token"

    /// AWS SSO OIDC device auth URL template.
    static let awsSSODeviceAuthTemplate = "https://oidc.%@.amazonaws.com/device_authorization"

    /// AWS SSO OIDC client registration URL template.
    static let awsSSORegisterTemplate = "https://oidc.%@.amazonaws.com/client/register"

    /// macOS path to kiro-cli SQLite database.
    static var kiroCLISQLitePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kiro-cli/data.sqlite3")
    }

    /// ~/.aws/sso/cache/ directory for SSO credential files.
    static var ssoCache: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/sso/cache")
    }

    /// Path where kiro-bridge persists its own token cache.
    static var bridgeTokenCache: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/sso/cache/kiro-bridge-token.json")
    }

    /// Seconds before expiry to trigger a proactive token refresh.
    static let tokenRefreshThreshold: TimeInterval = 600

    /// Available models exposed to Xcode.
    /// Note: Kiro API requires dot notation for minor versions (4.5, not 4-5).
    /// Verified valid model IDs (tested against live API): sonnet-4.5, haiku-4.5, sonnet-4, auto.
    static let models: [OpenAIModel] = [
        OpenAIModel(id: "claude-sonnet-4.5",  ownedBy: "kiro"),
        OpenAIModel(id: "claude-haiku-4.5",   ownedBy: "kiro"),
        OpenAIModel(id: "claude-sonnet-4",    ownedBy: "kiro"),
        OpenAIModel(id: "auto",               ownedBy: "kiro"),
    ]

    static func apiHost(region: String) -> String {
        String(format: apiHostTemplate, region)
    }

    static func chatURL(region: String) -> URL {
        URL(string: apiHost(region: region) + chatPath)!
    }

    static func codewhispererURL(region: String) -> URL {
        URL(string: String(format: codewhispererHostTemplate, region))!
    }

    static func kiroDesktopRefreshURL(region: String) -> URL {
        URL(string: String(format: kiroDesktopRefreshTemplate, region))!
    }

    static func awsSSOOIDCURL(region: String) -> URL {
        URL(string: String(format: awsSSOOIDCTemplate, region))!
    }

    static func awsSSODeviceAuthURL(region: String) -> URL {
        URL(string: String(format: awsSSODeviceAuthTemplate, region))!
    }

    static func awsSSORegisterURL(region: String) -> URL {
        URL(string: String(format: awsSSORegisterTemplate, region))!
    }
}

/// Errors thrown by kiro-bridge.
enum KiroBridgeError: Error, CustomStringConvertible {
    case noCredentials(String)
    case tokenRefreshFailed(String)
    case networkError(String)
    case authorizationError(String)
    case parseError(String)
    case sqliteError(String)
    case rateLimited

    var description: String {
        switch self {
        case .noCredentials(let msg):      return "No credentials: \(msg)"
        case .tokenRefreshFailed(let msg): return "Token refresh failed: \(msg)"
        case .networkError(let msg):       return "Network error: \(msg)"
        case .authorizationError(let msg): return "Authorization error: \(msg)"
        case .parseError(let msg):         return "Parse error: \(msg)"
        case .sqliteError(let msg):        return "SQLite error: \(msg)"
        case .rateLimited:                 return "Rate limited by Kiro API"
        }
    }
}
