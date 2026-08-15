import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';
import 'package:flux_media_server/features/collections/domain/usecases/add_collection_item.dart';
import 'package:flux_media_server/features/collections/domain/usecases/remove_collection_item.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

String _errorText(Object error) {
  if (error is Failure) return error.message;
  return error.toString();
}

@RoutePage()
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({required this.collection, super.key});

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
    final itemsState =
        ref.watch(collectionItemsFullProvider(widget.collection.id));

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
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorText(e), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(
                  collectionItemsFullProvider(widget.collection.id),
                ),
                child: Text(l.retry),
              ),
            ],
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
              crossAxisCount:
                  (MediaQuery.of(context).size.width / 180).floor().clamp(2, 6),
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final media = items[index];
              return Stack(
                children: [
                  MediaCard(
                    media: media,
                    onTap: () => context.router.push(
                      MediaDetailRoute(mediaId: media.id),
                    ),
                  ),
                  // Кнопка удаления элемента из коллекции (зона тапа 48dp).
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _confirmRemoveItem(context, media),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.playlist_remove,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: ${failure.message}')),
        );
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
  Future<void> _showAddMediaDialog(BuildContext context) async {
    final l = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddMediaDialog(
        collection: widget.collection,
        mediaType: widget.collection.type.value,
        l: l,
      ),
    );
  }

  Widget _buildSkeletonGrid(BuildContext context) {
    final crossAxisCount =
        (MediaQuery.of(context).size.width / 180).floor().clamp(2, 6);
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: crossAxisCount * 2,
      itemBuilder: (context, index) => const Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SkeletonWidget(
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonWidget(height: 14, width: double.infinity),
                  SizedBox(height: 6),
                  SkeletonWidget(height: 10, width: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.failedToRemove(failure.message)),
                      ),
                    );
                  },
                  (_) {
                    ref.invalidate(collectionsProvider);
                    context.router.maybePop();
                  },
                );
              }
            },
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Диалог со списком медиа (с фильтром) для добавления в коллекцию.
class _AddMediaDialog extends ConsumerStatefulWidget {
  const _AddMediaDialog({
    required this.collection,
    required this.mediaType,
    required this.l,
  });

  final Collection collection;
  final String mediaType;
  final AppLocalizations l;

  @override
  ConsumerState<_AddMediaDialog> createState() => _AddMediaDialogState();
}

class _AddMediaDialogState extends ConsumerState<_AddMediaDialog> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  bool _adding = false;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final mediaListState = ref.watch(mediaListProvider(widget.mediaType));

    return AlertDialog(
      title: Text(l.addMedia),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: l.searchMedia,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _filter = value.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: mediaListState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(_errorText(e)),
                data: (result) {
                  final query = _filter.toLowerCase();
                  final items = result.items
                      .where(
                        (m) =>
                            query.isEmpty ||
                            m.title.toLowerCase().contains(query),
                      )
                      .toList();
                  if (items.isEmpty) {
                    return Center(child: Text(l.noMediaFound));
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final media = items[index];
                      return ListTile(
                        leading: const Icon(Icons.movie),
                        title: Text(media.title),
                        onTap: _adding
                            ? null
                            : () => _add(media),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _adding ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }

  Future<void> _add(Media media) async {
    final l = widget.l;
    setState(() => _adding = true);
    final addCollectionItem = ref.read(addCollectionItemProvider);
    final result = await addCollectionItem(
      AddCollectionItemParams(
        collectionId: widget.collection.id,
        mediaId: media.id,
      ),
    );
    if (!mounted) return;
    setState(() => _adding = false);
    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.failedToAdd(failure.message))),
        );
      },
      (_) {
        // Оптимистичное обновление списка — без refetch.
        ref
            .read(collectionItemsFullProvider(widget.collection.id).notifier)
            .addLocal(media);
        Navigator.pop(context);
      },
    );
  }
}
