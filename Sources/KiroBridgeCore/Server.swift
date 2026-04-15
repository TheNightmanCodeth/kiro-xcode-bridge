import Foundation
import Hummingbird

/// Builds and returns the configured Hummingbird application.
func buildApp(
    port: Int,
    region: String,
    tokenManager: TokenManager,
    steeringLoader: SteeringLoader,
    verbose: Bool
) -> some ApplicationProtocol {
    let deps = ChatDependencies(
        tokenManager: tokenManager,
        steeringLoader: steeringLoader,
        region: region,
        verbose: verbose
    )

    let router = Router()

    // Health check
    router.get("/") { _, _ in
        Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: "{\"status\":\"ok\",\"service\":\"kiro-bridge\"}"))
        )
    }

    // GET /v1/models
    router.get("/v1/models") { request, context in
        try await handleModels(request: request, context: context)
    }

    // POST /v1/chat/completions
    router.post("/v1/chat/completions") { request, context in
        try await handleChat(request: request, context: context, deps: deps)
    }

    return Application(
        router: router,
        configuration: .init(address: .hostname("127.0.0.1", port: port))
    )
}
