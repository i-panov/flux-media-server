import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/media.dart';

final libraryMediaTypeFilterProvider = StateProvider<String?>((ref) => null);

final libraryMediaProvider = AsyncNotifierProvider.family<LibraryMediaNotifier, IList<Media>, MediaLibrary>(
  LibraryMediaNotifier.new,
);

class LibraryMediaNotifier extends FamilyAsyncNotifier<IList<Media>, MediaLibrary> {
  static const _pageSize = 20;

  @override
  Future<IList<Media>> build(MediaLibrary arg) async {
    final repo = ref.watch(mediaRepositoryProvider);
    final type = ref.watch(libraryMediaTypeFilterProvider);
    final result = await repo.getMediaList(libraryId: arg.id, type: type, limit: _pageSize, offset: 0);
    return result.fold(
      (failure) => throw Exception(failure.message),
      (data) => data.items.toIList(),
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull ?? IList();
    final repo = ref.read(mediaRepositoryProvider);
    final type = ref.read(libraryMediaTypeFilterProvider);
    final result = await repo.getMediaList(libraryId: arg.id, type: type, limit: _pageSize, offset: current.length);
    result.fold(
      (failure) => state = AsyncError(Exception(failure.message), StackTrace.current),
      (data) => state = AsyncValue.data(current.addAll(data.items)),
    );
  }

  void refresh() => ref.invalidateSelf();
}
