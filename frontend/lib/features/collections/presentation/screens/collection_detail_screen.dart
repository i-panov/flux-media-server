import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({super.key, required this.collection});

  final Collection collection;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends ConsumerState<CollectionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final itemsState = ref.watch(collectionItemsProvider(widget.collection.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: itemsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(
                    collectionItemsProvider(widget.collection.id)),
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
              final item = items[index];
              return FutureBuilder<Media?>(
                future: _fetchMedia(item.mediaId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Card(child: Center(child: CircularProgressIndicator()));
                  }
                  final media = snapshot.data!;
                  return MediaCard(
                    media: media,
                    onTap: () => context.router.push(MediaDetailRoute(mediaId: media.id)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<Media?> _fetchMedia(int mediaId) async {
    final mediaDetail = ref.read(mediaDetailProvider.notifier);
    await mediaDetail.load(mediaId);
    final state = ref.read(mediaDetailProvider);
    return state.maybeWhen(
      loaded: (media) => media,
      orElse: () => null,
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
              await deleteCollection(widget.collection.id);
              ref.invalidate(collectionsProvider);
              if (context.mounted) {
                context.router.pop();
              }
            },
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
