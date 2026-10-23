import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_source.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/batch_upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:flux_media_server/features/media/presentation/services/upload_notifications.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/upload_source_helpers.dart';

class _FakeRepository implements MediaRepository {
  /// Хэши, считающиеся дубликатами.
  Set<String> existingHashes = {};

  /// Хэши, лежащие в корзине: перезалив упирается в намёк,
  /// а не в молчаливый дубликат.
  Set<String> trashedHashes = {};

  /// Названия дубликатов по хэшу (сервер отдаёт title совпавшего).
  Map<String, String> titles = {};
  UploadStatus? statusResult;
  int cancelled = 0;

  /// Типы медиа, с которыми уходили файлы: проверка «чей тип уходит
  /// на сервер» для повторного прогона.
  final List<String> uploadedTypes = [];

  @override
  Future<
    Either<Failure, ({bool exists, int? mediaId, String? title, bool trashed})>
  >
  checkHash(String hash) async => Right((
    exists: existingHashes.contains(hash) || trashedHashes.contains(hash),
    mediaId: null,
    title: titles[hash],
    trashed: trashedHashes.contains(hash),
  ));

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required UploadSource source,
    required int length,
    required String mediaType,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    uploadedTypes.add(mediaType);
    return Right(UploadResult(jobId: source.path.hashCode));
  }

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

/// Уведомление, которое умеет падать: плагин падает на живых платформах
/// (нет демона уведомлений, отозванное разрешение), и пачка обязана
/// доехать и выйти из isRunning.
class _FakeNotifications extends UploadNotifications {
  new() : super(channelId: 'test');

  bool throwOnShow = false;
  bool throwOnClear = false;
  int shows = 0;
  int clears = 0;

  @override
  Future<void> showProgress({
    required int done,
    required int total,
    double? progress,
  }) async {
    if (throwOnShow) throw StateError('plugin boom');
    shows++;
  }

  @override
  Future<void> clear() async {
    if (throwOnClear) throw StateError('plugin boom');
    clears++;
  }
}

BatchUploadItem _item(String name) =>
    BatchUploadItem(source: fakeUploadSource(name: name), fileSize: 1024);

/// Статус «загружено, медиа создано» с id 42.
const _doneWithMedia = UploadStatus(
  id: 1,
  status: 'done',
  media: Media(id: 42, title: 'File', type: MediaType.video, fileSize: 1024),
);

