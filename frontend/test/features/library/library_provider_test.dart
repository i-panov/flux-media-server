import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';
import 'package:flux_media_server/shared/models/library.dart';

MediaLibrary _fakeLibrary(int id, [String? name]) => MediaLibrary(
      id: id,
      name: name ?? 'Library $id',
      path: '/media/$id',
      type: 'movie',
      enabled: true,
    );

class FakeLibraryRepository implements LibraryRepository {
  Future<Either<Failure, List<MediaLibrary>>> Function()? onGetLibraries;
  Future<Either<Failure, MediaLibrary>> Function(int)? onScanLibrary;

  @override
  Future<Either<Failure, List<MediaLibrary>>> getLibraries() =>
      onGetLibraries!();

  @override
  Future<Either<Failure, MediaLibrary>> scanLibrary(int id) =>
      onScanLibrary!(id);
}

void main() {
  late LibraryNotifier notifier;
  late FakeLibraryRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeLibraryRepository();
    notifier = LibraryNotifier(repository: fakeRepo);
  });

  tearDown(() => notifier.dispose());

  test('initial state is loading', () {
    expect(notifier.state, isA<LibraryLoading>());
  });

  test('load emits loaded with libraries', () async {
    final libs = [_fakeLibrary(1, 'Movies'), _fakeLibrary(2, 'TV Shows')];
    fakeRepo.onGetLibraries = () async => Right(libs);

    await notifier.load();

    final loaded = notifier.state as LibraryLoaded;
    expect(loaded.libraries, hasLength(2));
    expect(loaded.libraries[0].name, 'Movies');
  });

  test('load emits error on failure', () async {
    fakeRepo.onGetLibraries =
        () async => const Left(ServerFailure(message: 'Failed'));

    await notifier.load();

    expect(notifier.state, isA<LibraryError>());
    expect((notifier.state as LibraryError).message, 'Failed');
  });

  test('scan reloads libraries', () async {
    final libs = [_fakeLibrary(1)];
    fakeRepo.onGetLibraries = () async => Right(libs);
    fakeRepo.onScanLibrary = (_) async => Right(_fakeLibrary(1));

    await notifier.scan(1);

    final loaded = notifier.state as LibraryLoaded;
    expect(loaded.libraries, hasLength(1));
  });
}
