import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';

/// Notifier that toggles favorite status for a media item.
/// Optimistically updates the UI, then calls the API.
class FavoriteToggleNotifier extends StateNotifier<AsyncValue<bool>> {
  FavoriteToggleNotifier(this._ref) : super(const AsyncValue.data(false));

  final Ref _ref;

  /// Initializes the toggle state for a media item.
  void init(bool isFavorite) {
    state = AsyncValue.data(isFavorite);
  }

  /// Toggles favorite status. [mediaId] is the media to toggle.
  /// [type] is 'video' or 'audio'.
  Future<void> toggle(int mediaId, String type) async {
    final currentState = state.valueOrNull ?? false;
    // Optimistic update
    state = AsyncValue.data(!currentState);

    try {
      if (currentState) {
        // Remove favorite
        final removeFavorite = _ref.read(removeFavoriteProvider);
        final result = await removeFavorite(mediaId);
        result.fold(
          (failure) => state = AsyncValue.error(failure.message, StackTrace.current),
          (_) {
            // Refresh favorites list
            _ref.invalidate(favoritesProvider(null));
            _ref.invalidate(favoritesProvider(type));
          },
        );
      } else {
        // Add favorite
        final addFavorite = _ref.read(addFavoriteProvider);
        final result = await addFavorite(mediaId);
        result.fold(
          (failure) => state = AsyncValue.error(failure.message, StackTrace.current),
          (_) {
            _ref.invalidate(favoritesProvider(null));
            _ref.invalidate(favoritesProvider(type));
          },
        );
      }
    } catch (e, st) {
      // Revert on error
      state = AsyncValue.data(currentState);
      state = AsyncValue.error(e, st);
    }
  }
}

/// Provider for toggling favorite status of a specific media item.
final favoriteToggleProvider =
    StateNotifierProvider.autoDispose.family<FavoriteToggleNotifier, AsyncValue<bool>, int>(
  (ref, mediaId) => FavoriteToggleNotifier(ref),
);
