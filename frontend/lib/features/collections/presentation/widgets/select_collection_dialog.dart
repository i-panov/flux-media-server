import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/utils/collection_tree.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/create_collection_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Выбор коллекции для пачки файлов.
///
/// Отдельный диалог, а не перенос: цель здесь — «положить всё это в
/// коллекцию», а перенос умеет ещё «в корень» и исключения, которые
/// при загрузке неуместны.
///
/// Возвращает выбранную коллекцию или null (отмена).
Future<Collection?> showSelectCollectionDialog(
  BuildContext context,
  WidgetRef ref, {
  required MediaType type,
}) {
  return showDialog<Collection>(
    context: context,
    builder: (ctx) => _SelectCollectionDialog(type: type),
  );
}

class _SelectCollectionDialog extends ConsumerStatefulWidget {
  const new({required this.type});

  final MediaType type;

  @override
  ConsumerState<_SelectCollectionDialog> createState() =>
      _SelectCollectionDialogState();
}

class _SelectCollectionDialogState
    extends ConsumerState<_SelectCollectionDialog> {
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    final created = await showCreateCollectionDialog(
      context,
      type: widget.type,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    // null — отмена; созданную коллекцию сразу выбираем.
    if (created != null) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(collectionsProvider);
    return AlertDialog(
      title: Text(l.selectCollection),
      content: SizedBox(
        width: double.maxFinite,
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetryView(
            message: e.toString(),
            onRetry: () => ref.invalidate(collectionsProvider),
          ),
          data: (all) {
            final rows = flattenTree(
              buildCollectionTree(
                all.where((c) => c.type == widget.type).toList(),
              ),
            );
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: Text(l.newCollection),
                    enabled: !_creating,
                    onTap: _creating ? null : _create,
                  ),
                  if (rows.isEmpty) Text(l.noCollections),
                  for (final r in rows)
                    ListTile(
                      contentPadding: EdgeInsets.only(
                        // Кламп: глубина из битых данных не уезжает за край.
                        left: 16.0 + r.depth.clamp(0, 5) * 24.0,
                        right: 16,
                      ),
                      leading: Icon(
                        r.depth == 0
                            ? Icons.folder_outlined
                            : Icons.subdirectory_arrow_right,
                      ),
                      title: Text(r.collection.name),
                      onTap: () => Navigator.pop(context, r.collection),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
