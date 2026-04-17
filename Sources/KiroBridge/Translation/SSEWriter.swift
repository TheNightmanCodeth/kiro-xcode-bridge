import Foundation

/// Encodes content as Server-Sent Events in OpenAI format.
struct SSEWriter {
    /// Encodes a text chunk as an OpenAI `data: {...}\n\n` SSE event.
    static func chunk(_ text: String, model: String, id: String = UUID().uuidString) -> String {
        let chunk = OpenAIStreamChunk(content: text, model: model, id: id)
        guard let json = try? JSONEncoder().encode(chunk),
              let str = String(data: json, encoding: .utf8) else {
            return ""
        }
        return "data: \(str)\n\n"
    }

    /// The final SSE line signalling the end of the stream.
    static let done = "data: [DONE]\n\n"

    /// A stop-reason chunk followed by [DONE].
    static func stopAndDone(model: String, id: String = UUID().uuidString) -> String {
        let stop = OpenAIStreamChunk.stopChunk(model: model, id: id)
        guard let json = try? JSONEncoder().encode(stop),
              let str = String(data: json, encoding: .utf8) else {
            return done
        }
        return "data: \(str)\n\ndata: [DONE]\n\n"
    }
}
