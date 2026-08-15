import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_watch_progress.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// Provider for the GetWatchProgress use case.
final getWatchProgressProvider = Provider<GetWatchProgress>((ref) {
  return GetWatchProgress(ref.watch(mediaRepositoryProvider));
});

/// Async provider that fetches all watch progress for the current user.
final watchProgressProvider =
    FutureProvider.autoDispose<List<WatchProgress>>((ref) async {
  final getProgress = ref.watch(getWatchProgressProvider);
  final result = await getProgress(const NoParams());
  return result.fold(
    (failure) => throw Exception(failure.message),
    (progress) => progress,
  );
});
