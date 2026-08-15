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
class FavoriteToggleNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<bool>, int> {
  bool _isToggling = false;
  bool _disposed = false;

  @override
  AsyncValue<bool> build(int mediaId) {
    ref
      ..onDispose(() => _disposed = true)
      ..listen<AsyncValue<Set<int>>>(
        favoriteMediaIdsProvider,
        (_, next) => _applyIdsState(next),
      );
    return ref.read(favoriteMediaIdsProvider).when(
      data: (ids) => AsyncValue<bool>.data(ids.contains(mediaId)),
      loading: () => const AsyncValue<bool>.loading(),
      error: (e, st) {
        AppLogger.error('Failed to load favorite ids', e);
        return const AsyncValue<bool>.data(false);
      },
    );
  }

  void _applyIdsState(AsyncValue<Set<int>> ids) {
    state = ids.when(
      data: (ids) => AsyncValue<bool>.data(ids.contains(arg)),
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
    _applyIdsState(ref.read(favoriteMediaIdsProvider));
  }

  /// Toggles favorite status for this media item.
  Future<void> toggle() async {
    if (_isToggling) return;
    _isToggling = true;

    try {
      final isOffline = ref.read(isOfflineProvider);
      // Офлайн: локальный кеш и есть источник истины — показываем
      // текущее состояние, ничего не меняем на сервере.
      if (isOffline) {
        _syncFromProvider();
        return;
      }

      // Не-autoDispose зависимости захватываются до await: даже если
      // нотифаер будет автоутилизирован, источник истины обновится.
      final favorites = ref.read(favoritesProvider.notifier);
      final addFavorite = ref.read(addFavoriteProvider);
      final removeFavorite = ref.read(removeFavoriteProvider);

      final currentState = await _isFavorited();
      if (!_disposed) state = AsyncValue.data(!currentState);

      if (currentState) {
        final result = await removeFavorite(arg);
        result.fold(
          (failure) {
            AppLogger.error('Failed to remove favorite $arg', failure);
            if (!_disposed) _syncFromProvider();
          },
          (_) => favorites.removeLocal(arg),
        );
      } else {
        final result = await addFavorite(arg);
        result.fold(
          (failure) {
            AppLogger.error('Failed to add favorite $arg', failure);
            if (!_disposed) _syncFromProvider();
          },
          favorites.addLocal,
        );
      }
    } catch (e) {
      AppLogger.error('Failed to toggle favorite $arg', e);
      if (!_disposed) _syncFromProvider();
    } finally {
      _isToggling = false;
    }
  }

  /// Возвращает фактическое состояние избранного из кеша.
  Future<bool> _isFavorited() async {
    final favorites = ref.read(favoritesProvider).valueOrNull;
    if (favorites != null) {
      return favorites.any((f) => f.mediaId == arg);
    }
    try {
      final ids = await ref.read(favoriteMediaIdsProvider.future);
      return ids.contains(arg);
    } catch (e) {
      AppLogger.error('Failed to read favorite state $arg', e);
      return false;
    }
  }
}

/// Provider for toggling favorite status of a specific media item.
///
/// autoDispose: состояние выводится из keepAlive [favoriteMediaIdsProvider],
/// поэтому пересоздание нотифаера дешёво и не утекает на каждый трек.
final favoriteToggleProvider = NotifierProvider.autoDispose
    .family<FavoriteToggleNotifier, AsyncValue<bool>, int>(
  FavoriteToggleNotifier.new,
);
