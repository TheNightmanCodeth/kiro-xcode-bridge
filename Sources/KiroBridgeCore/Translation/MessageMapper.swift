import Foundation

/// Maps OpenAI-format messages to the Kiro request format.
struct MessageMapper {
    /// Builds a KiroRequest from an OpenAI chat request, optionally prepending a system prompt.
    static func buildKiroRequest(
        from openAI: OpenAIChatRequest,
        modelId: String,
        systemPrefix: String?,
        profileArn: String?
    ) -> KiroRequest {
        let conversationId = UUID().uuidString

        // Separate system messages
        var systemParts: [String] = []
        var chatMessages: [OpenAIMessage] = []

        for message in openAI.messages {
            if message.role == "system" {
                systemParts.append(message.content.text)
            } else {
                chatMessages.append(message)
            }
        }

        // Build full system prompt (steering + original system)
        var systemComponents: [String] = []
        if let prefix = systemPrefix, !prefix.isEmpty {
            systemComponents.append(prefix)
        }
        systemComponents.append(contentsOf: systemParts)
        let systemPrompt = systemComponents.filter { !$0.isEmpty }.joined(separator: "\n\n")

        // Build history (all messages except the last user message)
        var history: [KiroHistoryMessage] = []
        var currentContent = ""

        // Walk messages: last user message becomes currentMessage, rest become history
        let nonSystemMessages = chatMessages

        if nonSystemMessages.isEmpty {
            currentContent = systemPrompt.isEmpty ? "(empty)" : systemPrompt
        } else {
            // All but the last message go to history
            let historyMessages = nonSystemMessages.dropLast()
            let lastMessage = nonSystemMessages.last!

            // Prepend system prompt to the first user message in history (or current if no history)
            var firstUserHandled = false

            for msg in historyMessages {
                let content: String
                if msg.role == "user" && !firstUserHandled {
                    content = systemPrompt.isEmpty ? msg.content.text : "\(systemPrompt)\n\n\(msg.content.text)"
                    firstUserHandled = true
                } else {
                    content = msg.content.text
                }

                switch msg.role {
                case "user":
                    history.append(.init(body: .user(content: content, modelId: modelId)))
                case "assistant":
                    history.append(.init(body: .assistant(content: content)))
                default:
                    // Treat unknown roles as user
                    history.append(.init(body: .user(content: content, modelId: modelId)))
                }
            }

            // Current message
            var lastContent = lastMessage.content.text
            if lastMessage.role == "user" && !firstUserHandled && !systemPrompt.isEmpty {
                lastContent = "\(systemPrompt)\n\n\(lastContent)"
            }
            currentContent = lastContent.isEmpty ? "Continue" : lastContent
        }

        let userInputMessage = KiroRequest.UserInputMessage(
            content: currentContent,
            modelId: modelId
        )

        let conversationState = KiroRequest.ConversationState(
            conversationId: conversationId,
            currentMessage: .init(userInputMessage: userInputMessage),
            history: history.isEmpty ? nil : history
        )

        return KiroRequest(conversationState: conversationState, profileArn: profileArn)
    }
}
