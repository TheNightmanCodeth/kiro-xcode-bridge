import Foundation

/// Persists kiro-bridge's own token cache to ~/.aws/sso/cache/kiro-bridge-token.json.
struct TokenStore {
    static func save(credentials: KiroCredentials) {
        let cacheDir = KiroConfig.bridgeTokenCache.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let file = SSOCacheFile(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: ISO8601DateFormatter().string(from: credentials.expiresAt),
            region: credentials.region,
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret,
            startUrl: nil
        )

        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: KiroConfig.bridgeTokenCache)
    }

    static func load() -> KiroCredentials? {
        try? SSOCacheReader.readFile(KiroConfig.bridgeTokenCache)
    }
}

// MARK: - ISO8601 helper (shared across auth files)

func parseISO8601(_ string: String?) -> Date? {
    guard let string else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}
