import Foundation

// MARK: - /v1/models

struct OpenAIModel: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    init(id: String, ownedBy: String = "kiro") {
        self.id = id
        self.object = "model"
        self.created = 1_700_000_000
        self.ownedBy = ownedBy
    }

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

struct OpenAIModelList: Codable, Sendable {
    let object: String
    let data: [OpenAIModel]

    init(data: [OpenAIModel]) {
        self.object = "list"
        self.data = data
    }
}

// MARK: - /v1/chat/completions — Request

struct OpenAIChatRequest: Codable, Sendable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool?
    let maxTokens: Int?
    let temperature: Double?
    let systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case systemPrompt = "system"
    }
}

struct OpenAIMessage: Codable, Sendable {
    let role: String
    let content: OpenAIMessageContent

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

/// Content can be a plain string or an array of content parts.
enum OpenAIMessageContent: Sendable {
    case text(String)
    case parts([OpenAIContentPart])

    var text: String {
        switch self {
        case .text(let s): return s
        case .parts(let parts):
            return parts.compactMap { part in
                if case .text(let t) = part.value { return t }
                return nil
            }.joined()
        }
    }
}

extension OpenAIMessageContent: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else {
            let parts = try container.decode([OpenAIContentPart].self)
            self = .parts(parts)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s):
            try container.encode(s)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

struct OpenAIContentPart: Codable, Sendable {
    let type: String
    let value: ContentValue

    enum ContentValue: Sendable {
        case text(String)
        case imageURL(String)
        case other
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            value = .text(text)
        case "image_url":
            let url = try container.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
            value = .imageURL(url)
        default:
            value = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch value {
        case .text(let t):
            try container.encode(t, forKey: .text)
        case .imageURL(let u):
            try container.encode(u, forKey: .imageURL)
        case .other:
            break
        }
    }
}

// MARK: - /v1/chat/completions — Response (streaming chunks)

struct OpenAIStreamChunk: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIStreamChoice]

    init(content: String, model: String, id: String = UUID().uuidString) {
        self.id = "chatcmpl-\(id)"
        self.object = "chat.completion.chunk"
        self.created = Int(Date().timeIntervalSince1970)
        self.model = model
        self.choices = [OpenAIStreamChoice(content: content)]
    }

    // Internal full-field init used by stopChunk
    private init(rawId: String, object: String, created: Int, model: String, choices: [OpenAIStreamChoice]) {
        self.id = rawId
        self.object = object
        self.created = created
        self.model = model
        self.choices = choices
    }

    static func stopChunk(model: String, id: String = UUID().uuidString) -> OpenAIStreamChunk {
        OpenAIStreamChunk(
            rawId: "chatcmpl-\(id)",
            object: "chat.completion.chunk",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [OpenAIStreamChoice(finishReason: "stop")]
        )
    }
}

struct OpenAIStreamChoice: Codable, Sendable {
    let index: Int
    let delta: OpenAIDelta
    let finishReason: String?

    init(content: String) {
        self.index = 0
        self.delta = OpenAIDelta(role: nil, content: content)
        self.finishReason = nil
    }

    init(finishReason: String) {
        self.index = 0
        self.delta = OpenAIDelta(role: nil, content: "")
        self.finishReason = finishReason
    }

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

struct OpenAIDelta: Codable, Sendable {
    let role: String?
    let content: String?
}

// MARK: - /v1/chat/completions — Non-streaming response

struct OpenAIChatResponse: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChatChoice]
    let usage: OpenAIUsage?

    init(content: String, model: String) {
        self.id = "chatcmpl-\(UUID().uuidString)"
        self.object = "chat.completion"
        self.created = Int(Date().timeIntervalSince1970)
        self.model = model
        self.choices = [OpenAIChatChoice(content: content)]
        self.usage = nil
    }
}

struct OpenAIChatChoice: Codable, Sendable {
    let index: Int
    let message: OpenAIChatMessage
    let finishReason: String

    init(content: String) {
        self.index = 0
        self.message = OpenAIChatMessage(role: "assistant", content: content)
        self.finishReason = "stop"
    }

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenAIChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct OpenAIUsage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens     = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens      = "total_tokens"
    }
}
