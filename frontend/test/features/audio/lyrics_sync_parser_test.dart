import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/audio/presentation/utils/lyrics_sync_parser.dart';

void main() {
  group('parseSyncedLyrics', () {
    test('пустые данные — пустой список', () {
      expect(parseSyncedLyrics(''), isEmpty);
      expect(parseSyncedLyrics('   '), isEmpty);
    });

    test('строки без таймкода пропускаются', () {
      final result = parseSyncedLyrics('[00:01.00]first\nбез таймкода\n');
      expect(result, hasLength(1));
      expect(result.single.text, 'first');
    });

    test('доли секунд сохраняются полностью (не режутся toInt)', () {
      final result = parseSyncedLyrics('[01:05.75]текст');
      expect(result.single.time, const Duration(milliseconds: 65750));
    });

    test('доли секунд с одной цифрой после точки', () {
      final result = parseSyncedLyrics('[00:02.5]текст');
      expect(result.single.time, const Duration(milliseconds: 2500));
    });

    test('целые секунды без долей', () {
      final result = parseSyncedLyrics('[00:12]текст');
      expect(result.single.time, const Duration(seconds: 12));
    });

    test('минуты больше 9', () {
      final result = parseSyncedLyrics('[12:34.56]текст');
      expect(
        result.single.time,
        const Duration(minutes: 12, milliseconds: 34560),
      );
    });

    test('множественные таймкоды в одной строке — запись на каждый', () {
      final result = parseSyncedLyrics('[00:10.50][00:15.25]повтор');
      expect(result, hasLength(2));
      expect(result[0].text, 'повтор');
      expect(result[1].text, 'повтор');
      expect(result[0].time, const Duration(milliseconds: 10500));
      expect(result[1].time, const Duration(milliseconds: 15250));
    });

    test('несколько строк — порядок сохраняется', () {
      final result = parseSyncedLyrics(
        '[00:01.00]первая\n[00:02.00]вторая\n',
      );
      expect(result.map((e) => e.text), ['первая', 'вторая']);
    });

    test('текст обрезается по краям', () {
      final result = parseSyncedLyrics('[00:01.00]   текст   ');
      expect(result.single.text, 'текст');
    });
  });
}
