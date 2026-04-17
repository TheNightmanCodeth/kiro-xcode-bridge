import Foundation
import Hummingbird
import NIOCore

/// Dependencies injected into the chat handler.
struct ChatDependencies: Sendable {
    let tokenManager: TokenManager
    let steeringLoader: SteeringLoader
    let region: String
    let verbose: Bool
}

/// Handles POST /v1/chat/completions
func handleChat(
    request: Request,
    context: some RequestContext,
    deps: ChatDependencies
) async throws -> Response {
    // 1. Decode the OpenAI request
    let body = try await request.body.collect(upTo: 8 * 1024 * 1024)
    let openAIRequest = try JSONDecoder().decode(OpenAIChatRequest.self, from: Data(buffer: body))

    if deps.verbose {
        fputs("kiro-bridge: POST /v1/chat/completions model=\(openAIRequest.model)\n", stderr)
    }

    // 2. Get bearer token
    let token: String
    do {
        token = try await deps.tokenManager.getValidToken()
    } catch {
        throw HTTPError(.unauthorized, message: "Authentication failed: \(error)")
    }

    // 3. Steering rules
    let steering = deps.steeringLoader.rules

    // 4. Map to Kiro request
    // Strip provider prefix (e.g. "kiro/claude-sonnet-4.5" → "claude-sonnet-4.5")
    let rawModel = openAIRequest.model
    let strippedModel = rawModel.contains("/")
        ? String(rawModel.split(separator: "/").last ?? Substring(rawModel))
        : rawModel
    // Normalize model ID to the dot-notation Kiro expects (e.g. "claude-sonnet-4-5" → "claude-sonnet-4.5")
    let modelId = normalizeModelId(strippedModel)

    // profileArn is only required for Kiro Desktop auth.
    // Sending it for AWS SSO OIDC / Builder ID users causes a 403.
    let profileArn: String?
    let authType = await deps.tokenManager.authType
    if authType == .kiroDesktop {
        profileArn = await deps.tokenManager.profileArn
    } else {
        profileArn = nil
    }

    let kiroRequest = MessageMapper.buildKiroRequest(
        from: openAIRequest,
        modelId: modelId,
        systemPrefix: steering.isEmpty ? nil : steering,
        profileArn: profileArn
    )

    if deps.verbose {
        fputs("kiro-bridge: model: \(rawModel) → \(modelId), auth: \(authType)\n", stderr)
    }

    // 5. Build upstream URLRequest
    let urlRequest = try buildURLRequest(
        region: deps.region,
        token: token,
        kiroRequest: kiroRequest
    )

    if deps.verbose {
        fputs("kiro-bridge: → POST \(KiroConfig.chatURL(region: deps.region))\n", stderr)
    }

    let isStreaming = openAIRequest.stream ?? true

    if isStreaming {
        return streamingResponse(
            urlRequest: urlRequest,
            model: rawModel,
            tokenManager: deps.tokenManager,
            verbose: deps.verbose
        )
    } else {
        return try await nonStreamingResponse(
            urlRequest: urlRequest,
            model: rawModel,
            tokenManager: deps.tokenManager,
            verbose: deps.verbose
        )
    }
}

// MARK: - Streaming

private func streamingResponse(
    urlRequest: URLRequest,
    model: String,
    tokenManager: TokenManager,
    verbose: Bool
) -> Response {
    // Use AsyncStream<ByteBuffer> so we can write from a background Task
    // without needing inout access to the ResponseBodyWriter.
    let (bufStream, continuation) = AsyncStream.makeStream(of: ByteBuffer.self)

    Task {
        defer { continuation.finish() }
        do {
            let (asyncBytes, urlResponse) = try await URLSession.shared.bytes(for: urlRequest)
            let httpResponse = urlResponse as! HTTPURLResponse

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Drain body before attempting refresh
                var errBody = Data()
                for try await byte in asyncBytes { errBody.append(byte) }
                let errBodyStr = String(data: errBody, encoding: .utf8) ?? ""
                fputs("kiro-bridge: \(httpResponse.statusCode) body: \(errBodyStr.prefix(500))\n", stderr)
                _ = try await tokenManager.forceRefresh()
                let errMsg = "data: {\"error\":\"HTTP \(httpResponse.statusCode) — token refreshed, please retry\"}\n\ndata: [DONE]\n\n"
                continuation.yield(ByteBuffer(string: errMsg))
                return
            }

            if httpResponse.statusCode >= 400 {
                // Collect error body for diagnostics
                var errBody = Data()
                for try await byte in asyncBytes { errBody.append(byte) }
                let errBodyStr = String(data: errBody, encoding: .utf8) ?? "(no body)"
                fputs("kiro-bridge: HTTP \(httpResponse.statusCode) error: \(errBodyStr.prefix(500))\n", stderr)
                let escaped = errBodyStr.prefix(200).replacingOccurrences(of: "\"", with: "\\\"")
                let errMsg = "data: {\"error\":\"HTTP \(httpResponse.statusCode): \(escaped)\"}\n\ndata: [DONE]\n\n"
                continuation.yield(ByteBuffer(string: errMsg))
                return
            }

            let parser = EventStreamParser()
            var chunkBuffer = Data()
            chunkBuffer.reserveCapacity(4096)
            let id = UUID().uuidString

            for try await byte in asyncBytes {
                chunkBuffer.append(byte)

                if byte == UInt8(ascii: "}") {
                    let events = await parser.feed(chunkBuffer)
                    chunkBuffer.removeAll(keepingCapacity: true)

                    for event in events {
                        if case .text(let text) = event, !text.isEmpty {
                            let sseData = SSEWriter.chunk(text, model: model, id: id)
                            continuation.yield(ByteBuffer(string: sseData))
                            if verbose {
                                fputs("kiro-bridge: ← \(text.prefix(60))\n", stderr)
                            }
                        }
                    }
                }
            }

            // Flush remaining data
            if !chunkBuffer.isEmpty {
                for event in await parser.feed(chunkBuffer) {
                    if case .text(let text) = event, !text.isEmpty {
                        continuation.yield(ByteBuffer(string: SSEWriter.chunk(text, model: model, id: id)))
                    }
                }
            }

            continuation.yield(ByteBuffer(string: SSEWriter.stopAndDone(model: model, id: id)))

        } catch {
            let errMsg = "data: {\"error\":\"\(error.localizedDescription)\"}\n\ndata: [DONE]\n\n"
            continuation.yield(ByteBuffer(string: errMsg))
        }
    }

    var headers = HTTPFields()
    headers[.contentType] = "text/event-stream"
    headers[.cacheControl] = "no-cache"

    return Response(
        status: .ok,
        headers: headers,
        body: .init(asyncSequence: bufStream)
    )
}

