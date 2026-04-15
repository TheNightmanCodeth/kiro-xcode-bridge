import Foundation
import CSQLite

/// Reads Kiro CLI credentials from its SQLite3 database.
struct KiroCLIReader {
    // Token keys searched in priority order (matches kiro-gateway SQLITE_TOKEN_KEYS)
    static let tokenKeys = [
        "kirocli:social:token",
        "kirocli:odic:token",
        "codewhisperer:odic:token",
    ]

    static let registrationKeys = [
        "kirocli:odic:device-registration",
        "codewhisperer:odic:device-registration",
    ]

    /// Attempts to read credentials from the kiro-cli SQLite database.
    /// Returns nil if the database doesn't exist or contains no valid token.
    static func read(from dbPath: URL = KiroConfig.kiroCLISQLitePath) throws -> KiroCredentials? {
        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        // Try each token key in priority order
        var tokenJSON: String?
        var usedKey: String?
        for key in tokenKeys {
            if let value = queryValue(db: db, key: key) {
                tokenJSON = value
                usedKey = key
                break
            }
        }

        guard let tokenJSON, let usedKey else {
            return nil
        }

        // Parse token blob
        guard let tokenData = tokenJSON.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(SQLiteTokenData.self, from: tokenData) else {
            throw KiroBridgeError.parseError("Could not decode SQLite token JSON")
        }

        guard let accessToken = parsed.accessToken,
              let refreshToken = parsed.refreshToken else {
            return nil
        }

        let expiresAt = parseISO8601(parsed.expiresAt) ?? Date(timeIntervalSinceNow: 3600)

        // Try to load device registration (for OIDC refresh)
        var clientId: String?
        var clientSecret: String?
        for regKey in registrationKeys {
            if let regJSON = queryValue(db: db, key: regKey),
               let regData = regJSON.data(using: .utf8),
               let reg = try? JSONDecoder().decode(SQLiteRegistrationData.self, from: regData) {
                clientId = reg.clientId
                clientSecret = reg.clientSecret
                break
            }
        }

        let authType: AuthType = (clientId != nil && clientSecret != nil) ? .awsSSOOIDC : .kiroDesktop
        let ssoRegion = parsed.region ?? KiroConfig.defaultRegion

        return KiroCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            profileArn: parsed.profileArn,
            region: ssoRegion,
            authType: authType,
            clientId: clientId,
            clientSecret: clientSecret,
            scopes: parsed.scopes,
            sourceDBPath: dbPath,
            sourceDBKey: usedKey
        )
    }

    // MARK: - Private helpers

    private static func queryValue(db: OpaquePointer, key: String) -> String? {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM auth_kv WHERE key = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1 as Int, to: sqlite3_destructor_type?.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let cStr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cStr)
    }
}

// MARK: - Write back updated tokens

extension KiroCLIReader {
    /// Writes updated tokens back to the SQLite database after a token refresh.
    static func writeBack(credentials: KiroCredentials) {
        guard let dbPath = credentials.sourceDBPath,
              let key = credentials.sourceDBKey else {
            return
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else {
            fputs("kiro-bridge: warning: could not open SQLite for write-back\n", stderr)
            return
        }
        defer { sqlite3_close(db) }

        let tokenData = SQLiteTokenData(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            expiresAt: ISO8601DateFormatter().string(from: credentials.expiresAt),
            profileArn: credentials.profileArn,
            region: credentials.region,
            scopes: credentials.scopes
        )

        guard let json = try? JSONEncoder().encode(tokenData),
              let jsonString = String(data: json, encoding: .utf8) else {
            return
        }

        var stmt: OpaquePointer?
        let sql = "UPDATE auth_kv SET value = ? WHERE key = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, jsonString, -1, unsafeBitCast(-1 as Int, to: sqlite3_destructor_type?.self))
        sqlite3_bind_text(stmt, 2, key, -1, unsafeBitCast(-1 as Int, to: sqlite3_destructor_type?.self))
        sqlite3_step(stmt)
        sqlite3_changes(db)
    }
}
