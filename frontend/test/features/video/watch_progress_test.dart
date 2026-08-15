import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/utils/watch_progress.dart';

void main() {
  group('isWatchCompleted', () {
    test('явный флаг completed — завершён', () {
      expect(
        isWatchCompleted(position: 5, duration: 1000, completed: true),
        isTrue,
      );
    });

    test('позиция >= 90% длительности — завершён', () {
      expect(
        isWatchCompleted(position: 900, duration: 1000),
        isTrue,
      );
      expect(
        isWatchCompleted(position: 999, duration: 1000),
        isTrue,
      );
    });

    test('позиция < 90% — не завершён', () {
      expect(
        isWatchCompleted(position: 899, duration: 1000),
        isFalse,
      );
      expect(
        isWatchCompleted(position: 0, duration: 1000),
        isFalse,
      );
    });

    test('длительность неизвестна (0) — не завершён по позиции', () {
      expect(
        isWatchCompleted(position: 500, duration: 0),
        isFalse,
      );
    });
  });

  group('shouldShowInContinueWatching', () {
    test('завершённые скрываются из «Продолжить просмотр»', () {
      expect(
        shouldShowInContinueWatching(
          position: 950,
          duration: 1000,
          completed: false,
        ),
        isFalse,
      );
      expect(
        shouldShowInContinueWatching(
          position: 10,
          duration: 1000,
          completed: true,
        ),
        isFalse,
      );
    });

    test('начатые с известной длительностью — показываются', () {
      expect(
        shouldShowInContinueWatching(
          position: 300,
          duration: 1000,
          completed: false,
        ),
        isTrue,
      );
    });

    test('начатые без длительности — показываются только при position > 0', () {
      expect(
        shouldShowInContinueWatching(
          position: 5,
          duration: 0,
          completed: false,
        ),
        isTrue,
      );
      expect(
        shouldShowInContinueWatching(
          position: 0,
          duration: 0,
          completed: false,
        ),
        isFalse,
      );
    });

    test('порог 0.9 — единая константа (видеоэкран и ряд карточек)', () {
      expect(watchCompletionThreshold, 0.9);
    });
  });
}
