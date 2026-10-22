import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/models/upload_result.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/upload_controller.dart';
import 'package:fpdart/fpdart.dart';

class _FakeRepository implements MediaRepository {
  bool hashExists = false;
  bool hashTrashed = false;
  int uploadJobId = 1;
  UploadStatus? statusResult;
  Failure? statusFailure;
  Failure? uploadFailure;
  int? cancelledJobId;
  int pollCount = 0;

  /// Чанки прогресса, которые отдаёт фейковый upload (sent при total 100).
  List<int> progressChunks = const [];

  @override
  Future<Either<Failure, ({bool exists, int? mediaId, String? title, bool trashed})>>
  checkHash(String hash) async => Right((
    exists: hashExists || hashTrashed,
    mediaId: null,
    title: null,
    trashed: hashTrashed,
  ));

  @override
  Future<Either<Failure, UploadResult>> uploadFile({
    required String filePath,
    required String mediaType,
    required String fileName,
    void Function(int sent, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (uploadFailure != null) return Left(uploadFailure!);
    for (final sent in progressChunks) {
      onProgress?.call(sent, 100);
    }
    return Right(UploadResult(jobId: uploadJobId));
  }

  @override
  Future<Either<Failure, UploadStatus>> getUploadStatus(int jobId) async {
    pollCount++;
    if (statusFailure != null) return Left(statusFailure!);
    if (statusResult != null) return Right(statusResult!);
    // По умолчанию — queued, продолжаем опрос.
    return Right(UploadStatus(id: jobId, status: 'queued'));
  }

  @override
  Future<Either<Failure, void>> cancelUpload(int jobId) async {
    cancelledJobId = jobId;
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRepository repo;
  late ProviderContainer container;
  late List<String> successCalls;

  setUp(() {
    repo = _FakeRepository();
    successCalls = [];
    container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    // autoDispose-провайдер живёт только пока его слушают: без подписки
    // долгие poll-паузы пережили бы dispose и тесты стали бы flaky.
    final keepAlive = container.listen<UploadState>(
      uploadControllerProvider,
      (_, _) {},
    );
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });
  });

  UploadController makeController() {
    return container.read(uploadControllerProvider.notifier)
      ..hasher = (_, _) async => 'hash-1';
  }

  Future<bool> start(UploadController controller) {
    return controller.start(
      filePath: '/tmp/file.mp3',
      mediaType: 'audio',
      fileName: 'file.mp3',
      fileSize: 100,
      onSuccess: (_) async => successCalls.add('ok'),
    );
  }

  test('успешная загрузка: hash → check → upload → poll → success', () async {
    repo.statusResult = const UploadStatus(id: 1, status: 'done');

    final started = await start(makeController());

    expect(started, isTrue);
    expect(successCalls, ['ok']);
    expect(repo.pollCount, 1);
  });

  test('дубликат: checkHash=true → без upload и без errorMessage', () async {
    repo.hashExists = true;

    final started = await start(makeController());

    expect(started, isFalse);
    expect(successCalls, isEmpty);
    expect(repo.pollCount, 0);
    // Нет ошибки — экран покажет «файл уже существует», а не сбой.
    expect(
      container.read(uploadControllerProvider).errorMessage,
      isNull,
    );
  });

  test('trashed-хэш: false с errorMessage-намёком, а не дубликат', () async {
    repo.hashTrashed = true;

    final started = await start(makeController());

    expect(started, isFalse);
    expect(successCalls, isEmpty);
    expect(repo.pollCount, 0);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      contains('trash'),
    );
  });

