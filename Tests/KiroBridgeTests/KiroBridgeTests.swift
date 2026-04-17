import Testing
import Foundation
@testable import KiroBridge

// MARK: - FrontMatterParser tests

@Suite("FrontMatterParser")
struct FrontMatterParserTests {
    @Test("No front matter returns full body")
    func noFrontMatter() {
        let raw = "# Hello\n\nThis is content."
        let fm = FrontMatterParser.parse(raw)
        #expect(fm.inclusion == nil)
        #expect(fm.body == raw)
    }

    @Test("Front matter with inclusion: auto")
    func inclusionAuto() {
        let raw = "---\ninclusion: auto\n---\n\n# Hello"
        let fm = FrontMatterParser.parse(raw)
        #expect(fm.inclusion == "auto")
        #expect(fm.body == "# Hello")
    }

    @Test("Front matter with inclusion: manual")
    func inclusionManual() {
        let raw = "---\ninclusion: manual\n---\n\nSecret rules"
        let fm = FrontMatterParser.parse(raw)
        #expect(fm.inclusion == "manual")
        #expect(fm.body == "Secret rules")
    }

    @Test("No closing --- treats as no front matter")
    func unclosedFrontMatter() {
        let raw = "---\ninclusion: auto\n\n# No close"
        let fm = FrontMatterParser.parse(raw)
        #expect(fm.inclusion == nil)
        #expect(fm.body == raw)
    }
}

// MARK: - EventStreamParser tests

@Suite("EventStreamParser")
struct EventStreamParserTests {
    @Test("Parses a simple content event")
    func simpleContent() {
        let parser = EventStreamParser()
        let data = Data(#"{"content":"Hello, world!"}"#.utf8)
        let events = parser.feed(data)
        guard let event = events.first else {
            Issue.record("Expected at least one event")
            return
        }
        if case .text(let text) = event {
            #expect(text == "Hello, world!")
        } else {
            Issue.record("Expected text event, got \(event)")
        }
    }

    @Test("Handles multiple events in one chunk")
    func multipleEvents() {
        let parser = EventStreamParser()
        let raw = #"{"content":"Hello"} {"content":" world"}"#
        let data = Data(raw.utf8)
        let events = parser.feed(data)
        let texts = events.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        #expect(texts == ["Hello", " world"])
    }

    @Test("Handles content split across two chunks")
    func splitChunks() {
        let parser = EventStreamParser()
        let part1 = Data(#"{"cont"#.utf8)
        let part2 = Data(#"ent":"Hello"}"#.utf8)
        let e1 = parser.feed(part1)
        let e2 = parser.feed(part2)
        #expect(e1.isEmpty)
        let texts = e2.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        #expect(texts == ["Hello"])
    }

    @Test("Skips duplicate content")
    func deduplicates() {
        let parser = EventStreamParser()
        let raw = #"{"content":"Hello"} {"content":"Hello"}"#
        let events = parser.feed(Data(raw.utf8))
        let texts = events.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        #expect(texts.count == 1)
        #expect(texts == ["Hello"])
    }
}

// MARK: - SSEWriter tests

@Suite("SSEWriter")
struct SSEWriterTests {
    @Test("Chunk has correct SSE format")
    func chunkFormat() {
        let sse = SSEWriter.chunk("Hello", model: "claude-sonnet-4")
        #expect(sse.hasPrefix("data: "))
        #expect(sse.hasSuffix("\n\n"))
    }

    @Test("Done sentinel is correct")
    func doneFormat() {
        #expect(SSEWriter.done == "data: [DONE]\n\n")
    }
}

// MARK: - MessageMapper tests

@Suite("MessageMapper")
struct MessageMapperTests {
    @Test("System message gets prepended to first user message")
    func systemMessagePrepended() {
        let messages: [OpenAIMessage] = [
            OpenAIMessage(role: "system", content: .text("Be concise.")),
            OpenAIMessage(role: "user",   content: .text("Hello")),
        ]
        let req = OpenAIChatRequest(
            model: "claude-sonnet-4",
            messages: messages,
            stream: true,
            maxTokens: nil,
            temperature: nil,
            systemPrompt: nil
        )
        let kiro = MessageMapper.buildKiroRequest(
            from: req,
            modelId: "claude-sonnet-4",
            systemPrefix: nil,
            profileArn: nil
        )
        let content = kiro.conversationState.currentMessage.userInputMessage.content
        #expect(content.contains("Be concise."))
        #expect(content.contains("Hello"))
    }

    @Test("Steering prefix prepended to content")
    func steeringPrepended() {
        let messages: [OpenAIMessage] = [
            OpenAIMessage(role: "user", content: .text("Write a function")),
        ]
        let req = OpenAIChatRequest(
            model: "claude-sonnet-4",
            messages: messages,
            stream: true,
            maxTokens: nil,
            temperature: nil,
            systemPrompt: nil
        )
        let kiro = MessageMapper.buildKiroRequest(
            from: req,
            modelId: "claude-sonnet-4",
            systemPrefix: "Always use Swift.",
            profileArn: nil
        )
        let content = kiro.conversationState.currentMessage.userInputMessage.content
        #expect(content.contains("Always use Swift."))
        #expect(content.contains("Write a function"))
    }

    @Test("Multi-turn builds history correctly")
    func multiTurnHistory() {
        let messages: [OpenAIMessage] = [
            OpenAIMessage(role: "user",      content: .text("Hello")),
            OpenAIMessage(role: "assistant", content: .text("Hi!")),
            OpenAIMessage(role: "user",      content: .text("How are you?")),
        ]
        let req = OpenAIChatRequest(
            model: "claude-sonnet-4",
            messages: messages,
            stream: true,
            maxTokens: nil,
            temperature: nil,
            systemPrompt: nil
        )
        let kiro = MessageMapper.buildKiroRequest(
            from: req,
            modelId: "claude-sonnet-4",
            systemPrefix: nil,
            profileArn: nil
        )
        let history = kiro.conversationState.history
        #expect(history?.count == 2) // Hello + Hi!
        let currentContent = kiro.conversationState.currentMessage.userInputMessage.content
        #expect(currentContent == "How are you?")
    }
}

// MARK: - ISO8601 helper tests

@Suite("ISO8601 parsing")
struct ISO8601Tests {
    @Test("Parses Z-suffixed date")
    func parsesZDate() {
        let date = parseISO8601("2026-01-12T23:00:00.000Z")
        #expect(date != nil)
    }

    @Test("Parses offset date")
    func parsesOffsetDate() {
        let date = parseISO8601("2026-01-12T23:00:00+00:00")
        #expect(date != nil)
    }

    @Test("Returns nil for nil input")
    func nilInput() {
        #expect(parseISO8601(nil) == nil)
    }
}
