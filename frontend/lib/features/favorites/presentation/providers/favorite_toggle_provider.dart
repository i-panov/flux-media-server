import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';

/// Notifier that toggles favorite status for a media item.
/// Optimistically updates the UI based on the actual provider state.
///
/// NOT autoDispose: the toggle may be called via ref.read (e.g. from cards in
/// lists) where no one watches the state. Without autoDispose the notifier
/// survives the toggle and correctly retains its state.
class FavoriteToggleNotifier extends StateNotifier<AsyncValue<bool>> {
  FavoriteToggleNotifier(this._ref, this._mediaId)
      : super(const AsyncValue.loading());

  final Ref _ref;
  final int _mediaId;
  bool _isToggling = false;

  /// Returns the actual favorite state from the cached
  /// [favoriteMediaIdsProvider].
  Future<bool> _isFavorited() async {
    try {
      final ids = await _ref.read(favoriteMediaIdsProvider.future);
      return ids.contains(_mediaId);
    } catch (_) {
      return false;
    }
  }

  /// Toggles favorite status.
  Future<void> toggle(int mediaId) async {
    if (!mounted || _isToggling) return;
    _isToggling = true;

    try {
      // Read the real state directly – do not trust the cached bool.
      final currentState = await _isFavorited();
      if (!mounted) return;

      // Optimistic update
      state = AsyncValue.data(!currentState);

      try {
        if (currentState) {
          final removeFavorite = _ref.read(removeFavoriteProvider);
          final result = await removeFavorite(mediaId);
          if (!mounted) return;
          result.fold(
            (failure) {
              if (!mounted) return;
              // Revert to previous state on error.
              state = AsyncValue.data(currentState);
            },
            (_) {
              _ref
                ..invalidate(favoritesProvider)
                ..invalidate(favoriteMediaIdsProvider);
            },
          );
        } else {
          final addFavorite = _ref.read(addFavoriteProvider);
          final result = await addFavorite(mediaId);
          if (!mounted) return;
          result.fold(
            (failure) {
              if (!mounted) return;
              // Revert to previous state on error.
              state = AsyncValue.data(currentState);
            },
            (_) {
              _ref
                ..invalidate(favoritesProvider)
                ..invalidate(favoriteMediaIdsProvider);
            },
          );
        }
    } catch (e) {
      if (!mounted) return;
      // Revert to previous state on error.
      state = AsyncValue.data(currentState);
    }
    } finally {
      _isToggling = false;
    }
  }
}

/// Provider for toggling favorite status of a specific media item.
/// Not auto-disposed so that `toggle` can be called via `ref.read` without
/// the notifier being garbage-collected mid-operation.
final favoriteToggleProvider =
    StateNotifierProvider.family<FavoriteToggleNotifier, AsyncValue<bool>, int>(
  FavoriteToggleNotifier.new,
);
