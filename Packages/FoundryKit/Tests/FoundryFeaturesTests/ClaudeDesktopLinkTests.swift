import Foundation
import Testing

@testable import FoundryFeatures

@Suite("ClaudeDesktopLink")
struct ClaudeDesktopLinkTests {
    @Test("Путь транскрипта: '/' и '.' в cwd превращаются в '-'")
    @MainActor func transcriptPathMunging() {
        let path = ClaudeDesktopLink.transcriptPath(
            sessionID: "abc-123",
            cwd: "/Volumes/Work/PET/books/.claude/worktrees/reading-98372d"
        )
        #expect(path == NSHomeDirectory()
            + "/.claude/projects/-Volumes-Work-PET-books--claude-worktrees-reading-98372d/abc-123.jsonl")
    }
}
