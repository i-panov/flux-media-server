import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/progress.dart';

/// Async provider that fetches all watch progress for the current user.
final FutureProvider<List<WatchProgress>> watchProgressProvider =
    FutureProvider.autoDispose<List<WatchProgress>>((ref) async {
      final result = await ref.watch(mediaRepositoryProvider).getProgress();
      return await result.fold(
        // Тип Failure сохраняется в AsyncError (не заворачивается в Exception).
        // ignore: only_throw_errors
        (failure) => throw failure,
        (progress) => progress,
      );
    });
