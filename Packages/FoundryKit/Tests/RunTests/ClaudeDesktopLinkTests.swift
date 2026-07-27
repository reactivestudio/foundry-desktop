import Foundation
import Testing

@testable import Run

@Suite("ClaudeDesktopLink")
struct ClaudeDesktopLinkTests {
    @Test("Путь транскрипта: '/' и '.' в projectDirectory превращаются в '-'")
    @MainActor func transcriptPathEscapesProjectDirectory() {
        let path = ClaudeDesktopLink.transcriptPath(
            sessionID: "abc-123",
            projectDirectory: "/Volumes/Work/PET/books/.claude/worktrees/reading-98372d"
        )
        #expect(
            path == NSHomeDirectory()
                + "/.claude/projects/-Volumes-Work-PET-books--claude-worktrees-reading-98372d/abc-123.jsonl")
    }
}
