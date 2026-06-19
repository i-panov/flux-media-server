import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/library/data/datasources/library_remote_datasource.dart';
import 'package:flux_media_server/features/library/data/repositories/library_repository_impl.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';

final libraryRemoteDataSourceProvider = Provider<LibraryRemoteDataSource>((ref) {
  return LibraryRemoteDataSource(ref.watch(apiClientProvider));
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepositoryImpl(ref.watch(libraryRemoteDataSourceProvider));
});

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<MediaLibrary>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<MediaLibrary>> {
  @override
  Future<List<MediaLibrary>> build() async {
    final repo = ref.watch(libraryRepositoryProvider);
    final result = await repo.getLibraries();
    return result.getOrElse(() => throw Exception('Failed to load libraries'));
  }

  Future<void> scan(int id) async {
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.scanLibrary(id);
    await result.fold(
      (failure) => state = AsyncError(Exception(failure.message), StackTrace.current),
      (_) async {
        state = const AsyncLoading();
        state = await AsyncValue.guard(() => build());
      },
    );
  }
}
