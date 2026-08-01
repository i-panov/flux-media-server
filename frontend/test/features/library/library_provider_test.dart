import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

MediaLibrary _fakeLibrary(int id, [String? name]) => MediaLibrary(
      id: id,
      name: name ?? 'Library $id',
      path: '/media/$id',
      type: 'movie',
      enabled: true,
    );

class FakeLibraryRepository implements LibraryRepository {
  Future<Either<Failure, List<MediaLibrary>>> Function()? onGetLibraries;
  Future<Either<Failure, String>> Function(int)? onScanLibrary;
  Future<Either<Failure, ScanStatus>> Function(int)? onGetScanStatus;
  Future<Either<Failure, MediaLibrary>> Function({required String name, required String type})? onCreateLibrary;
  Future<Either<Failure, void>> Function(int)? onDeleteLibrary;

  @override
  Future<Either<Failure, List<MediaLibrary>>> getLibraries() =>
      onGetLibraries!();

  @override
  Future<Either<Failure, String>> scanLibrary(int id) =>
      onScanLibrary!(id);

  @override
  Future<Either<Failure, ScanStatus>> getScanStatus(int id) =>
      onGetScanStatus!(id);

  @override
  Future<Either<Failure, MediaLibrary>> createLibrary({required String name, required String type}) =>
      onCreateLibrary!(name: name, type: type);

  @override
  Future<Either<Failure, void>> deleteLibrary(int id) =>
      onDeleteLibrary!(id);
}

void main() {
  late ProviderContainer container;
  late FakeLibraryRepository fakeRepo;

  setUp(() {
    fakeRepo = FakeLibraryRepository();
    container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('loads libraries on build', () async {
    final libs = [_fakeLibrary(1, 'Movies'), _fakeLibrary(2, 'TV Shows')];
    fakeRepo.onGetLibraries = () async => Right(libs);

    final result = await container.read(libraryProvider.future);
    expect(result, hasLength(2));
    expect(result[0].name, 'Movies');
  });

  test('scan triggers library scan and starts polling', () async {
    final libs = [_fakeLibrary(1)];
    fakeRepo.onGetLibraries = () async => Right(libs);
    fakeRepo.onScanLibrary = (_) async => const Right('Scan started');
    fakeRepo.onGetScanStatus = (_) async => const Right(
      ScanStatus(libraryId: 1, running: false),
    );

    // First load
    await container.read(libraryProvider.future);

    // Then scan
    await container.read(libraryProvider.notifier).scan(1);

    // Verify scanning started
    expect(container.read(libraryProvider.notifier).scanningLibraryId, 1);
    expect(container.read(libraryProvider.notifier).isScanning, isTrue);
  });
}
