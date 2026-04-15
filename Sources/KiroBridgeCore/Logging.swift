import Foundation

/// Writes a message to stderr.
///
/// Uses FileHandle.standardError so it compiles under Swift 6 strict concurrency on
/// both macOS and Linux (avoids the C `extern FILE *stderr` global, which Swift 6
/// flags as a shared mutable variable).
func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
