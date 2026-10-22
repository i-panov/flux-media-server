import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/select_collection_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Кладёт выделенные медиа в коллекцию: выбор коллекции + один запрос.
///
/// Групповая операция: загруженный сезон раскладывается по коллекции
/// одним действием, а не по одному файлу.
Future<void> addSelectionToCollection(
  BuildContext context,
  WidgetRef ref, {
  required List<int> mediaIds,
  required MediaType type,
}) async {
  if (mediaIds.isEmpty) return;
  final collection = await showSelectCollectionDialog(
    context,
    ref,
    type: type,
  );
  if (collection == null || !context.mounted) return;

  final result = await ref
      .read(collectionsRepositoryProvider)
      .addCollectionItemsBulk(collection.id, mediaIds);
  if (!context.mounted) return;
  final l = AppLocalizations.of(context)!;
  result.fold(
    (failure) => showErrorSnackBar(context, failure.message),
    (bulk) => showSuccessSnackBar(
      context,
      l.bulkAddedToCollection(
        collection.name,
        bulk.changedCount,
        bulk.skipped.length,
      ),
    ),
  );
}

/// Переносит выделенные медиа из одной коллекции в другую.
///
/// Отдельная операция, а не «добавить»: элемент из исходной коллекции
/// должен из неё уйти, иначе он останется в обеих.
Future<void> moveSelectionToCollection(
  BuildContext context,
  WidgetRef ref, {
  required int sourceCollectionId,
  required List<int> mediaIds,
  required MediaType type,
}) async {
  if (mediaIds.isEmpty) return;
  final collection = await showSelectCollectionDialog(
    context,
    ref,
    type: type,
  );
  if (collection == null || !context.mounted) return;
  if (collection.id == sourceCollectionId) return;

  final result = await ref
      .read(collectionsRepositoryProvider)
      .moveCollectionItemsBulk(sourceCollectionId, collection.id, mediaIds);
  if (!context.mounted) return;
  final l = AppLocalizations.of(context)!;
  result.fold(
    (failure) => showErrorSnackBar(context, failure.message),
    (bulk) => showSuccessSnackBar(
      context,
      l.bulkMovedToCollection(
        collection.name,
        bulk.changedCount,
        bulk.skipped.length,
      ),
    ),
  );
}
