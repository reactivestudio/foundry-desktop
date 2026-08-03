/// Семья знаков мастера настройки: вендорские марки и пиктограммы частей. Каждый знак перерисован из SVG
/// макета в `Path` (macOS не декодирует SVG нативно) и лежит своим типом рядом — `ClaudeGlyph`,
/// `OpenAIGlyph`, `GeminiGlyph`, `PluginGlyph`, `CLIGlyph`. Все viewBox 64 или 24, знак масштабируется
/// под запрошенный кегль.
enum SetupGlyph { case claude, openai, gemini, plugin, cli }
