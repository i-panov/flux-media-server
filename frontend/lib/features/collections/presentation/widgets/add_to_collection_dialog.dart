import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/create_collection_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Shows a dialog to add a media item to a collection.
/// Returns true if the item was added.
Future<bool?> showAddToCollectionDialog(
  BuildContext context,
  int mediaId, {
  String mediaType = 'video',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) =>
        _AddToCollectionDialog(mediaId: mediaId, mediaType: mediaType),
  );
}

class _AddToCollectionDialog extends ConsumerStatefulWidget {
  const new({required this.mediaId, required this.mediaType});

  final int mediaId;
  final String mediaType;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 4),
            Flexible(
              child: collectionsState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(l.failedToAdd(_errorText(e))),
                data: (collections) {
                  final filtered = collections
                      .where((c) => c.type.value == widget.mediaType)
                      .toList();
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.add),
                          title: Text(l.create),
                          onTap: _loading ? null : () => _showCreateDialog(l),
                        );
                      }
                      final collection = filtered[index - 1];
                      return _CollectionTile(
                        collection: collection,
                        mediaId: widget.mediaId,
                        enabled: !_loading,
                        onTap: () => _addToCollection(collection),
                        onRemove: () => _removeFromCollection(collection),
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
      final result = await ref
          .read(collectionsRepositoryProvider)
          .addCollectionItem(collection.id, widget.mediaId);
      if (!mounted) return;
      result.fold(
        (failure) {
          showErrorSnackBar(context, l.failedToAdd(failure.message));
        },
        (_) {
          // Перечитываем элементы коллекции, чтобы показать новый элемент.
          ref.invalidate(collectionItemsFullProvider(collection.id));
          Navigator.pop(context, true);
          showSuccessSnackBar(context, l.addedToCollection(collection.name));
        },
      );
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, l.failedToAdd(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Убрать элемент из коллекции.
  ///
  /// Раньше элемент можно было только добавить: плитка уже добавленной
  /// коллекции блокировала тап, и из коллекции было не выйти — ни из
  /// этого диалога, ни откуда-то ещё (в аудио-разделе коллекции вообще
  /// не показывались, то есть и не существовало места, где их видно).
  Future<void> _removeFromCollection(Collection collection) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(collectionsRepositoryProvider)
          .removeCollectionItem(collection.id, widget.mediaId);
      if (!mounted) return;
      result.fold(
        (failure) {
          showErrorSnackBar(context, l.failedToRemove(failure.message));
        },
        (_) {
          // Перечитываем элементы коллекции, чтобы убрать удалённый.
          ref.invalidate(collectionItemsFullProvider(collection.id));
          showSuccessSnackBar(
            context,
            l.removedFromCollection(collection.name),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, l.failedToRemove(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateDialog(AppLocalizations l) async {
    setState(() => _loading = true);
    try {
      final created = await showCreateCollectionDialog(
        context,
        type: widget.mediaType == 'audio' ? MediaType.audio : MediaType.video,
      );
      if (!mounted) return;
      if (created != null) {
        ref.invalidate(collectionsProvider);
        showSuccessSnackBar(context, l.createdCollection(created.name));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorText(Object error) {
    if (error is Failure) return error.message;
    return error.toString();
  }
}

/// Плитка коллекции: подсвечивает «уже добавлено» и блокирует тап.
class _CollectionTile extends ConsumerWidget {
  const new({
    required this.collection,
    required this.mediaId,
    required this.enabled,
    required this.onTap,
    required this.onRemove,
  });

  final Collection collection;
  final int mediaId;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final itemsState = ref.watch(collectionItemsFullProvider(collection.id));
    final alreadyAdded = itemsState.value?.any((m) => m.id == mediaId) ?? false;
    return ListTile(
      leading: Icon(alreadyAdded ? Icons.check_circle : Icons.folder),
      title: Text(collection.name),
      subtitle: Text(collection.type.value),
      // Уже добавленный элемент нельзя добавить повторно, но можно убрать —
      // поэтому вместо блокирующей надписи кнопка удаления.
      trailing: alreadyAdded
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: l.removeFromCollection,
              onPressed: enabled ? onRemove : null,
            )
          : null,
      onTap: enabled && !alreadyAdded ? onTap : null,
    );
  }
}
