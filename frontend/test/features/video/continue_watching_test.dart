import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/video/presentation/utils/continue_watching.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';

Media _media(int id, {int? duration}) => Media(
  id: id,
  title: 'Media $id',
  type: MediaType.video,
  fileSize: 1,
  duration: duration,
);

WatchProgress _progress(
  int mediaId, {
  int? position,
  int? duration,
  bool? completed,
  DateTime? updatedAt,
}) => WatchProgress(
  userId: 1,
  mediaId: mediaId,
  position: position ?? 100,
  duration: duration ?? 1000,
  completed: completed ?? false,
  updatedAt: updatedAt,
);

void main() {
  final t1 = DateTime(2024, 1, 5);
  final t2 = DateTime(2024, 2, 6);
  final t3 = DateTime(2024, 3, 7);

  group('ContinueWatching.build', () {
    test('сортирует по свежести: свежие сверху', () {
      final result = ContinueWatching.build(
        [_media(1), _media(2), _media(3)],
        [
          _progress(1, updatedAt: t1),
          _progress(2, updatedAt: t3),
          _progress(3, updatedAt: t2),
        ],
      );

      expect([for (final e in result.entries) e.media.id], [2, 3, 1]);
      expect(result.byId.keys.toSet(), {1, 2, 3});
    });

    test('отбрасывает досмотренные и завершённые', () {
      final result = ContinueWatching.build(
        [_media(1), _media(2), _media(3)],
        [
          _progress(1, position: 950),
          _progress(2, completed: true),
          _progress(3),
        ],
      );

      expect(result.ids, {3});
    });

    test('берёт длительность из карточки при нуле в прогрессе', () {
      final withDuration = ContinueWatching.build(
        [_media(1, duration: 1000)],
        [_progress(1, duration: 0)],
      );
      expect(withDuration.ids, {1});

      final withoutDuration = ContinueWatching.build(
        [_media(1)],
        [_progress(1, duration: 0)],
      );
      expect(withoutDuration.ids, {1});
    });

    test('пусто на пустом входе', () {
      expect(ContinueWatching.build([], [_progress(1)]).isEmpty, isTrue);
      expect(ContinueWatching.build([_media(1)], []).isEmpty, isTrue);
    });
  });

  group('splitSection', () {
    test('режет ровно по лимиту', () {
      final split = splitSection([1, 2, 3, 4, 5], 3);
      expect(split.visible, [1, 2, 3]);
      expect(split.rest, [4, 5]);
    });

    test('короткий список целиком видимый', () {
      final split = splitSection([1, 2], 10);
      expect(split.visible, [1, 2]);
      expect(split.rest, isEmpty);
    });

    test('ровно лимит — остатка нет', () {
      final split = splitSection([1, 2, 3], 3);
      expect(split.visible, [1, 2, 3]);
      expect(split.rest, isEmpty);
    });
  });
}
