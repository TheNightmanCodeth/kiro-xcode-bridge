import Foundation
import Hummingbird

/// Handles GET /v1/models — returns the list of available Kiro models in OpenAI format.
func handleModels(request _: Request, context _: some RequestContext, models: [OpenAIModel]) async throws -> Response {
    let list = OpenAIModelList(data: models)
    let data = try JSONEncoder().encode(list)

    var headers = HTTPFields()
    headers[.contentType] = "application/json"

    return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(data: data)))
}
