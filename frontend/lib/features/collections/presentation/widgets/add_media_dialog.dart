import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Диалог со списком медиа (с фильтром) для добавления в коллекцию.
///
/// Раньше жил приватным классом внутри `collection_detail_screen.dart`,
/// раздувая экран. Логика та же: клиентский фильтр по названию,
// optimistic update списка без refetch.
Future<void> showAddMediaDialog(
  BuildContext context,
  Collection collection,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => AddMediaDialog(
      collection: collection,
      mediaType: collection.type.value,
    ),
  );
}

class AddMediaDialog extends ConsumerStatefulWidget {
  const new({
    required this.collection,
    required this.mediaType,
    super.key,
  });

  final Collection collection;
  final String mediaType;

  @override
  ConsumerState<AddMediaDialog> createState() => _AddMediaDialogState();
}

class _AddMediaDialogState extends ConsumerState<AddMediaDialog> {
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
    final l = context.l10n;
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
                error: (e, _) => Text(
                  e is Failure ? e.message : e.toString(),
                ),
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
                        leading: Icon(
                          media.type == MediaType.audio
                              ? Icons.music_note
                              : Icons.movie,
                        ),
                        title: Text(media.title),
                        onTap: _adding ? null : () => _add(media),
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
    final l = context.l10n;
    setState(() => _adding = true);
    final result = await ref
        .read(collectionsRepositoryProvider)
        .addCollectionItem(widget.collection.id, media.id);
    if (!mounted) return;
    setState(() => _adding = false);
    result.fold(
      (failure) {
        showErrorSnackBar(context, l.failedToAdd(failure.message));
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
