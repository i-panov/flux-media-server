import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/utils/collection_tree.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Диалог выбора целевой коллекции для перемещения.
///
/// Возвращает id цели, [moveToRootId] — пункт «В корень», null — отмена.
const moveToRootId = -1;
///
/// [excludeIds] — запрещённые цели: при переносе коллекции это она сама
/// и её поддерево (иначе цикл), при переносе элемента — пусто.
/// [allowRoot] — пункт «В корень» (только перенос коллекции).
/// Показываются только коллекции нужного [type]: сезоны сериала нельзя
/// уронить в музыкальную подборку.
Future<int?> showMoveToCollectionDialog(
  BuildContext context,
  WidgetRef ref, {
  required MediaType type,
  Set<int> excludeIds = const {},
  bool allowRoot = false,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _MoveDialog(
      type: type,
      excludeIds: excludeIds,
      allowRoot: allowRoot,
    ),
  );
}

class _MoveDialog extends ConsumerWidget {
  const new({
    required this.type,
    required this.excludeIds,
    required this.allowRoot,
  });

  final MediaType type;
  final Set<int> excludeIds;
  final bool allowRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(collectionsProvider);
    return AlertDialog(
      title: Text(l.moveToCollection),
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
                all.where((c) => c.type == type).toList(),
              ),
            ).where((r) => !excludeIds.contains(r.collection.id)).toList();
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (allowRoot)
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: Text(l.moveToRoot),
                      onTap: () => Navigator.pop(context, moveToRootId),
                    ),
                  if (rows.isEmpty && !allowRoot) Text(l.noCollections),
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
                      onTap: () =>
                          Navigator.pop(context, r.collection.id),
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
