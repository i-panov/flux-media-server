import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/video/presentation/providers/extracted_audio_provider.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

Media _track(int id) => Media(
  id: id,
  title: 'Track $id',
  type: MediaType.audio,
  fileSize: 100,
);

class _FakeRepository implements MediaRepository {
  Media? linked;
  Failure? failure;

  @override
  Future<Either<Failure, Media?>> getExtractedAudio(int mediaId) async {
    if (failure != null) return Left(failure!);
    return Right(linked);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepository();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  test('возвращает связанный трек', () async {
    repo.linked = _track(9);

    final media = await container.read(extractedAudioProvider(7).future);

    expect(media?.id, 9);
  });

  test('без связки — null, а не ошибка', () async {
    final media = await container.read(extractedAudioProvider(7).future);

    expect(media, isNull);
  });

  test('сбой сети — AsyncError', () async {
    repo.failure = const ServerFailure(message: 'boom');

    await expectLater(
      container.read(extractedAudioProvider(7).future),
      throwsA(isA<ServerFailure>()),
    );
  });
}
