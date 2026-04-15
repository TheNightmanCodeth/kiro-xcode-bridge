import Foundation

/// Reads Kiro credentials from ~/.aws/sso/cache/ JSON files.
struct SSOCacheReader {
    /// Scans the SSO cache directory for valid Kiro credential files.
    /// Returns the first file that contains a refreshToken.
    static func read(from cacheDir: URL = KiroConfig.ssoCache) throws -> KiroCredentials? {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else {
            return nil
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        // Sort by modification date, newest first
        let jsonFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA > dateB
            }

        for fileURL in jsonFiles {
            if let creds = try? readFile(fileURL) {
                return creds
            }
        }
        return nil
    }

    static func readFile(_ fileURL: URL) throws -> KiroCredentials? {
        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(SSOCacheFile.self, from: data)

        guard let refreshToken = file.refreshToken else {
            return nil
        }

        let accessToken = file.accessToken ?? ""
        let expiresAt = parseISO8601(file.expiresAt) ?? Date(timeIntervalSinceNow: 3600)
        let region = file.region ?? KiroConfig.defaultRegion
        let authType: AuthType = (file.clientId != nil && file.clientSecret != nil) ? .awsSSOOIDC : .kiroDesktop

        return KiroCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            profileArn: nil,
            region: region,
            authType: authType,
            clientId: file.clientId,
            clientSecret: file.clientSecret,
            sourceCacheFile: fileURL
        )
    }
}
