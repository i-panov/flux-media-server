import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/logger.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';

/// Notifier that toggles favorite status for a media item.
///
/// Состояние выводится из [favoriteMediaIdsProvider] — единого источника
/// истины (keepAlive). Подписка через [Ref.listen] держит иконку в
/// синхронизации на всех экранах: снятие избранного в любом месте
/// мгновенно отражается в остальных.
///
/// autoDispose: нотифаер — дешёвая производная от keepAlive-провайдера,
/// поэтому для каждого трека мини-плеера не копятся вечные экземпляры.
class FavoriteToggleNotifier extends StateNotifier<AsyncValue<bool>> {
  FavoriteToggleNotifier(this._ref, this._mediaId)
      : super(const AsyncValue.loading()) {
    _syncFromProvider();
    _ref.listen<AsyncValue<Set<int>>>(
      favoriteMediaIdsProvider,
      (_, next) => _applyIdsState(next),
    );
  }

  final Ref _ref;
  final int _mediaId;
  bool _isToggling = false;

  void _applyIdsState(AsyncValue<Set<int>> ids) {
    state = ids.when(
      data: (ids) => AsyncValue<bool>.data(ids.contains(_mediaId)),
      // Пересчёт списка не должен «мигать» иконкой: пока новое множество
      // вычисляется, сохраняем предыдущее значение.
      loading: () => state,
      error: (e, _) {
        AppLogger.error('Failed to load favorite ids', e);
        return state;
      },
    );
  }

  void _syncFromProvider() {
    _applyIdsState(_ref.read(favoriteMediaIdsProvider));
  }

  /// Toggles favorite status for [_mediaId].
  Future<void> toggle() async {
    if (_isToggling) return;
    _isToggling = true;

    try {
      final isOffline = _ref.read(isOfflineProvider);
      // Офлайн: локальный кеш и есть источник истины — показываем
      // текущее состояние, ничего не меняем на сервере.
      if (isOffline) {
        _syncFromProvider();
        return;
      }

      // Не-autoDispose зависимости захватываются до await: даже если
      // нотифаер будет автоутилизирован, источник истины обновится.
      final favorites = _ref.read(favoritesProvider.notifier);
      final addFavorite = _ref.read(addFavoriteProvider);
      final removeFavorite = _ref.read(removeFavoriteProvider);

      final currentState = await _isFavorited();
      if (mounted) state = AsyncValue.data(!currentState);

      if (currentState) {
        final result = await removeFavorite(_mediaId);
        result.fold(
          (failure) {
            AppLogger.error('Failed to remove favorite $_mediaId', failure);
            if (mounted) _syncFromProvider();
          },
          (_) => favorites.removeLocal(_mediaId),
        );
      } else {
        final result = await addFavorite(_mediaId);
        result.fold(
          (failure) {
            AppLogger.error('Failed to add favorite $_mediaId', failure);
            if (mounted) _syncFromProvider();
          },
          favorites.addLocal,
        );
      }
    } catch (e) {
      AppLogger.error('Failed to toggle favorite $_mediaId', e);
      if (mounted) _syncFromProvider();
    } finally {
      _isToggling = false;
    }
  }

  /// Возвращает фактическое состояние избранного из кеша.
  Future<bool> _isFavorited() async {
    final favorites = _ref.read(favoritesProvider).valueOrNull;
    if (favorites != null) {
      return favorites.any((f) => f.mediaId == _mediaId);
    }
    try {
      final ids = await _ref.read(favoriteMediaIdsProvider.future);
      return ids.contains(_mediaId);
    } catch (e) {
      AppLogger.error('Failed to read favorite state $_mediaId', e);
      return false;
    }
  }
}

/// Provider for toggling favorite status of a specific media item.
///
/// autoDispose: состояние выводится из keepAlive [favoriteMediaIdsProvider],
/// поэтому пересоздание нотифаера дешёво и не утекает на каждый трек.
final favoriteToggleProvider = StateNotifierProvider.autoDispose
    .family<FavoriteToggleNotifier, AsyncValue<bool>, int>(
  FavoriteToggleNotifier.new,
);
