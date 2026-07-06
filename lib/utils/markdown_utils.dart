// lib/utils/markdown_utils.dart
// FIX: Chat History - **bold** markers showing literally in preview
// Usage: MarkdownUtils.stripForPreview(rawText)

class MarkdownUtils {
  /// Strips common markdown syntax for use in plain-text previews.
  /// **bold** → bold  |  *italic* → italic  |  `code` → code  |  # heading → heading
  static String stripForPreview(String text, {int maxLength = 120}) {
    var result = text

        // Bold: **text** or __text__
        .replaceAllMapped(
          RegExp(r'\*\*(.+?)\*\*', dotAll: true),
          (m) => m.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'__(.+?)__', dotAll: true),
          (m) => m.group(1) ?? '',
        )

        // Italic: *text* or _text_
        .replaceAllMapped(
          RegExp(r'\*(.+?)\*', dotAll: true),
          (m) => m.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'_(.+?)_', dotAll: true),
          (m) => m.group(1) ?? '',
        )

        // Inline code: `code`
        .replaceAllMapped(
          RegExp(r'`(.+?)`', dotAll: true),
          (m) => m.group(1) ?? '',
        )

        // Code block: ```...```
        .replaceAllMapped(
          RegExp(r'```[\s\S]*?```'),
          (m) => '',
        )

        // Headings: # ## ### etc
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')

        // Blockquote: > text
        .replaceAll(RegExp(r'^>\s*', multiLine: true), '')

        // Horizontal rule
        .replaceAll(RegExp(r'^---+$', multiLine: true), '')

        // Collapse multiple spaces/newlines to single space
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (maxLength > 0 && result.length > maxLength) {
      result = '${result.substring(0, maxLength)}...';
    }

    return result;
  }

  /// Returns true if text contains markdown syntax
  static bool hasMarkdown(String text) {
    return RegExp(r'\*\*|__|\*|_|`|^#{1,6}\s', multiLine: true).hasMatch(text);
  }
}
