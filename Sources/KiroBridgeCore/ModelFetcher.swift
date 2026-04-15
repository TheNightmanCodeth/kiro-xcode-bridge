import Foundation

/// Fetches available models from the CodeWhisperer ListAvailableModels API.
/// Falls back to nil on any failure; callers should use the static list as a fallback.
enum ModelFetcher {

    /// Calls AmazonCodeWhispererService.ListAvailableModels and returns the model list.
    /// Always prepends `auto` since Kiro supports it as a meta-model but the API doesn't list it.
    static func fetch(
        token: String,
        profileArn: String?,
        region: String
    ) async -> [OpenAIModel]? {
        let baseURL = KiroConfig.codewhispererURL(region: region)
            .appendingPathComponent("listAvailableModels")

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-amz-json-1.0", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("AmazonCodeWhispererService.ListAvailableModels",
                            forHTTPHeaderField: "x-amz-target")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 15

        var body: [String: Any] = ["origin": "CLI", "maxResults": 50]
        if let arn = profileArn, !arn.isEmpty {
            body["profileArn"] = arn
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        urlRequest.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawModels = json["models"] as? [[String: Any]] else {
            return nil
        }

        var models: [OpenAIModel] = [OpenAIModel(id: "auto")]  // always include auto first
        for m in rawModels {
            if let id = m["modelId"] as? String, !id.isEmpty, id != "auto" {
                models.append(OpenAIModel(id: id))
            }
        }
        return models.count > 1 ? models : nil
    }
}