// MARK: - Non-streaming

private func nonStreamingResponse(
    urlRequest: URLRequest,
    model: String,
    tokenManager: TokenManager,
    verbose: Bool
) async throws -> Response {
    let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
    let httpResponse = urlResponse as! HTTPURLResponse

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        _ = try await tokenManager.forceRefresh()
        throw KiroBridgeError.authorizationError("HTTP \(httpResponse.statusCode) — token refreshed, please retry")
    }

    if httpResponse.statusCode >= 400 {
        throw KiroBridgeError.networkError("HTTP \(httpResponse.statusCode) from Kiro API")
    }

    let parser = EventStreamParser()
    let events = await parser.feed(data)
    let fullText = events.compactMap { event -> String? in
        if case .text(let t) = event { return t }
        return nil
    }.joined()

    let response = OpenAIChatResponse(content: fullText, model: model)
    let responseData = try JSONEncoder().encode(response)

    var headers = HTTPFields()
    headers[.contentType] = "application/json"

    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: .init(data: responseData))
    )
}

// MARK: - URLRequest builder

private func buildURLRequest(
    region: String,
    token: String,
    kiroRequest: KiroRequest
) throws -> URLRequest {
    let chatURL = KiroConfig.chatURL(region: region)
    var urlRequest = URLRequest(url: chatURL)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json",       forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(token)",         forHTTPHeaderField: "Authorization")
    urlRequest.setValue(kiroUserAgent(),           forHTTPHeaderField: "User-Agent")
    urlRequest.setValue(kiroXAmzUserAgent(),       forHTTPHeaderField: "x-amz-user-agent")
    urlRequest.setValue("true",                    forHTTPHeaderField: "x-amzn-codewhisperer-optout")
    urlRequest.setValue("vibe",                    forHTTPHeaderField: "x-amzn-kiro-agent-mode")
    urlRequest.setValue(UUID().uuidString,         forHTTPHeaderField: "amz-sdk-invocation-id")
    urlRequest.setValue("attempt=1; max=3",        forHTTPHeaderField: "amz-sdk-request")
    urlRequest.timeoutInterval = 600

    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    urlRequest.httpBody = try encoder.encode(kiroRequest)
    return urlRequest
}

// MARK: - Headers

private func kiroUserAgent() -> String {
    "aws-sdk-js/1.0.27 ua/2.1 os/macos lang/swift api/codewhispererstreaming#1.0.27 m/E KiroIDE-0.7.45-\(machineFingerprint())"
}

private func kiroXAmzUserAgent() -> String {
    "aws-sdk-js/1.0.27 KiroIDE-0.7.45-\(machineFingerprint())"
}

private let _fingerprint: String = {
    let id = "\(ProcessInfo.processInfo.hostName)-kiro-bridge"
    var hash: UInt64 = 14695981039346656037
    for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
    }
    return String(format: "%016x", hash)
}()

private func machineFingerprint() -> String { _fingerprint }

// MARK: - Model ID normalization

/// Converts dash-separated minor versions to dot notation that Kiro expects.
/// e.g. "claude-sonnet-4-5" → "claude-sonnet-4.5"
///      "claude-haiku-4-5"  → "claude-haiku-4.5"
///      "claude-sonnet-4"   → "claude-sonnet-4"   (unchanged)
private func normalizeModelId(_ id: String) -> String {
    // Match trailing "-<major>-<minor>" suffix and convert to "-<major>.<minor>"
    let parts = id.split(separator: "-", omittingEmptySubsequences: false)
    // If the last two components are both numeric digits, join them with a dot
    if parts.count >= 2,
       let _ = Int(parts[parts.count - 1]),
       let _ = Int(parts[parts.count - 2]) {
        let prefix = parts.dropLast(2).joined(separator: "-")
        return "\(prefix)-\(parts[parts.count - 2]).\(parts[parts.count - 1])"
    }
    return id
}
