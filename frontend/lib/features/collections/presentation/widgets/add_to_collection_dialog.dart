import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
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
  int mediaId, {
  String mediaType = 'video',
}) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _AddToCollectionDialog(
      mediaId: mediaId,
      mediaType: mediaType,
    ),
  );
}

class _AddToCollectionDialog extends ConsumerStatefulWidget {
  const _AddToCollectionDialog({
    required this.mediaId,
    required this.mediaType,
  });

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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
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
                          onTap:
                              _loading ? null : () => _showCreateDialog(l),
                        );
                      }
                      final collection = filtered[index - 1];
                      return _CollectionTile(
                        collection: collection,
                        mediaId: widget.mediaId,
                        enabled: !_loading,
                        onTap: () => _addToCollection(collection),
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
      final addCollectionItem = ref.read(addCollectionItemProvider);
      final result = await addCollectionItem(
        AddCollectionItemParams(
          collectionId: collection.id,
          mediaId: widget.mediaId,
        ),
      );
      if (!mounted) return;
      result.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.failedToAdd(failure.message))),
          );
        },
        (_) {
          // Перечитываем элементы коллекции, чтобы показать новый элемент.
          ref.invalidate(collectionItemsFullProvider(collection.id));
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.addedToCollection(collection.name))),
          );
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

  Future<void> _showCreateDialog(AppLocalizations l) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateCollectionDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _loading = true);
    try {
      final createCollection = ref.read(createCollectionProvider);
      final collection = await createCollection(
        CreateCollectionParams(
          name: name,
          type: widget.mediaType,
        ),
      );
      if (!mounted) return;
      collection.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.failedToAdd(failure.message))),
          );
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

  String _errorText(Object error) {
    if (error is Failure) return error.message;
    return error.toString();
  }
}

/// Плитка коллекции: подсвечивает «уже добавлено» и блокирует тап.
class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({
    required this.collection,
    required this.mediaId,
    required this.enabled,
    required this.onTap,
  });

  final Collection collection;
  final int mediaId;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final itemsState =
        ref.watch(collectionItemsFullProvider(collection.id));
    final alreadyAdded =
        itemsState.valueOrNull?.any((m) => m.id == mediaId) ?? false;
    return ListTile(
      enabled: enabled && !alreadyAdded,
      leading: Icon(alreadyAdded ? Icons.check_circle : Icons.folder),
      title: Text(collection.name),
      subtitle: Text(collection.type.value),
      trailing: alreadyAdded ? Text(l.alreadyAdded) : null,
      onTap: enabled && !alreadyAdded ? onTap : null,
    );
  }
}

/// Диалог создания коллекции: trim имени, Create активна при непустом
/// поле, контроллер диспозится.
class _CreateCollectionDialog extends StatefulWidget {
  const _CreateCollectionDialog();

  @override
  State<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<_CreateCollectionDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final canSubmit = _nameController.text.trim().isNotEmpty;
    if (canSubmit != _canSubmit) {
      setState(() => _canSubmit = canSubmit);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.create),
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(hintText: l.name),
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(l.create),
        ),
      ],
    );
  }
}
