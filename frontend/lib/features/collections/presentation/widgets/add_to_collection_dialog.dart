import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/collections/domain/usecases/add_collection_item.dart';
import 'package:flux_media_server/features/collections/domain/usecases/create_collection.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
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

class _AddToCollectionDialogState
    extends ConsumerState<_AddToCollectionDialog> {
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
            return ListView.builder(
              shrinkWrap: true,
              itemCount: collections.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(l.create),
                    onTap: _loading ? null : () => _showCreateDialog(l),
                  );
                }
                final collection = collections[index - 1];
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(collection.name),
                  subtitle: Text(collection.type.value),
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

  Future<void> _showCreateDialog(AppLocalizations l) async {
    final nameController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.create),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.create),
          ),
        ],
      ),
    );
    if ((created ?? false) && nameController.text.isNotEmpty) {
      setState(() => _loading = true);
      try {
        final createCollection = ref.read(createCollectionProvider);
        final collection = await createCollection(
          CreateCollectionParams(name: nameController.text, type: 'video'),
        );
        collection.fold(
          (failure) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.failedToAdd(failure.message))),
              );
            }
          },
          (_) {
            ref.invalidate(collectionsProvider);
          },
        );
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
}
