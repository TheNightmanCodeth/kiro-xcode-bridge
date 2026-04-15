import Foundation

/// Resolves Kiro credentials by trying sources in priority order:
/// 1. KIRO_API_KEY / --api-key (treated as a static bearer token)
/// 2. kiro-cli SQLite database
/// 3. ~/.aws/sso/cache/ JSON files
/// 4. Bridge's own token cache (~/.aws/sso/cache/kiro-bridge-token.json)
/// 5. Interactive device code flow
struct CredentialResolver {
    let apiKey: String?
    let startUrl: String?
    let region: String
    let forceLogin: Bool
    let verbose: Bool

    func resolve() async throws -> TokenManager {
        // 1. API key
        if let key = apiKey, !key.isEmpty {
            if verbose { writeStderr("kiro-bridge: auth: API key\n") }
            return TokenManager(staticToken: key, method: .apiKey, region: region)
        }

        if !forceLogin {
            // 2. kiro-cli SQLite
            if let creds = try? KiroCLIReader.read() {
                if verbose { writeStderr("kiro-bridge: auth: \(AuthMethod.kiroCLISQLite(email: nil))\n") }
                return TokenManager(credentials: creds, method: .kiroCLISQLite(email: nil), region: region)
            }

            // 3. SSO cache
            if let creds = try? SSOCacheReader.read() {
                let filename = creds.sourceCacheFile?.lastPathComponent ?? "unknown"
                if verbose { writeStderr("kiro-bridge: auth: SSO cache (\(filename))\n") }
                return TokenManager(credentials: creds, method: .ssoCache(file: filename), region: region)
            }

            // 4. Bridge cache
            if let creds = TokenStore.load(), creds.expiresAt > Date() {
                if verbose { writeStderr("kiro-bridge: auth: bridge cache\n") }
                return TokenManager(credentials: creds, method: .bridgeCache, region: region)
            }
        }

        // 5. Interactive device code flow
        let flow = DeviceCodeFlow(region: region, startUrl: startUrl)
        let creds = try await flow.run()
        return TokenManager(credentials: creds, method: .deviceCode, region: region)
    }
}