  test('пустой файл: false с errorMessage, а не молча', () async {
    final started = await makeController().start(
      filePath: '/tmp/empty.mp3',
      mediaType: 'audio',
      fileName: 'empty.mp3',
      fileSize: 0,
      onSuccess: (_) async => successCalls.add('ok'),
    );
    expect(started, isFalse);
    expect(successCalls, isEmpty);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      isNotNull,
    );
  });

  test('файл больше лимита: false с errorMessage, а не молча', () async {
    final started = await makeController().start(
      filePath: '/tmp/big.mp3',
      mediaType: 'video',
      fileName: 'big.mp3',
      fileSize: 3 * 1024 * 1024 * 1024,
      onSuccess: (_) async => successCalls.add('ok'),
    );
    expect(started, isFalse);
    expect(successCalls, isEmpty);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      isNotNull,
    );
  });

  test('null fileName: false с errorMessage, а не краш на !', () async {
    final started = await makeController().start(
      filePath: '/tmp/file.mp3',
      mediaType: 'audio',
      fileName: null,
      fileSize: 100,
      onSuccess: (_) async => successCalls.add('ok'),
    );
    expect(started, isFalse);
    expect(successCalls, isEmpty);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      isNotNull,
    );
  });

  test('ошибка upload возвращает false с errorMessage', () async {
    repo.uploadFailure = const ServerFailure(message: 'network down');

    final started = await start(makeController());

    expect(started, isFalse);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      'network down',
    );
  });

  test('ошибка статуса после 3 попыток: errorMessage из failure', () async {
    repo.statusFailure = const ServerFailure(message: 'status boom');

    final started = await start(makeController());

    expect(started, isFalse);
    expect(repo.pollCount, 3);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      'status boom',
    );
  });

  test('ошибка обработки сервера: errorMessage из status.error', () async {
    // Регрессия: раньше сообщение терялось (poll возвращал голый bool),
    // и экран показывал «файл уже существует» вместо ошибки ffmpeg.
    repo.statusResult = const UploadStatus(
      id: 1,
      status: 'error',
      error: 'ffmpeg failed',
    );

    final started = await start(makeController());

    expect(started, isFalse);
    expect(
      container.read(uploadControllerProvider).errorMessage,
      'ffmpeg failed',
    );
  });

  test('ошибка обработки без текста: fallback вместо молчания', () async {
    repo.statusResult = const UploadStatus(id: 1, status: 'error');

    final started = await start(makeController());

    expect(started, isFalse);
    // Не null — иначе экран снова показал бы «дубликат».
    expect(
      container.read(uploadControllerProvider).errorMessage,
      isNotNull,
    );
  });

  test('отмена хэшера (null) трактуется как отмена загрузки', () async {
    final controller = container.read(uploadControllerProvider.notifier)
      ..hasher = (_, _) async => null;

    final started = await controller.start(
      filePath: '/tmp/file.mp3',
      mediaType: 'audio',
      fileName: 'file.mp3',
      fileSize: 100,
      onSuccess: (_) async => successCalls.add('ok'),
    );

    expect(started, isFalse);
    expect(successCalls, isEmpty);
    expect(container.read(uploadControllerProvider).cancelled, isTrue);
    // Не дубликат и не молчаливый сбой: флаг отмены выставлен.
    expect(
      container.read(uploadControllerProvider).errorMessage,
      isNull,
    );
  });

  test('отмена во время poll отменяет джоб на сервере', () async {
    // Первый poll — queued, затем отмена.
    repo
      ..uploadJobId = 42
      ..statusResult = const UploadStatus(id: 42, status: 'queued');
    final controller = makeController();

    final future = start(controller);
    // Даём отработать upload + первый poll.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controller.cancel();
    final started = await future;

    expect(started, isFalse);
    expect(repo.cancelledJobId, 42);
    expect(container.read(uploadControllerProvider).cancelled, isTrue);
  });

  test('отмена во время POST не трогает чужие джобы', () async {
    // Регрессия: раньше отменялся _lastJobId — на повторной загрузке это
    // был бы id уже завершённого чужого джоба (лишний DELETE).
    repo
      ..uploadJobId = 7
      ..statusResult = const UploadStatus(id: 7, status: 'done');
    final controller = makeController();

    // Первая загрузка успешна — состояние джоба 7 нигде не сохраняется.
    expect(await start(controller), isTrue);

    // Вторая: отмена во время POST (upload видит флаг и фейлит отменой).
    repo.uploadFailure = const UploadCancelledFailure();
    final started = await start(controller);

    expect(started, isFalse);
    expect(repo.cancelledJobId, isNull);
  });

  test('троттлинг прогресса: первый и финальный чанки проходят', () async {
    repo
      ..progressChunks = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
      ..statusResult = const UploadStatus(id: 1, status: 'done');
    final controller = makeController();
    final sentValues = <int>[];
    container.listen<UploadState>(uploadControllerProvider, (_, next) {
      if (next.sentBytes != null) sentValues.add(next.sentBytes!);
    });

    expect(await start(controller), isTrue);

    // Синхронная пачка в пределах одного тика: первый чанк проходит
    // (метка эпохи), середина съедается троттлингом, финал — всегда.
    expect(sentValues.first, 10);
    expect(sentValues.last, 100);
    expect(sentValues.length, lessThan(10));
    // После завершения прогресс сброшен.
    expect(container.read(uploadControllerProvider).progress, isNull);
  });

  test('фаза переключается hashing → checking → uploading → processing',
      () async {
    repo.statusResult = const UploadStatus(id: 1, status: 'done');
    final controller = makeController();
    final phases = <UploadPhase?>[];

    // Подписываемся на изменения фазы.
    container.listen(uploadControllerProvider, (prev, next) {
      if (next.phase != null) phases.add(next.phase);
    }, fireImmediately: true);

    await start(controller);

    expect(
      phases,
      containsAll([
        UploadPhase.hashing,
        UploadPhase.checking,
        UploadPhase.uploading,
        UploadPhase.processing,
      ]),
    );
  });

  group('UploadState.progress', () {
    test('кламп сверху и ноль при неизвестном total', () {
      expect(
        const UploadState(sentBytes: 150, totalBytes: 100).progress,
        1.0,
      );
      expect(const UploadState(sentBytes: 10).progress, isNull);
      expect(const UploadState(sentBytes: 50, totalBytes: 100).progress, 0.5);
    });
  });
}
