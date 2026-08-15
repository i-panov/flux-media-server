import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/utils/extensions.dart';

void main() {
  group('StringExtensions.capitalize', () {
    test('capitalizes the first grapheme', () {
      expect('hello'.capitalize, 'Hello');
      expect('hello world'.capitalize, 'Hello world');
    });

    test('does not touch a capitalized string', () {
      expect('Hello'.capitalize, 'Hello');
    });

    test('works with multi-code-unit graphemes (emoji)', () {
      expect('😀 smile'.capitalize, '😀 smile');
    });

    test('handles empty and single-character strings', () {
      expect(''.capitalize, '');
      expect('a'.capitalize, 'A');
    });

    test('does not replace later occurrences of the first grapheme', () {
      expect('london l'.capitalize, 'London l');
    });
  });

  group('DurationExtensions.formatted', () {
    test('formats minutes and seconds', () {
      expect(const Duration(seconds: 65).formatted, '01:05');
    });

    test('formats hours', () {
      expect(
        const Duration(hours: 1, minutes: 2, seconds: 3).formatted,
        '01:02:03',
      );
    });

    test('zero duration', () {
      expect(Duration.zero.formatted, '00:00');
    });
  });
}
