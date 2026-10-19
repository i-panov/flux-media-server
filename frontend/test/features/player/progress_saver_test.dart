import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/player/data/progress_saver.dart';
import 'package:flux_media_server/features/player/data/resume_policy.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:fpdart/fpdart.dart';

class _FakeRepository implements MediaRepository {
  /// (mediaId, position, duration, completed) в порядке вызовов.
  /// completed всегда не-null: как и настоящий репозиторий, подставляем
  /// false вместо null, чтобы сравнение записей было точным.
  final List<({int mediaId, int position, int duration, bool completed})>
  updates = [];

  List<WatchProgress> storedProgress = [];

  /// Поштучные записи для getProgressById (новый путь loadSavedPosition).
  final Map<int, WatchProgress> storedById = {};
  Failure? progressByIdFailure;
  int updateCalls = 0;
  bool failUpdates = false;

  @override
  Future<Either<Failure, WatchProgress>> updateProgress(
    int mediaId, {
    int? position,
    int? duration,
    bool? completed,
  }) async {
    updateCalls++;
    updates.add((
      mediaId: mediaId,
      position: position ?? 0,
      duration: duration ?? 0,
      completed: completed ?? false,
    ));
    if (failUpdates) {
      return const Left(ServerFailure(message: 'boom'));
    }
    return Right(
      WatchProgress(
        userId: 1,
        mediaId: mediaId,
        position: position ?? 0,
        duration: duration ?? 0,
        completed: completed ?? false,
      ),
    );
  }

  @override
  Future<Either<Failure, List<WatchProgress>>> getProgress() async =>
      Right(storedProgress);

  @override
  Future<Either<Failure, WatchProgress?>> getProgressById(int mediaId) async {
    final failure = progressByIdFailure;
    if (failure != null) return Left(failure);
    return Right(storedById[mediaId]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ProgressSaver.save', () {
    test('сохраняет позицию и длительность в секундах', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(repository: repo);

      await saver.save(
        7,
        const Duration(seconds: 42),
        const Duration(minutes: 10),
      );

      expect(repo.updates, [
        (mediaId: 7, position: 42, duration: 600, completed: false),
      ]);
    });

    test('нулевая позиция не уходит в сеть', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(repository: repo);

      await saver.save(7, Duration.zero, const Duration(minutes: 10));

      expect(repo.updateCalls, 0);
    });

