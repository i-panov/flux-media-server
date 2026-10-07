import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/utils/extensions.dart';

void main() {
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
