/// Parses filenames to extract title and year, mirroring the backend parser.
/// Supports patterns like:
///   "Movie.Name.2024.mkv" → title: "Movie Name", year: 2024
///   "Movie.Name (2024).mp4" → title: "Movie Name", year: 2024
///   "Movie.Name.S01E05.mp4" → title: "Movie Name", year: null
class FilenameParseResult {
  const FilenameParseResult({
    required this.title,
    required this.year,
  });

  final String title;
  final int? year;
}

class FilenameParser {
  /// Parses [filename] (basename only) to extract title and optional year.
  static FilenameParseResult parse(String filename) {
    // Pattern: Title.Year.ext  (e.g. "Matrix.1999.mkv")
    final dotMatch = RegExp(r'^(.+)\.(\d{4})\.[^.]+$').firstMatch(filename);
    if (dotMatch != null) {
      final title = dotMatch.group(1)!.replaceAll('.', ' ');
      final year = int.tryParse(dotMatch.group(2)!);
      return FilenameParseResult(title: title, year: year);
    }

    // Pattern: Title (Year).ext  (e.g. "Matrix (1999).mp4")
    final parenMatch = RegExp(r'^(.+)\s*\((\d{4})\)\.[^.]+$').firstMatch(filename);
    if (parenMatch != null) {
      final title = parenMatch.group(1)!.trim();
      final year = int.tryParse(parenMatch.group(2)!);
      return FilenameParseResult(title: title, year: year);
    }

    // Pattern: Title.S01E05.ext
    final episodeMatch = RegExp(r'^(.+)\.S(\d{2})E(\d{2})\..+$').firstMatch(filename);
    if (episodeMatch != null) {
      final title = episodeMatch.group(1)!.replaceAll('.', ' ');
      return FilenameParseResult(title: title, year: null);
    }

    // Fallback: strip extension, replace dots with spaces
    final parts = filename.split('.');
    if (parts.length > 1) {
      parts.removeLast();
    }
    return FilenameParseResult(title: parts.join(' '), year: null);
  }
}