void main() {
  late _FakeRepository repo;
  late FakeCollectionsRepository collections;
  late _FakeNotifications notifications;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepository();
    collections = FakeCollectionsRepository()
      ..onAddItem = (collectionId, mediaId) async => Right(
        CollectionItem(id: 1, collectionId: collectionId, mediaId: mediaId),
      );
    notifications = _FakeNotifications();
    container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(repo),
        collectionsRepositoryProvider.overrideWithValue(collections),
        uploadNotificationsProvider.overrideWithValue(notifications),
      ],
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

  test('файл кладётся в выбранную коллекцию', () async {
    // Экран загрузки может закрыться посреди пачки: добавление живёт в
    // контроллере, поэтому id коллекции приходит из пачки, а не из UI.
    repo.statusResult = _doneWithMedia;

    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-of-${source.path}';
    batch().setFiles([_item('a.mp4')]);
    final summary = await batch().startAll(mediaType: 'video', collectionId: 7);

    expect(summary.items.single.status, BatchItemStatus.done);
    expect(collections.addItemCalls, [(7, 42)]);
    expect(batch().collectionFailures, 0);
  });

  test('сбой добавления в коллекцию не валит загрузку', () async {
    // Файл уже на сервере: ошибка побочного действия — не ошибка
    // загрузки, иначе успешно залитое помечалось бы failed.
    repo.statusResult = _doneWithMedia;
    collections.onAddItem = (_, _) async => throw Exception('collection boom');

    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-of-${source.path}';
    batch().setFiles([_item('a.mp4')]);
    final summary = await batch().startAll(mediaType: 'video', collectionId: 7);

    expect(summary.items.single.status, BatchItemStatus.done);
    expect(batch().collectionFailures, 1);
  });

  test('уведомление показывает прогресс и убирается после пачки', () async {
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-of-${source.path}';
    batch().setFiles([_item('a.mp4')]);
    await batch().startAll(mediaType: 'video');

    expect(notifications.shows, greaterThan(0));
    expect(notifications.clears, 1);
  });

  test('сбой уведомления не оставляет пачку в isRunning', () async {
    // Плагин может бросить и на показе, и на очистке: пачка обязана
    // сбросить isRunning, иначе экран залипнет до перезапуска.
    notifications
      ..throwOnShow = true
      ..throwOnClear = true;
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-of-${source.path}';
    batch().setFiles([_item('a.mp4')]);
    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.isRunning, isFalse);
    expect(summary.items.single.status, BatchItemStatus.done);
  });

  test('пачка: успех + дубликат + продолжение после дубликата', () async {
    // Хэшер детерминированный: хэш = путь (дубликат = тот же путь).
    batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-of-${source.path}';
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
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, isCancelled) async {
      if (source.path.endsWith('a.mp4')) {
        batch().cancelAll();
        await Future<void>.delayed(Duration.zero);
      }
      return 'hash-${source.path}';
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
    container.read(uploadControllerProvider.notifier).hasher = (
      path,
      _,
    ) async => throw Exception('hash boom');

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.doneCount, 0);
    expect(summary.failedCount, 2);
  });

  test('хэш из корзины — failed с намёком, а не дубликат', () async {
    batch().setFiles([_item('a.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-${source.path}';
    repo.trashedHashes = {'hash-/tmp/a.mp4'};

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.doneCount, 0);
    expect(summary.duplicateCount, 0);
    expect(summary.failedCount, 1);
    expect(summary.items.single.errorMessage, contains('trash'));
  });

  test('retryFailed перепроганяет только упавшие', () async {
    batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
    var failA = true;
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, _) async {
      if (failA && source.path.endsWith('a.mp4')) throw Exception('hash boom');
      return 'hash-${source.path}';
    };

    final first = await batch().startAll(mediaType: 'video');
    expect(first.failedCount, 1);
    expect(first.doneCount, 1);

    failA = false;
    final second = await batch().retryFailed(collectionId: null);
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
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, _) async {
      // Пока первый файл в работе — подмена списка запрещена.
      batch().setFiles([_item('x.mp4')]);
      return 'hash-${source.path}';
    };

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.items.map((i) => i.source.name), ['a.mp4']);
  });

  test('пустой startAll возвращает покой без работы', () async {
    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.isRunning, false);
    expect(summary.items, isEmpty);
  });

  test('хэшер вызван один раз на файл (knownHash без перехэша)', () async {
    batch().setFiles([_item('a.mp4'), _item('b.mp4'), _item('c.mp4')]);
    final calls = <String, int>{};
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, _) async {
      calls[source.path] = (calls[source.path] ?? 0) + 1;
      return 'hash-${source.path}';
    };

    await batch().startAll(mediaType: 'video');

    // Пул посчитал + заливка переиспользовала: ровно по разу.
    expect(calls, {'/tmp/a.mp4': 1, '/tmp/b.mp4': 1, '/tmp/c.mp4': 1});
  });

  test('дубликат несёт название совпавшего', () async {
    batch().setFiles([_item('a.mp4')]);
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-${source.path}';
    repo
      ..existingHashes = {'hash-/tmp/a.mp4'}
      ..titles = {'hash-/tmp/a.mp4': 'S01E02 Название'};

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.duplicateCount, 1);
    expect(summary.items.single.existingTitle, 'S01E02 Название');
  });

  test('хэширование идёт пулом с честным прогрессом', () async {
    batch().setFiles([for (var i = 0; i < 6; i++) _item('f$i.mp4')]);
    final gate = Completer<void>();
    var active = 0;
    var maxActive = 0;
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, isCancelled) async {
      active++;
      if (active > maxActive) maxActive = active;
      try {
        await gate.future;
        return 'hash-${source.path}';
      } finally {
        active--;
      }
    };

    final running = batch().startAll(mediaType: 'video');
    // Ждём входа в фазу хэширования (пул упёрся в гейт).
    for (var i = 0; i < 100; i++) {
      final s = container.read(batchUploadControllerProvider);
      if (s.hashingTotal == 6) break;
      await Future<void>.delayed(Duration.zero);
    }
    final hashing = container.read(batchUploadControllerProvider);
    expect(hashing.hashingTotal, 6);
    expect(hashing.hashingDone, lessThan(6));
    gate.complete();
    final summary = await running;

    // Параллельно, но не wider пула.
    expect(maxActive, greaterThan(1));
    expect(maxActive, lessThanOrEqualTo(3));
    expect(summary.doneCount, 6);
  });

  test('sizesPending: старт запрещён, updateSizes снимает флаг', () {
    batch().setFiles([
      BatchUploadItem(source: fakeUploadSource(name: 'a.mp4'), fileSize: 0),
    ], sizesPending: true);

    var state = container.read(batchUploadControllerProvider);
    expect(state.sizesPending, isTrue, reason: '0 = не измерено');
    expect(state.items.single.fileSize, 0);

    batch().updateSizes({'/tmp/a.mp4': 2048});

    state = container.read(batchUploadControllerProvider);
    expect(state.sizesPending, isFalse, reason: 'размеры пришли');
    expect(state.items.single.fileSize, 2048);
  });

  test('updateSizes не трогает файлы вне карты', () {
    batch().setFiles([
      BatchUploadItem(source: fakeUploadSource(name: 'a.mp4'), fileSize: 0),
      BatchUploadItem(source: fakeUploadSource(name: 'b.mp4'), fileSize: 0),
    ], sizesPending: true);

    batch().updateSizes({'/tmp/a.mp4': 100});

    final items = container.read(batchUploadControllerProvider).items;
    expect(items[0].fileSize, 100);
    expect(items[1].fileSize, 0);
  });

  test('пустой файл (0 после замеров) честно падает backstopом', () async {
    // После updateSizes 0 означает реальный пустой файл: старт разрешён,
    // контроллер валит его своим backstop-сообщением, а не молча.
    batch().setFiles([
      BatchUploadItem(source: fakeUploadSource(name: 'empty.mp4'), fileSize: 0),
    ], sizesPending: true);
    batch().updateSizes({'/tmp/empty.mp4': 0});

    final summary = await batch().startAll(mediaType: 'video');

    expect(summary.failedCount, 1);
    expect(summary.items.single.errorMessage, contains('empty'));
  });

  test('retryFailed работает вместе с пулом хэшей', () async {
    batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
    var failFirst = true;
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, _) async {
      if (failFirst && source.path.endsWith('a.mp4')) {
        throw Exception('hash boom');
      }
      return 'hash-${source.path}';
    };

    final first = await batch().startAll(mediaType: 'video');
    expect(first.failedCount, 1);
    expect(first.doneCount, 1);

    failFirst = false;
    final second = await batch().retryFailed(collectionId: null);
    expect(second.failedCount, 0);
    expect(second.doneCount, 2);
  });

  test('retryFailed берёт тип у прошлой пачки, а не у экрана', () async {
    // Пачка общая для аудио и видео: экран мог быть открыт с другой
    // вкладки, и присланный им тип отправил бы аудио-файлы как видео.
    batch().setFiles([_item('a.mp3'), _item('b.mp3')]);
    var failFirst = true;
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, _) async {
      if (failFirst && source.path.endsWith('a.mp3')) {
        throw Exception('hash boom');
      }
      return 'hash-${source.path}';
    };

    final first = await batch().startAll(mediaType: 'audio');
    expect(first.failedCount, 1);

    failFirst = false;
    repo.uploadedTypes.clear();
    final second = await batch().retryFailed(collectionId: null);

    expect(second.failedCount, 0);
    expect(repo.uploadedTypes, ['audio']);
  });

  test('startAll без pending не меняет тип и коллекцию пачки', () async {
    // Видео-экран мог нажать «Загрузить» по чужой завершённой аудио-пачке:
    // pending-файлов нет, и прогон не должен переписывать её тип с
    // коллекцией — иначе повтор ушёл бы на сервер чужими.
    repo.statusResult = _doneWithMedia;
    batch().setFiles([_item('a.mp3'), _item('b.mp3')]);
    var failB = true;
    container
        .read(uploadControllerProvider.notifier)
        .hasher = (source, _) async {
      if (failB && source.path.endsWith('b.mp3')) throw Exception('hash boom');
      return 'hash-${source.path}';
    };

    final first = await batch().startAll(mediaType: 'audio', collectionId: 7);
    expect(first.failedCount, 1);
    expect(collections.addItemCalls, [(7, 42)]);

    // Чужой экран жмёт «Загрузить»: грузить нечего, пачка не меняется.
    final noop = await batch().startAll(mediaType: 'video', collectionId: 9);
    expect(noop.failedCount, 1);
    expect(batch().mediaType, 'audio');

    failB = false;
    repo.uploadedTypes.clear();
    collections.addItemCalls.clear();
    final second = await batch().retryFailed(collectionId: 7);

    expect(second.failedCount, 0);
    expect(repo.uploadedTypes, ['audio']);
    expect(collections.addItemCalls, [(7, 42)]);
  });

  test(
    'retryFailed берёт коллекцию, выбранную на экране после пачки',
    () async {
      // Коллекцию можно сменить, когда пачка уже закончилась: повтор обязан
      // уйти в ту, что видит пользователь, а не в старую из прошлого прогона.
      repo.statusResult = _doneWithMedia;
      batch().setFiles([_item('a.mp4'), _item('b.mp4')]);
      var failB = true;
      container
          .read(uploadControllerProvider.notifier)
          .hasher = (source, _) async {
        if (failB && source.path.endsWith('b.mp4')) {
          throw Exception('hash boom');
        }
        return 'hash-${source.path}';
      };

      final first = await batch().startAll(mediaType: 'video', collectionId: 7);
      expect(first.failedCount, 1);
      expect(collections.addItemCalls, [(7, 42)]);

      failB = false;
      collections.addItemCalls.clear();
      final second = await batch().retryFailed(collectionId: 8);

      expect(second.failedCount, 0);
      expect(collections.addItemCalls, [(8, 42)]);
    },
  );

  test('clear сбрасывает тип пачки вместе с файлами', () async {
    // Вход на экран загрузки сбрасывает пачку: вместе с файлами должен
    // уйти и тип, иначе экран другого типа выберет коллекцию по типу
    // уже стёртой пачки.
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-${source.path}';
    batch().setFiles([_item('a.mp3')]);
    await batch().startAll(mediaType: 'audio');
    expect(batch().mediaType, 'audio');

    batch().clear();

    expect(batch().mediaType, isNull);
    expect(batch().state.items, isEmpty);
  });

  test('setFiles забывает тип прошлой пачки', () async {
    // Новый набор — новая пачка: сброс при входе на экран не срабатывает,
    // если чужая пачка ещё идёт, поэтому тип должен уходить и здесь.
    container.read(uploadControllerProvider.notifier).hasher = (
      source,
      _,
    ) async => 'hash-${source.path}';
    batch().setFiles([_item('a.mp3')]);
    await batch().startAll(mediaType: 'audio');

    batch().setFiles([_item('b.mp4')]);

    expect(batch().mediaType, isNull);
  });
}
