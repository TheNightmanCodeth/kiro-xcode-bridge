import Foundation

/// Interactive AWS SSO OIDC device-code login flow.
/// Used when no cached credentials exist (first-time setup).
struct DeviceCodeFlow {
    let region: String
    let startUrl: String

    init(region: String = KiroConfig.defaultRegion, startUrl: String? = nil) {
        self.region = region
        self.startUrl = startUrl ?? "https://view.awsapps.com/start"
    }

    func run() async throws -> KiroCredentials {
        // 1. Register client
        let reg = try await registerClient()
        let clientId = reg["clientId"] as? String ?? ""
        let clientSecret = reg["clientSecret"] as? String ?? ""

        // 2. Start device authorization
        let authResp = try await startDeviceAuth(clientId: clientId, clientSecret: clientSecret)
        let deviceCode = authResp["deviceCode"] as? String ?? ""
        let verificationUri = authResp["verificationUriComplete"] as? String
            ?? authResp["verificationUri"] as? String
            ?? "https://device.sso.\(region).amazonaws.com/"
        let userCode = authResp["userCode"] as? String ?? ""
        let interval = authResp["interval"] as? Int ?? 5

        // 3. Display to user
        print("\nkiro-bridge: No cached credentials found. Starting login...\n")
        print("   Open this URL in your browser:")
        print("   \(verificationUri)\n")
        print("   Enter code: \(userCode)\n")
        print("   Waiting for authorization...")

        // 4. Poll
        return try await pollForToken(
            clientId: clientId,
            clientSecret: clientSecret,
            deviceCode: deviceCode,
            interval: interval
        )
    }

    // MARK: - Private

    private func registerClient() async throws -> [String: Any] {
        let url = KiroConfig.awsSSORegisterURL(region: region)
        let body: [String: Any] = [
            "clientName": "kiro-bridge",
            "clientType": "public",
            "scopes": ["codewhisperer:completions", "codewhisperer:analysis"],
        ]
        return try await httpPostJSON(url: url, body: body)
    }

    private func startDeviceAuth(clientId: String, clientSecret: String) async throws -> [String: Any] {
        let url = KiroConfig.awsSSODeviceAuthURL(region: region)
        let body: [String: Any] = [
            "clientId": clientId,
            "clientSecret": clientSecret,
            "startUrl": startUrl,
        ]
        return try await httpPostJSON(url: url, body: body)
    }

    private func pollForToken(
        clientId: String,
        clientSecret: String,
        deviceCode: String,
        interval: Int
    ) async throws -> KiroCredentials {
        let url = KiroConfig.awsSSOOIDCURL(region: region)

        while true {
            try await Task.sleep(for: .seconds(interval))

            let body: [String: Any] = [
                "clientId": clientId,
                "clientSecret": clientSecret,
                "deviceCode": deviceCode,
                "grantType": "urn:ietf:params:oauth:grant-type:device_code",
            ]

            do {
                let resp = try await httpPostJSON(url: url, body: body)

                guard let accessToken = resp["accessToken"] as? String,
                      let refreshToken = resp["refreshToken"] as? String else {
                    continue
                }

                let expiresIn = resp["expiresIn"] as? Double ?? 3600
                let expiresAt = Date(timeIntervalSinceNow: expiresIn - 60)

                let creds = KiroCredentials(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt,
                    profileArn: resp["profileArn"] as? String,
                    region: region,
                    authType: .awsSSOOIDC,
                    clientId: clientId,
                    clientSecret: clientSecret
                )

                TokenStore.save(credentials: creds)
                print("   Logged in successfully!")
                return creds

            } catch let error as DeviceCodeError {
                switch error {
                case .authorizationPending, .slowDown:
                    continue
                case .accessDenied:
                    throw KiroBridgeError.authorizationError("Login was denied by the user.")
                case .expired:
                    throw KiroBridgeError.authorizationError("Login code expired. Please restart kiro-bridge.")
                }
            }
        }
    }
}

// MARK: - Errors

enum DeviceCodeError: Error {
    case authorizationPending
    case slowDown
    case accessDenied
    case expired
}

// MARK: - HTTP helpers

private func httpPostJSON(url: URL, body: [String: Any]) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.timeoutInterval = 30

    let (data, response) = try await URLSession.shared.data(for: request)
    let httpResponse = response as! HTTPURLResponse

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw KiroBridgeError.parseError("Non-JSON response from \(url)")
    }

    // Check for OIDC errors
    if let errorCode = json["error"] as? String {
        switch errorCode {
        case "authorization_pending": throw DeviceCodeError.authorizationPending
        case "slow_down":             throw DeviceCodeError.slowDown
        case "access_denied":         throw DeviceCodeError.accessDenied
        case "expired_token":         throw DeviceCodeError.expired
        default:
            let msg = json["error_description"] as? String ?? errorCode
            throw KiroBridgeError.authorizationError(msg)
        }
    }

    if httpResponse.statusCode >= 400 {
        throw KiroBridgeError.networkError("HTTP \(httpResponse.statusCode) from \(url)")
    }

    return json
}
