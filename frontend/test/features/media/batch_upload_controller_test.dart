import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/batch_upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:fpdart/fpdart.dart';

class _FakeRepository implements MediaRepository {
  /// Хэши, считающиеся дубликатами.
  Set<String> existingHashes = {};

  /// Хэши, лежащие в корзине: перезалив упирается в намёк,
  /// а не в молчаливый дубликат.
  Set<String> trashedHashes = {};
  UploadStatus? statusResult;
  int cancelled = 0;

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title, bool trashed})>>
  checkHash(String hash) async => Right((
    exists: existingHashes.contains(hash) || trashedHashes.contains(hash),
    mediaId: null,
    title: null,
    trashed: trashedHashes.contains(hash),
  ));

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async => Right(UploadResult(jobId: filePath.hashCode));

  @override
  Future<Either<Failure, UploadStatus>> getUploadStatus(int jobId) async =>
      Right(statusResult ?? UploadStatus(id: jobId, status: 'done'));

  @override
  Future<Either<Failure, void>> cancelUpload(int jobId) async {
    cancelled++;
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchUploadItem _item(String name) => BatchUploadItem(
  filePath: '/tmp/$name',
  fileName: name,
  fileSize: 1024,
);

void main() {
  late _FakeRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepository();
    container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    // Оба autoDispose-контроллера живут пока их слушают.
    final keepAlive = container.listen<UploadState>(
      uploadControllerProvider,
      (_, _) {},
    );
    final keepBatch = container.listen<BatchUploadState>(
      batchUploadControllerProvider,
      (_, _) {},
    );
    addTearDown(() {
      keepAlive.close();
      keepBatch.close();
      container.dispose();
    });
  });

  BatchUploadController batch() =>
      container.read(batchUploadControllerProvider.notifier);

  test('пачка: успех + дубликат + продолжение после дубликата', () async {
    // Хэшер детерминированный: хэш = путь (дубликат = тот же путь).
    batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher =
        (path, _) async => 'hash-of-$path';
    repo.existingHashes = {'hash-of-/tmp/b.mp4'};

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.doneCount, 1);
    expect(summary.duplicateCount, 1);
    expect(summary.failedCount, 0);
    expect(summary.items[0].status, BatchItemStatus.done);
    expect(summary.items[1].status, BatchItemStatus.duplicate);
  });

  test('отмена останавливает пачку, остаток помечается', () async {
    batch().setFiles([_item('a.mp4'), _item('b.mp4'), _item('c.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher =
        (path, isCancelled) async {
          if (path.endsWith('a.mp4')) {
            batch().cancelAll();
            await Future<void>.delayed(Duration.zero);
          }
          return 'hash-$path';
        };

    final summary = await batch().startAll(mediaType: 'video');

    // Первый влетел в отмену, остальные помечены отменёнными.
    expect(summary.isRunning, false);
    expect(
      summary.items.every(
        (i) =>
            i.status == BatchItemStatus.cancelled ||
            i.status == BatchItemStatus.done,
      ),
      true,
    );
    expect(
      summary.items.any((i) => i.status == BatchItemStatus.cancelled),
      true,
    );
  });

  test('ошибка одного файла не валит пачку', () async {
    batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher =
        (path, _) async => throw Exception('hash boom');

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.doneCount, 0);
    expect(summary.failedCount, 2);
  });

  test('хэш из корзины — failed с намёком, а не дубликат', () async {
    batch().setFiles([_item('a.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher =
        (path, _) async => 'hash-$path';
    repo.trashedHashes = {'hash-/tmp/a.mp4'};

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.doneCount, 0);
    expect(summary.duplicateCount, 0);
    expect(summary.failedCount, 1);
    expect(
      summary.items.single.errorMessage,
      contains('trash'),
    );
  });

  test('retryFailed перепроганяет только упавшие', () async {
    batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
    var failA = true;
    container.read(uploadControllerProvider.notifier).hasher = (path, _) async {
      if (failA && path.endsWith('a.mp4')) throw Exception('hash boom');
      return 'hash-$path';
    };

    final first = await batch().startAll(mediaType: 'video');
    expect(first.failedCount, 1);
    expect(first.doneCount, 1);

    failA = false;
    final second = await batch().retryFailed(mediaType: 'video');
    expect(second.failedCount, 0);
    expect(second.doneCount, 2);
    expect(
      second.items.every(
        (i) =>
            i.status == BatchItemStatus.done ||
            i.status == BatchItemStatus.duplicate,
      ),
      true,
    );
  });

  test('setFiles во время running игнорируется', () async {
    batch().setFiles([_item('a.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher =
        (path, _) async {
          // Пока первый файл в работе — подмена списка запрещена.
          batch().setFiles([_item('x.mp4')]);
          return 'hash-$path';
        };

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.items.map((i) => i.fileName), ['a.mp4']);
  });

  test('пустой startAll возвращает покой без работы', () async {
    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.isRunning, false);
    expect(summary.items, isEmpty);
  });
}
