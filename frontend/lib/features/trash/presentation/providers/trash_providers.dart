import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/trash/data/trash_remote_datasource.dart';
import 'package:flux_media_server/features/trash/domain/trash_repository.dart';

final trashRemoteDataSourceProvider = Provider<TrashRemoteDataSource>((ref) {
  return TrashRemoteDataSource(ref.watch(libraryApiClientProvider));
});

final trashRepositoryProvider = Provider<TrashRepository>((ref) {
  return TrashRepositoryImpl(ref.watch(trashRemoteDataSourceProvider));
});

/// Содержимое корзины: коллекции и медиа плоским списком.
final FutureProvider<TrashContents> trashProvider =
    FutureProvider.autoDispose<TrashContents>((ref) async {
      final result = await ref.watch(trashRepositoryProvider).getTrash();
      return await result.fold(
        // Тип Failure сохраняется в AsyncError (не заворачивается в Exception).
        // ignore: only_throw_errors
        (failure) => throw failure,
        (contents) => contents,
      );
    });
