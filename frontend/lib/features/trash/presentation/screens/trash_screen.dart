import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/core/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/trash/presentation/providers/trash_providers.dart';
import 'package:flux_media_server/features/trash/presentation/utils/refresh.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Корзина: удалённые медиа и коллекции плоским списком (вложенности
/// внутри нет). Восстановить — вернуть как было, удалить навсегда —
/// стереть без возврата (файлы медиа — с диска).
@RoutePage()
class TrashScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  /// Id в полёте: двойной тап не шлёт второй запрос, кнопки гаснут.
  final Set<String> _inFlight = {};

  String _key(String kind, int id) => '$kind:$id';

  bool _busy(String key) => _inFlight.contains(key);

  Future<void> _guarded(String key, Future<void> Function() action) async {
    if (!_inFlight.add(key)) return;
    try {
      await action();
    } finally {
      if (mounted) setState(() => _inFlight.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final trash = ref.watch(trashProvider);
    // Кнопка очистки гаснет на пустой корзине (тапать не по чему).
    final isEmpty = trash.value?.isEmpty ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.trash),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: l.emptyTrash,
            onPressed: isEmpty
                ? null
                : () => _guarded('empty', _confirmEmpty),
          ),
        ],
      ),
      body: trash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(
          message: e.toString(),
          onRetry: () => ref.invalidate(trashProvider),
        ),
        data: (contents) {
          if (contents.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.delete_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(l.trashEmpty),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(trashProvider),
            child: ListView(
              children: [
                for (final c in contents.collections)
                  _TrashTile(
                    icon: Icons.folder_outlined,
                    title: c.name,
                    busy: _busy(_key('c', c.id)),
                    onRestore: () => _guarded(
                      _key('c', c.id),
                      () => _restoreCollection(c),
                    ),
                    onPurge: () => _guarded(
                      _key('c', c.id),
                      () => _confirmPurgeCollection(c),
                    ),
                  ),
                for (final m in contents.media)
                  _TrashTile(
                    icon: m.type == MediaType.audio
                        ? Icons.music_note
                        : Icons.movie_outlined,
                    title: m.title,
                    busy: _busy(_key('m', m.id)),
                    onRestore: () => _guarded(
                      _key('m', m.id),
                      () => _restoreMedia(m),
                    ),
                    onPurge: () => _guarded(
                      _key('m', m.id),
                      () => _confirmPurgeMedia(m),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _restoreCollection(Collection c) async {
    final l = AppLocalizations.of(context)!;
    final result = await ref
        .read(trashRepositoryProvider)
        .restoreCollection(c.id);
    if (!context.mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        refreshAfterTrashChange(ref);
        showTextSnackBar(context, l.restored);
      },
    );
  }

  Future<void> _confirmPurgeCollection(Collection c) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteForever),
        content: Text(l.purgeCollectionConfirm(c.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deleteForever),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(trashRepositoryProvider)
        .purgeCollection(c.id);
    if (!context.mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        refreshAfterTrashChange(ref);
        showTextSnackBar(context, l.purged);
      },
    );
  }

  Future<void> _restoreMedia(Media m) async {
    final l = AppLocalizations.of(context)!;
    final result = await ref.read(trashRepositoryProvider).restoreMedia(m.id);
    if (!context.mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        refreshAfterTrashChange(ref);
        showTextSnackBar(context, l.restored);
      },
    );
  }

  Future<void> _confirmPurgeMedia(Media m) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteForever),
        content: Text(l.purgeMediaConfirm(m.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deleteForever),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref.read(trashRepositoryProvider).purgeMedia(m.id);
    if (!context.mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        // Офлайн-копия снесённого файла — призрак: вычищаем сразу,
        // иначе в офлайн-списке останется недоступный элемент.
        unawaited(ref.read(offlineCacheServiceProvider).remove(m.id));
        refreshAfterTrashChange(ref);
        showTextSnackBar(context, l.purged);
      },
    );
  }

  Future<void> _confirmEmpty() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.emptyTrash),
        content: Text(l.emptyTrashConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deleteForever),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Id сносимых медиа — из состояния ДО запроса: после empty
    // список уже пуст, чистить кеш будет не по чему.
    final trashedIds =
        ref.read(trashProvider).value?.media.map((m) => m.id).toList() ??
        const <int>[];
    final result = await ref.read(trashRepositoryProvider).emptyTrash();
    if (!context.mounted) return;
    result.fold(
      (failure) => showErrorSnackBar(context, failure.message),
      (_) {
        // Призраки в офлайне: empty сносит файлы пачкой, одиночный
        // purge чистит свой (выше), здесь — все разом.
        for (final id in trashedIds) {
          unawaited(ref.read(offlineCacheServiceProvider).remove(id));
        }
        refreshAfterTrashChange(ref);
        showTextSnackBar(context, l.trashEmptied);
      },
    );
  }
}

class _TrashTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.busy,
    required this.onRestore,
    required this.onPurge,
  });

  final IconData icon;
  final String title;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListTile(
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.restore_outlined),
              tooltip: l.restore,
              onPressed: onRestore,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: l.deleteForever,
              onPressed: onPurge,
            ),
          ],
        ],
      ),
    );
  }
}
