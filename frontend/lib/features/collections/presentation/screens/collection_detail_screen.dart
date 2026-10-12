import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/core/widgets/skeleton_media_grid.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/collections/domain/usecases/remove_collection_item.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_media_dialog.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/collection_grid_tile.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const new({required this.collection, super.key});

  final Collection collection;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final itemsState = ref.watch(
      collectionItemsFullProvider(widget.collection.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.addMedia,
            onPressed: () => _showAddMediaDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: itemsState.when(
        loading: () => _buildSkeletonGrid(context),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(
            collectionItemsFullProvider(widget.collection.id),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l.thisCollectionIsEmpty),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (MediaQuery.of(context).size.width / 180)
                  .floor()
                  .clamp(2, 6),
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final media = items[index];
              return CollectionGridTile(
                media: media,
                onTap: () {
                  if (media.type == MediaType.audio) {
                    unawaited(
                      context.router.push(AudioPlayerRoute(media: media)),
                    );
                  } else {
                    unawaited(
                      context.router.push(
                        VideoDetailRoute(mediaId: media.id),
                      ),
                    );
                  }
                },
                onRemove: () => _confirmRemoveItem(context, media),
              );
            },
          );
        },
      ),
    );
  }

  /// Подтверждение и удаление элемента из коллекции.
  Future<void> _confirmRemoveItem(BuildContext context, Media media) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFromCollection),
        content: Text(media.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removeCollectionItem = ref.read(removeCollectionItemProvider);
    final result = await removeCollectionItem(
      RemoveCollectionItemParams(
        collectionId: widget.collection.id,
        mediaId: media.id,
      ),
    );
    if (!mounted) return;
    result.fold(
      (failure) {
        final l = AppLocalizations.of(context)!;
        showErrorSnackBar(context, l.failedToRemove(failure.message));
      },
      (_) {
        // Оптимистичное обновление списка — без refetch.
        ref
            .read(collectionItemsFullProvider(widget.collection.id).notifier)
            .removeLocal(media.id);
      },
    );
  }

  /// Диалог выбора медиа для добавления в коллекцию (со списком
  /// медиа типа коллекции и клиентским фильтром-поиском).
  Future<void> _showAddMediaDialog(BuildContext context) {
    return showAddMediaDialog(context, widget.collection);
  }

  Widget _buildSkeletonGrid(BuildContext context) {
    final crossAxisCount = (MediaQuery.of(context).size.width / 180)
        .floor()
        .clamp(2, 6);
    return SkeletonMediaGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      // Две «страницы» — столько же плашек, сколько в коллекции.
      itemCount: crossAxisCount * 2,
    );
  }

  void _confirmDelete(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteCollection),
          content: Text(l.deleteCollectionConfirm(widget.collection.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final deleteCollection = ref.read(deleteCollectionProvider);
                final result = await deleteCollection(widget.collection.id);
                if (context.mounted) {
                  result.fold(
                    (failure) {
                      showErrorSnackBar(
                        context,
                        l.failedToRemove(failure.message),
                      );
                    },
                    (_) {
                      ref.invalidate(collectionsProvider);
                      unawaited(context.router.maybePop());
                    },
                  );
                }
              },
              child: Text(l.delete, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
