import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_cover.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Выбор файла и загрузка новой обложки медиа.
///
/// Общая точка для выпадающего меню трека и detail-экрана.
/// [onUploadStarted]/[onUploadFinished] — для индикации загрузки
/// в UI, которому нужен спиннер (detail-экран).
Future<void> changeMediaCover(
  BuildContext context,
  WidgetRef ref,
  int mediaId, {
  bool Function()? isCancelled,
  VoidCallback? onUploadStarted,
  VoidCallback? onUploadFinished,
}) async {
  final l = AppLocalizations.of(context)!;
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );

  if (result == null || result.files.isEmpty) return;
  final file = result.files.first;
  if (file.path == null) return;

  onUploadStarted?.call();
  try {
    final r = await ref.read(uploadCoverProvider)(
      UploadCoverParams(
        mediaId: mediaId,
        filePath: file.path!,
        isCancelled: isCancelled,
      ),
    );

    if (!context.mounted) return;

    r.fold(
      (failure) {
        if (failure is UploadCancelledFailure) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.failedToAdd(failure.message)),
            backgroundColor: Colors.red,
          ),
        );
      },
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.uploadSuccess),
            backgroundColor: Colors.green,
          ),
        );
        // Серверный updatedAt даёт честный cache-buster для обложки —
        // тихий перезапрос деталей без мигания спиннером.
        unawaited(ref.read(mediaDetailProvider(mediaId).notifier).refresh());
        refreshMediaLists(ref);
      },
    );
  } finally {
    onUploadFinished?.call();
  }
}

/// Диалог подтверждения и удаление медиа.
///
/// Общая точка для выпадающего меню трека и detail-экрана.
/// [popOnSuccess] — закрыть текущий экран после удаления.
Future<void> deleteMediaWithConfirm(
  BuildContext context,
  WidgetRef ref,
  int mediaId, {
  bool popOnSuccess = false,
}) async {
  final l = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.delete),
      content: Text(l.deleteMediaConfirmation),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final result = await ref.read(deleteMediaProvider)(mediaId);
  if (!context.mounted) return;

  result.fold(
    (failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.errorLabel}: ${failure.message}'),
          backgroundColor: Colors.red,
        ),
      );
    },
    (_) {
      refreshMediaLists(ref);
      if (popOnSuccess) Navigator.of(context).maybePop();
    },
  );
}