    test('параллельные сохранения сериализуются по порядку', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(repository: repo);

      await Future.wait([
        saver.save(7, const Duration(seconds: 1), Duration.zero),
        saver.save(7, const Duration(seconds: 2), Duration.zero),
        saver.save(
          7,
          const Duration(seconds: 3),
          Duration.zero,
          completed: true,
        ),
      ]);

      expect(
        [for (final u in repo.updates) u.position],
        [1, 2, 3],
      );
    });

    test('ошибка сети глотается, цепочка не блокируется', () async {
      final repo = _FakeRepository()..failUpdates = true;
      final saver = ProgressSaver(repository: repo);

      // Не бросает — best-effort.
      await saver.save(7, const Duration(seconds: 1), Duration.zero);
      await saver.save(7, const Duration(seconds: 2), Duration.zero);

      expect(repo.updateCalls, 2);
    });
  });

  group('ProgressSaver.startAutoSave', () {
    test('тики дёргают снимок и сохраняют его', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(
        repository: repo,
        saveInterval: const Duration(milliseconds: 20),
      );
      addTearDown(saver.stopAutoSave);

      saver.startAutoSave(
        () => (
          mediaId: 7,
          position: const Duration(seconds: 5),
          duration: const Duration(minutes: 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(repo.updateCalls, greaterThanOrEqualTo(2));
      expect(repo.updates.first.mediaId, 7);
    });

    test('null-снимок пропускается', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(
        repository: repo,
        saveInterval: const Duration(milliseconds: 20),
      );
      addTearDown(saver.stopAutoSave);

      saver.startAutoSave(() => null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.updateCalls, 0);
    });

    test('stopAutoSave останавливает тики', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(
        repository: repo,
        saveInterval: const Duration(milliseconds: 20),
      )..startAutoSave(
        () => (
          mediaId: 7,
          position: const Duration(seconds: 5),
          duration: Duration.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      saver.stopAutoSave();
      final calls = repo.updateCalls;
      expect(calls, greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repo.updateCalls, calls);
    });

    test('повторный старт гасит предыдущий таймер', () async {
      final repo = _FakeRepository();
      final saver = ProgressSaver(
        repository: repo,
        saveInterval: const Duration(milliseconds: 20),
      );
      addTearDown(saver.stopAutoSave);

      var id = 1;
      saver.startAutoSave(
        () => (
          mediaId: id,
          position: const Duration(seconds: 1),
          duration: Duration.zero,
        ),
      );
      id = 2;
      saver.startAutoSave(
        () => (
          mediaId: id,
          position: const Duration(seconds: 1),
          duration: Duration.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Жив только второй таймер: все сохранения — для id 2.
      expect(repo.updates, isNotEmpty);
      expect(
        repo.updates.every((u) => u.mediaId == 2),
        isTrue,
      );
    });
  });

  group('ResumePolicy.target', () {
    test('null — начинать с нуля', () {
      expect(ResumePolicy.target(null), isNull);
    });

    test('позиция не выше порога — перемотка бессмысленна', () {
      expect(ResumePolicy.target(const Duration(seconds: 5)), isNull);
      expect(ResumePolicy.target(const Duration(seconds: 3)), isNull);
      expect(ResumePolicy.target(Duration.zero), isNull);
    });

    test('позиция выше порога — продолжаем с неё, без кнопок', () {
      // Раньше здесь появлялась кнопка «Продолжить с …» в автоскрывающихся
      // контролах: её то видели, то нет, а видео стартовало с нуля.
      expect(
        ResumePolicy.target(const Duration(seconds: 6)),
        const Duration(seconds: 6),
      );
      expect(
        ResumePolicy.target(const Duration(seconds: 7200)),
        const Duration(seconds: 7200),
      );
    });
  });

  group('ResumePolicy.loadSavedPosition', () {
    test('возвращает позицию для нужного mediaId', () async {
      final repo = _FakeRepository()
        ..storedById[9] = const WatchProgress(
          userId: 1,
          mediaId: 9,
          position: 42,
          duration: 100,
        );
      final policy = ResumePolicy(repository: repo);

      expect(
        await policy.loadSavedPosition(9),
        const Duration(seconds: 42),
      );
    });

    test('null при отсутствии записи и при нулевой позиции', () async {
      final repo = _FakeRepository()
        ..storedById[9] = const WatchProgress(
          userId: 1,
          mediaId: 9,
          position: 0,
        );
      final policy = ResumePolicy(repository: repo);

      expect(await policy.loadSavedPosition(9), isNull);
      expect(await policy.loadSavedPosition(404), isNull);
    });

    test('досмотренное видео — null, а не прыжок в последнюю секунду', () async {
      // Регрессия: флаг completed не проверялся, хотя был задокументирован
      // в докстринге метода.
      final repo = _FakeRepository()
        ..storedById[9] = const WatchProgress(
          userId: 1,
          mediaId: 9,
          position: 3599,
          duration: 3600,
          completed: true,
        );
      final policy = ResumePolicy(repository: repo);

      expect(await policy.loadSavedPosition(9), isNull);
    });

    test('ошибка сети превращается в null, а не в исключение', () async {
      final repo = _FakeRepository()
        ..progressByIdFailure = const ServerFailure(message: 'boom');
      final policy = ResumePolicy(repository: repo);

      expect(await policy.loadSavedPosition(9), isNull);
    });
  });
}
