import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/utils/filename_parser.dart';

void main() {
  group('FilenameParser.parse', () {
    test('dot pattern: title with dots becomes spaces', () {
      final r = FilenameParser.parse('Movie.Name.2024.mkv');
      expect(r.title, 'Movie Name');
      expect(r.year, 2024);
    });

    test('paren pattern replaces dots with spaces (unified with dot pattern)',
        () {
      final r = FilenameParser.parse('Movie.Name (2024).mp4');
      expect(r.title, 'Movie Name');
      expect(r.year, 2024);
    });

    test('paren pattern trims whitespace around title', () {
      final r = FilenameParser.parse('Movie  (1999).mp4');
      expect(r.title, 'Movie');
      expect(r.year, 1999);
    });

    test('episode pattern', () {
      final r = FilenameParser.parse('Movie.Name.S01E05.mp4');
      expect(r.title, 'Movie Name');
      expect(r.year, isNull);
    });

    test('fallback strips extension and joins with spaces', () {
      final r = FilenameParser.parse('plain.title.mkv');
      expect(r.title, 'plain title');
      expect(r.year, isNull);
    });
  });
}
