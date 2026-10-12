import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/models/upload_status.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/extract_controller.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

Media _track(int id) => Media(
  id: id,
  title: 'Track $id',
  type: MediaType.audio,
  fileSize: 100,
);

class _FakeRepository implements MediaRepository {
  /// Сценарий POST: готовый трек (связка есть) или jobId.
  Media? linkedMedia;
  int extractJobId = 1;
  Failure? extractFailure;
  int extractAudioCalls = 0;

  /// Кривой ответ сервера: ни jobId, ни media.
  bool returnEmptyResult = false;

  UploadStatus? statusResult;
  Failure? statusFailure;
  int? cancelledJobId;
  int pollCount = 0;

  @override
  Future<Either<Failure, ({int? jobId, Media? media})>> extractAudio(
    int mediaId, {
    bool Function()? isCancelled,
  }) async {
    extractAudioCalls++;
    if (extractFailure != null) return Left(extractFailure!);
    if (returnEmptyResult) return const Right((jobId: null, media: null));
    if (linkedMedia != null) return Right((jobId: null, media: linkedMedia));
    return Right((jobId: extractJobId, media: null));
  }

  @override
  Future<Either<Failure, UploadStatus>> getExtractStatus(
    int jobId, {
    bool Function()? isCancelled,
  }) async {
    pollCount++;
    if (statusFailure != null) return Left(statusFailure!);
    if (statusResult != null) return Right(statusResult!);
    return Right(UploadStatus(id: jobId, status: 'queued'));
  }

  @override
  Future<Either<Failure, void>> cancelExtract(
    int jobId, {
    bool Function()? isCancelled,
  }) async {
    cancelledJobId = jobId;
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRepository repo;
  late ProviderContainer container;
  late List<Media> successCalls;

  setUp(() {
    repo = _FakeRepository();
    successCalls = [];
    container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    // autoDispose-провайдер живёт только пока его слушают.
    final keepAlive = container.listen(extractControllerProvider, (_, _) {});
    addTearDown(() {
      keepAlive.close();
      container.dispose();
    });
  });

  ExtractController makeController() =>
      container.read(extractControllerProvider.notifier);

  Future<Media?> start(ExtractController controller) async {
    final track = await controller.start(mediaId: 7);
    if (track != null) successCalls.add(track);
    return track;
  }

  test('связка есть: сразу готовый трек без опроса', () async {
    repo.linkedMedia = _track(9);

    final track = await start(makeController());

    expect(track?.id, 9);
    expect(successCalls.map((m) => m.id), [9]);
    expect(repo.pollCount, 0);
  });

  test('джоб: опрос до done возвращает трек', () async {
    repo.statusResult = UploadStatus(
      id: 1,
      status: 'done',
      media: _track(11),
    );

    final track = await start(makeController());

    expect(track?.id, 11);
    expect(successCalls.map((m) => m.id), [11]);
    expect(repo.pollCount, 1);
  });

  test('ошибка обработки: errorMessage из статуса', () async {
    repo.statusResult = const UploadStatus(
      id: 1,
      status: 'error',
      error: 'ffmpeg failed',
    );

    final track = await start(makeController());

    expect(track, isNull);
    expect(successCalls, isEmpty);
    expect(
      container.read(extractControllerProvider).errorMessage,
      'ffmpeg failed',
    );
  });

  test('done без media: ошибка, а не молчание', () async {
    repo.statusResult = const UploadStatus(id: 1, status: 'done');

    final track = await start(makeController());

    expect(track, isNull);
    expect(
      container.read(extractControllerProvider).errorMessage,
      isNotNull,
    );
  });

  test('исчерпание опросов: errorMessage из failure', () async {
    repo.statusFailure = const ServerFailure(message: 'status boom');

    final track = await start(makeController());

    expect(track, isNull);
    expect(repo.pollCount, 3);
    expect(
      container.read(extractControllerProvider).errorMessage,
      'status boom',
    );
  });

  test('ошибка POST: false-path с errorMessage', () async {
    repo.extractFailure = const ServerFailure(message: 'no audio stream');

    final track = await start(makeController());

    expect(track, isNull);
    expect(
      container.read(extractControllerProvider).errorMessage,
      'no audio stream',
    );
  });

  test('jobId==null && media==null: ошибка вместо зависания', () async {
    repo.returnEmptyResult = true;

    final track = await start(makeController());

    expect(track, isNull);
    expect(successCalls, isEmpty);
    expect(
      container.read(extractControllerProvider).errorMessage,
      isNotNull,
    );
  });

  test('ошибка сбрасывается при успешном рестарте', () async {
    repo.extractFailure = const ServerFailure(message: 'boom');
    final controller = makeController();

    expect(await start(controller), isNull);
    expect(
      container.read(extractControllerProvider).errorMessage,
      'boom',
    );

    repo
      ..extractFailure = null
      ..linkedMedia = _track(5);

    final track = await start(controller);

    expect(track?.id, 5);
    expect(container.read(extractControllerProvider).errorMessage, isNull);
    expect(container.read(extractControllerProvider).cancelled, isFalse);
  });

  test('двойной start: один POST, оба future с тем же результатом', () async {
    repo.statusResult = UploadStatus(
      id: 1,
      status: 'done',
      media: _track(11),
    );
    final controller = makeController();

    final first = controller.start(mediaId: 7);
    final second = controller.start(mediaId: 7);

    final results = await Future.wait([first, second]);
    // Один джоб на двоих: второй вызов присоединился, а не создал новый.
    expect(repo.extractAudioCalls, 1);
    expect(repo.pollCount, 1);
    expect(results.map((m) => m?.id), [11, 11]);
  });

  test('UploadCancelledFailure в poll: done=false с фолбэк-ошибкой', () async {
    // Ветка жива благодаря пробросу isCancelled: сбой приходит без
    // взведённого флага (иначе вышли бы раньше через break), lastError
    // пуст — срабатывает фолбэк вместо null.
    repo.statusFailure = const UploadCancelledFailure();

    final track = await start(makeController());

    expect(track, isNull);
    expect(
      container.read(extractControllerProvider).errorMessage,
      'Audio extraction failed',
    );
    expect(container.read(extractControllerProvider).cancelled, isFalse);
  });

  test('отмена во время poll отменяет джоб на сервере', () async {
    repo
      ..extractJobId = 42
      ..statusResult = const UploadStatus(id: 42, status: 'queued');
    final controller = makeController();

    final future = start(controller);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controller.cancel();
    final track = await future;

    expect(track, isNull);
    expect(repo.cancelledJobId, 42);
    final state = container.read(extractControllerProvider);
    expect(state.cancelled, isTrue);
    // Отмена — не ошибка: errorMessage пуст, cancelled отличает исход.
    expect(state.errorMessage, isNull);
  });
}
