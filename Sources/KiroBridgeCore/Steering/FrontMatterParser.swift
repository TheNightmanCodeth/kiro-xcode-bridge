import Foundation

/// Parses YAML-like front matter from a Markdown file.
///
/// Only the `inclusion` key is extracted — everything else is ignored.
/// Front matter must start on line 1 with `---` and end with a second `---`.
struct FrontMatter {
    let inclusion: String?   // "auto" | "manual" | nil (treated as "auto")
    let body: String         // Markdown content with front matter stripped
}

struct FrontMatterParser {
    static func parse(_ raw: String) -> FrontMatter {
        let lines = raw.components(separatedBy: "\n")

        // Require the very first line to be "---"
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return FrontMatter(inclusion: nil, body: raw)
        }

        // Find the closing "---"
        var closingLine: Int? = nil
        for (i, line) in lines.dropFirst().enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closingLine = i + 1 // index in original array
                break
            }
        }

        guard let closing = closingLine else {
            return FrontMatter(inclusion: nil, body: raw)
        }

        // Parse front matter key-value pairs
        let fmLines = lines[1..<closing]
        var inclusion: String? = nil
        for line in fmLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inclusion:") {
                let value = trimmed.dropFirst("inclusion:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                inclusion = value.isEmpty ? nil : value
            }
        }

        // Body is everything after the closing ---
        let bodyLines = lines[(closing + 1)...]
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)

        return FrontMatter(inclusion: inclusion, body: body)
    }
}
