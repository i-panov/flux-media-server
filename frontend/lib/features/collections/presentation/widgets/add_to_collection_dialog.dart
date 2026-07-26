import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/domain/usecases/add_collection_item.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';

/// Shows a dialog to add a media item to a collection.
/// Returns true if the item was added.
Future<bool?> showAddToCollectionDialog(
  BuildContext context,
  WidgetRef ref,
  int mediaId,
) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _AddToCollectionDialog(mediaId: mediaId),
  );
}

class _AddToCollectionDialog extends ConsumerStatefulWidget {
  const _AddToCollectionDialog({required this.mediaId});

  final int mediaId;

  @override
  ConsumerState<_AddToCollectionDialog> createState() =>
      _AddToCollectionDialogState();
}

class _AddToCollectionDialogState extends ConsumerState<_AddToCollectionDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final collectionsState = ref.watch(collectionsProvider);

    return AlertDialog(
      title: Text(l.addToCollection),
      content: SizedBox(
        width: double.maxFinite,
        child: collectionsState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(l.failedToAdd(e.toString())),
          data: (collections) {
            if (collections.isEmpty) {
              return Center(child: Text(l.noCollectionsYetCreate));
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final collection = collections[index];
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(collection.name),
                  subtitle: Text(collection.type),
                  onTap: _loading ? null : () => _addToCollection(collection),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }

  Future<void> _addToCollection(Collection collection) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _loading = true);
    try {
      final addCollectionItem = ref.read(addCollectionItemProvider);
      await addCollectionItem(
        AddCollectionItemParams(
          collectionId: collection.id,
          mediaId: widget.mediaId,
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.addedToCollection(collection.name))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.failedToAdd(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
