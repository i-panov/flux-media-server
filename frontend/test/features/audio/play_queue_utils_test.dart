import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/audio/presentation/utils/play_queue_utils.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia(int id) => Media(
      id: id,
      title: 'Track $id',
      year: 2024,
      type: MediaType.audio,
      fileSize: 1024,
    );

void main() {
  group('buildPlayQueue', () {
    test('трек есть в очереди — сохраняется его индекс', () {
      final queue = [_fakeMedia(1), _fakeMedia(2), _fakeMedia(3)];
      final result = buildPlayQueue(
        media: _fakeMedia(2),
        fallbackQueue: queue,
        fullQueue: queue,
      );

      expect(result.startIndex, 1);
      expect(result.queue.map((m) => m.id), [1, 2, 3]);
    });

    test('MAJOR: трека нет в очереди — вставляется в начало, а не трек №0',
        () {
      final queue = [_fakeMedia(1), _fakeMedia(2)];
      final result = buildPlayQueue(
        media: _fakeMedia(99),
        fallbackQueue: queue,
        fullQueue: queue,
      );

      expect(result.startIndex, 0);
      expect(result.queue.first.id, 99);
      expect(result.queue, hasLength(3));
    });

    test('fullQueue null — используется fallbackQueue (офлайн)', () {
      final fallback = [_fakeMedia(7), _fakeMedia(8)];
      final result = buildPlayQueue(
        media: _fakeMedia(7),
        fallbackQueue: fallback,
      );

      expect(result.queue.map((m) => m.id), [7, 8]);
      expect(result.startIndex, 0);
    });

    test('пустая очередь — трек вставляется единственным', () {
      final result = buildPlayQueue(
        media: _fakeMedia(5),
        fallbackQueue: [],
      );

      expect(result.queue.map((m) => m.id), [5]);
      expect(result.startIndex, 0);
    });
  });
}
