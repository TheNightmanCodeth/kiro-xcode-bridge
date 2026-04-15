import Foundation

/// Parses the Kiro backend's streaming response.
///
/// Kiro returns a continuous byte stream (not formal binary AWS event stream,
/// despite the naming). Events are JSON objects embedded in the stream,
/// identified by specific opening-key patterns. The parser buffers incoming
/// bytes, finds complete JSON objects, and emits typed events.
///
/// Supported patterns (from kiro-gateway AwsEventStreamParser):
///   `{"content":…}`          → text chunk
///   `{"name":…}`             → tool call start (ignored for now)
///   `{"input":…}`            → tool input continuation (ignored)
///   `{"stop":…}`             → stream stop
///   `{"usage":…}`            → credit usage
///   `{"contextUsagePercentage":…}` → context usage
final class EventStreamParser: @unchecked Sendable {
    private var buffer: String = ""

    // Pattern matching table: (openingKey, eventTag)
    private static let patterns: [(String, String)] = [
        ("{\"content\":", "content"),
        ("{\"name\":",    "tool_start"),
        ("{\"input\":",   "tool_input"),
        ("{\"stop\":",    "tool_stop"),
        ("{\"usage\":",   "usage"),
        ("{\"contextUsagePercentage\":", "context_usage"),
    ]

    // Tracks the last content value to skip duplicates (kiro-gateway behaviour)
    private var lastContent: String?

    /// Feed a chunk of raw bytes from the Kiro response.
    /// Returns zero or more parsed events extracted from the buffered data.
    func feed(_ chunk: Data) -> [KiroResponseEvent] {
        // The Kiro response is a binary AWS event stream: each frame has a 12-byte
        // prelude (total length, headers length, CRC32) followed by ASCII headers and
        // a JSON payload. The CRC bytes are arbitrary binary and are NOT valid UTF-8
        // (e.g. 0xDB 0xE9), which would make String(data:encoding:.utf8) return nil
        // and silently discard the entire chunk — including the JSON content.
        //
        // String(decoding:as:) uses replacement characters (U+FFFD) for invalid bytes
        // instead of failing. The binary framing bytes become garbage characters that
        // won't match any JSON pattern; the ASCII/UTF-8 JSON payload is preserved.
        let text = String(decoding: chunk, as: UTF8.self)
        buffer += text
        return extractEvents()
    }

    // MARK: - Private extraction

    private func extractEvents() -> [KiroResponseEvent] {
        var events: [KiroResponseEvent] = []

        while true {
            // Find the earliest pattern in the current buffer
            var bestPos: String.Index? = nil
            var bestTag: String = ""

            for (pattern, tag) in Self.patterns {
                if let range = buffer.range(of: pattern) {
                    if bestPos == nil || range.lowerBound < bestPos! {
                        bestPos = range.lowerBound
                        bestTag = tag
                    }
                }
            }

            guard let startPos = bestPos else {
                // No complete event marker found; trim buffer to avoid unbounded growth.
                // Keep only the last 64 bytes in case a pattern straddles a chunk boundary.
                if buffer.count > 64 {
                    buffer = String(buffer.suffix(64))
                }
                break
            }

            // Find the matching closing brace
            guard let (jsonStr, afterEnd) = findCompleteJSON(from: startPos) else {
                // JSON not yet complete — wait for more data.
                // Truncate everything before startPos since it has no useful patterns.
                buffer = String(buffer[startPos...])
                break
            }

            // Advance buffer past this JSON object
            buffer = String(buffer[afterEnd...])

            // Parse and dispatch
            if let event = parseEvent(jsonString: jsonStr, tag: bestTag) {
                events.append(event)
            }
        }

        return events
    }

    private func parseEvent(jsonString: String, tag: String) -> KiroResponseEvent? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch tag {
        case "content":
            guard let content = json["content"] as? String else { return nil }
            // Skip duplicates (kiro-gateway deduplication behaviour)
            if content == lastContent { return nil }
            lastContent = content
            return .text(content)

        case "usage":
            let credits = json["usage"] as? Double ?? 0
            return .usage(credits: credits)

        case "context_usage":
            let pct = json["contextUsagePercentage"] as? Double ?? 0
            return .contextUsage(percentage: pct)

        case "tool_stop":
            if json["stop"] != nil {
                return .stop
            }
            return nil

        default:
            return nil
        }
    }

    /// Finds a complete JSON object starting at `start` in `buffer`,
    /// correctly handling nested braces and quoted strings.
    /// Returns the JSON string and the index just past the closing brace,
    /// or nil if the object isn't yet complete.
    private func findCompleteJSON(from start: String.Index) -> (json: String, after: String.Index)? {
        var idx = start
        var depth = 0
        var inString = false
        var escaped = false

        while idx < buffer.endIndex {
            let ch = buffer[idx]

            if escaped {
                escaped = false
                idx = buffer.index(after: idx)
                continue
            }

            if ch == "\\" && inString {
                escaped = true
                idx = buffer.index(after: idx)
                continue
            }

            if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        let after = buffer.index(after: idx)
                        let json = String(buffer[start..<after])
                        return (json, after)
                    }
                }
            }

            idx = buffer.index(after: idx)
        }

        return nil
    }
}
