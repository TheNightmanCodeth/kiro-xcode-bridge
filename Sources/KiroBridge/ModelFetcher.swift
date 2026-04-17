import Foundation
import Logging

/// Fetches available models from the CodeWhisperer ListAvailableModels API.
/// Falls back to nil on any failure; callers should use the static list as a fallback.
enum ModelFetcher {
  
  enum ModelFetcherError: Error {
    /// An error was thrown encoding the request body
    case encodeBodyFailure(Error)
    /// An error was thrown decoding the response body
    case decodeBodyFailure(Error)
    /// An error was received from the backend
    case apiError(status: Int, response: (HTTPURLResponse, Data))
    /// An error was thrown sending the request
    case networkError(Error)
    /// The json object was valid but not the type we expected it to be
    case invalidJSONObject(String)
  }

  static let logger = Logger(label: "ModelFetcher")

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
    urlRequest.setValue(
      "AmazonCodeWhispererService.ListAvailableModels",
      forHTTPHeaderField: "x-amz-target"
    )
    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    urlRequest.timeoutInterval = 15

    var body: [String: Any] = ["origin": "CLI", "maxResults": 50]
    if let arn = profileArn, !arn.isEmpty {
      body["profileArn"] = arn
    }
    
    do {
      let bodyData = try JSONSerialization.data(withJSONObject: body)
      urlRequest.httpBody = bodyData
    } catch {
      logger.error("Failed to encode request body", error: ModelFetcherError.encodeBodyFailure(error))
      return nil
    }
    
    let data: Data
    let http: HTTPURLResponse
    do {
      let (resData, response) = try await URLSession.shared.data(for: urlRequest)
      http = response as! HTTPURLResponse
      data = resData
    } catch {
      logger.error("Failed to perform network request", error: ModelFetcherError.networkError(error))
      return nil
    }
    
    guard http.statusCode == 200 else {
      let error = ModelFetcherError.apiError(status: http.statusCode, response: (http, data))
      logger.error("Received failure from API", error: error)
      return nil
    }
    
    let jsonObject: Any
    do {
      jsonObject = try JSONSerialization.jsonObject(with: data)
    } catch {
      logger.error("Failed to decode response body", error: ModelFetcherError.decodeBodyFailure(error))
      return nil
    }
    
    guard let json = jsonObject as? [String: Any], let rawModels = json["models"] as? [[String: Any]] else {
      let str = String(data: data, encoding: .utf8) ?? "NaN"
      logger.error("Response object is invalid", error: ModelFetcherError.invalidJSONObject(str))
      return nil
    }

    var models: [OpenAIModel] = [OpenAIModel(id: "auto")]  // always include auto first
    for m in rawModels {
      if let id = m["modelId"] as? String, !id.isEmpty, id != "auto" {
        models.append(OpenAIModel(id: id))
      } else {
        logger.debug("Got weird model: \(m)")
      }
    }
    return models.count > 1 ? models : nil
  }
}


