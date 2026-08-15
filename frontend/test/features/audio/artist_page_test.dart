import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/audio/presentation/utils/download_batch.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _fakeMedia(int id) => Media(
      id: id,
      title: 'Track $id',
      year: 2024,
      type: MediaType.audio,
      fileSize: 1024,
    );

Future<bool> Function(int mediaId) _isCachedFor(int cachedId) {
  return (id) async => id == cachedId;
}

void main() {
  group('filterUncachedTracks', () {
    test('исключает уже скачанные треки', () async {
      final tracks = [_fakeMedia(1), _fakeMedia(2), _fakeMedia(3)];

      final pending = await filterUncachedTracks(
        tracks,
        _isCachedFor(2),
      );

      expect(pending.map((m) => m.id), [1, 3]);
    });

    test('все скачаны — пустой результат', () async {
      final pending = await filterUncachedTracks(
        [_fakeMedia(1)],
        (_) async => true,
      );

      expect(pending, isEmpty);
    });
  });

  group('downloadTracksBatch', () {
    test('все треки скачаны — downloaded = N, failed = 0', () async {
      final downloadedIds = <int>[];
      final result = await downloadTracksBatch(
        pending: [_fakeMedia(1), _fakeMedia(2), _fakeMedia(3)],
        download: (track) async => downloadedIds.add(track.id),
        isDownloaded: downloadedIds.contains,
        isFailed: (_) => false,
      );

      expect(result.downloaded, 3);
      expect(result.failed, 0);
    });

    test('исключение в download не роняет пачку — failed = 1', () async {
      final result = await downloadTracksBatch(
        pending: [_fakeMedia(1), _fakeMedia(2), _fakeMedia(3)],
        download: (track) async {
          if (track.id == 2) throw Exception('boom');
        },
        isDownloaded: (id) => id != 2,
        isFailed: (_) => false,
      );

      expect(result.downloaded, 2);
      expect(result.failed, 1);
    });

    test('CRITICAL #20: исключение в первом треке не блокирует остальные',
        () async {
      final called = <int>[];
      final result = await downloadTracksBatch(
        pending: [_fakeMedia(1), _fakeMedia(2), _fakeMedia(3)],
        download: (track) async {
          called.add(track.id);
          if (track.id == 1) throw Exception('boom');
        },
        isDownloaded: (id) => id != 1,
        isFailed: (_) => false,
      );

      expect(called.toSet(), {1, 2, 3});
      expect(result.downloaded, 2);
      expect(result.failed, 1);
    });

    test('состояние DownloadError учитывается как failed', () async {
      final result = await downloadTracksBatch(
        pending: [_fakeMedia(1), _fakeMedia(2)],
        download: (_) async {},
        isDownloaded: (id) => id == 1,
        isFailed: (id) => id == 2,
      );

      expect(result.downloaded, 1);
      expect(result.failed, 1);
    });

    test('отменённые (idle) треки не считаются ни туда, ни сюда', () async {
      final result = await downloadTracksBatch(
        pending: [_fakeMedia(1), _fakeMedia(2)],
        download: (_) async {},
        isDownloaded: (_) => false,
        isFailed: (_) => false,
      );

      expect(result.downloaded, 0);
      expect(result.failed, 0);
    });

    test('пустой pending — 0/0 без вызовов', () async {
      final called = <int>[];
      final result = await downloadTracksBatch(
        pending: [],
        download: (track) async => called.add(track.id),
        isDownloaded: (_) => true,
        isFailed: (_) => false,
      );

      expect(result, (downloaded: 0, failed: 0));
      expect(called, isEmpty);
    });

    test('onTrackDone вызывается после каждого трека (живой прогресс)',
        () async {
      final progress = <(int, int)>[];
      await downloadTracksBatch(
        pending: [_fakeMedia(1), _fakeMedia(2)],
        download: (_) async {},
        isDownloaded: (_) => true,
        isFailed: (_) => false,
        onTrackDone: (done, failed) => progress.add((done, failed)),
      );

      expect(progress, [(1, 0), (2, 0)]);
    });

    test('конкурентность ограничена по умолчанию (не больше 4)', () async {
      var active = 0;
      var maxActive = 0;
      await downloadTracksBatch(
        pending: List.generate(10, (i) => _fakeMedia(i + 1)),
        download: (_) async {
          active++;
          maxActive = maxActive < active ? active : maxActive;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
        },
        isDownloaded: (_) => true,
        isFailed: (_) => false,
      );

      expect(maxActive, lessThanOrEqualTo(4));
    });
  });
}
