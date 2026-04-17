import Foundation

// MARK: - Kiro API Request (POST /generateAssistantResponse)

struct KiroRequest: Encodable, Sendable {
    let conversationState: ConversationState
    let profileArn: String?

    struct ConversationState: Encodable, Sendable {
        let chatTriggerType: String = "MANUAL"
        let conversationId: String
        let currentMessage: CurrentMessage
        var history: [KiroHistoryMessage]?

        enum CodingKeys: String, CodingKey {
            case chatTriggerType, conversationId, currentMessage, history
        }
    }

    struct CurrentMessage: Encodable, Sendable {
        let userInputMessage: UserInputMessage
    }

    struct UserInputMessage: Encodable, Sendable {
        let content: String
        let modelId: String
        let origin: String
        var userInputMessageContext: UserInputMessageContext?

        init(content: String, modelId: String, origin: String = "AI_EDITOR", userInputMessageContext: UserInputMessageContext? = nil) {
            self.content = content
            self.modelId = modelId
            self.origin = origin
            self.userInputMessageContext = userInputMessageContext
        }

        enum CodingKeys: String, CodingKey {
            case content, modelId, origin, userInputMessageContext
        }
    }

    struct UserInputMessageContext: Encodable, Sendable {
        // Reserved for tool/tool-result passthrough; unused for basic chat
    }
}

/// A history entry returned from previous turns.
struct KiroHistoryMessage: Encodable, Sendable {
    enum Body: Sendable {
        case user(content: String, modelId: String)
        case assistant(content: String)
    }

    let body: Body

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch body {
        case .user(let content, let modelId):
            try container.encode(UserTurn(userInputMessage: .init(content: content, modelId: modelId, origin: "AI_EDITOR")))
        case .assistant(let content):
            try container.encode(AssistantTurn(assistantResponseMessage: .init(content: content)))
        }
    }

    struct UserTurn: Encodable, Sendable {
        let userInputMessage: KiroRequest.UserInputMessage
    }

    struct AssistantTurn: Encodable, Sendable {
        struct AssistantMsg: Encodable, Sendable { let content: String }
        let assistantResponseMessage: AssistantMsg
    }
}

// MARK: - Kiro API Response (streaming event objects)

/// Parsed event extracted from the Kiro response stream.
enum KiroResponseEvent: Sendable {
    case text(String)
    case usage(credits: Double)
    case contextUsage(percentage: Double)
    case stop
}
