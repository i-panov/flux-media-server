import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/media/data/datasources/media_remote_datasource.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Инвалидирует списки медиа обоих типов после мутаций (загрузка,
/// удаление, смена обложки, редактирование метаданных).
void refreshMediaLists(WidgetRef ref) {
  ref
    ..invalidate(mediaListProvider('video'))
    ..invalidate(mediaListProvider('audio'));
}

class MediaListResult {
  const new({required this.items, required this.total});

  final IList<Media> items;
  final int total;
}

final mediaRemoteDataSourceProvider = Provider<MediaRemoteDataSource>((ref) {
  return MediaRemoteDataSource(
    ref.watch(mediaApiClientProvider),
    libraryApiClient: ref.watch(libraryApiClientProvider),
    uploadBaseUrl: ref.watch(baseUrlProvider),
    // Общий клиент с TLS-настройками приложения, а не голый http.Client:
    // иначе upload/cover падали бы на самоподписанных сертах.
    clientFactory: () => ref.read(directHttpClientProvider),
    authToken: () => ref.read(settingsProvider).settings.authToken,
    refreshAuth: () async {
      final refreshToken = ref.read(settingsProvider).settings.refreshToken;
      if (refreshToken == null) return null;
      final refreshed = await ref
          .read(authTokenRefresherProvider)
          .refresh(refreshToken);
      return refreshed ? ref.read(settingsProvider).settings.authToken : null;
    },
  );
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepositoryImpl(ref.watch(mediaRemoteDataSourceProvider));
});

/// Текущий поисковый запрос, ограниченный типом медиа ('video'/'audio').
/// Family не даёт состоянию «протекать» между вкладками.
class SearchQueryNotifier extends Notifier<String> {
  // Riverpod 3: family-аргумент приходит через конструктор (create-функция
  // провайдера — tear-off конструктора с параметром), build() без аргументов.
  new(this.type);

  final String type;

  @override
  String build() => '';

  /// Текущий поисковый запрос для типа медиа.
  String get query => state;

  /// Обновляет поисковый запрос для типа медиа.
  set query(String value) => state = value;
}

final searchQueryProvider =
    NotifierProvider.family<SearchQueryNotifier, String, String>(
      SearchQueryNotifier.new,
    );

/// Media list scoped to a media type ('video' or 'audio').
/// Using a family avoids state leakage between audio/video tabs that
/// previously shared a single global [mediaListProvider].
final mediaListProvider =
    AsyncNotifierProvider.family<MediaListNotifier, MediaListResult, String>(
      MediaListNotifier.new,
    );

/// Обёртка [Failure] в Exception для проброса в AsyncValue.error:
/// линт only_throw_errors требует Exception/Error, а типизированный
/// failure сохраняется в поле — UI может различать network/auth/server.
class MediaListFailure implements Exception {
  const new(this.failure);

  final Failure failure;

  @override
  String toString() => failure.message;
}

class MediaListNotifier extends AsyncNotifier<MediaListResult> {
  // Riverpod 3: family-аргумент приходит через конструктор (create-функция
  // провайдера — tear-off конструктора с параметром), build() без аргументов.
  new(this.type);

  final String type;

  static const _pageSize = 20;

  bool _isLoadingMore = false;

  @override
  Future<MediaListResult> build() async {
    // Смена query (или тип) пересоздаёт список: сбрасываем флаг,
    // иначе незавершённый loadMore заблокирует подгрузку нового списка.
    _isLoadingMore = false;

    final q = ref.watch(searchQueryProvider(type));
    final result = await ref
        .watch(mediaRepositoryProvider)
        .getMediaList(limit: _pageSize, offset: 0, q: q.isEmpty ? null : q, type: type);
    return await result.fold(
      (failure) {
        // Сеть пропала после запуска: включаем офлайн-режим, чтобы
        // экраны показали скачанные треки, а не ошибку. Сброс — при
        // следующем успешном запросе (build/loadMore) или checkAuthStatus.
        if (failure is NetworkFailure) {
          ref.read(networkStatusProvider.notifier).markOffline();
        }
        throw MediaListFailure(failure);
      },
      (data) {
        ref.read(networkStatusProvider.notifier).markOnline();
        return MediaListResult(items: data.items.toIList(), total: data.total);
      },
    );
  }

  /// Loads the next page of results.
  ///
  /// Guards against concurrent calls and stale query results:
  /// - [_isLoadingMore] prevents duplicate requests with the same offset.
  /// - Captures the query at call time and compares against the latest
  ///   value after the async request completes; if the query changed, the
  ///   result is discarded to avoid appending items from a previous search.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.items.length >= current.total) return;
    if (_isLoadingMore) return;

    // Capture the query at call time.
    final qAtCall = ref.read(searchQueryProvider(type));
    _isLoadingMore = true;

    final result = await ref
        .read(mediaRepositoryProvider)
        .getMediaList(
          limit: _pageSize,
          offset: current.items.length,
          q: qAtCall.isEmpty ? null : qAtCall,
          type: type,
        );

    _isLoadingMore = false;

    // If the query changed during the async request, discard the result.
    final qNow = ref.read(searchQueryProvider(type));
    if (qNow != qAtCall) return;

    result.fold(
      (failure) {
        if (failure is NetworkFailure) {
          ref.read(networkStatusProvider.notifier).markOffline();
        }
        // Данные сохраняем, но ошибку показываем: Riverpod 3 при
        // присвоении AsyncError сам сохраняет предыдущее значение
        // (copyWithPrevious теперь internal и вызывается фреймворком).
        state = AsyncValue<MediaListResult>.error(
          MediaListFailure(failure),
          StackTrace.current,
        );
      },
      (data) {
        ref.read(networkStatusProvider.notifier).markOnline();
        state = AsyncValue.data(
          MediaListResult(
            items: current.items.addAll(data.items),
            total: data.total,
          ),
        );
      },
    );
  }
}
