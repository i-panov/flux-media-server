import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/presentation/providers/downloads_invalidator_provider.dart';
import 'package:flux_media_server/features/trash/presentation/providers/trash_providers.dart';

/// Единая инвалидация после изменений корзины (restore/purge/empty)
/// и удалений в неё: списки библиотеки, коллекции, избранное,
/// офлайн-список и сама корзина. Детали по id инвалидирует вызывающий
/// (mediaDetailProvider — family, id известен только ему).
void refreshAfterTrashChange(WidgetRef ref) {
  refreshMediaLists(ref);
  ref
    ..invalidate(collectionsProvider)
    ..invalidate(favoritesProvider)
    ..invalidate(trashProvider);
  // Офлайн-список строится из кеша на диске: дёргаем счётчик,
  // провайдер перезапросится сам (паттерн downloadsStateProvider).
  ref.read(downloadsInvalidatorProvider.notifier).state++;
}
