import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/scaffold_messenger.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/file_export_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Общий хелпер «Скачать»: копия из офлайн-кеша в видимую пользователю
/// область (Загрузки на Android, выбранная папка на десктопе).
///
/// Пара к [toggleDownload]: та — кеш («В офлайн»), эта — файлы.
/// Если кеша нет, сначала качаем (прогресс на иконке ряда), сеть
/// при готовом кеше не трогаем. Обратного доверия нет: чужой файл
/// из пользовательской области в кеш не попадает.
Future<void> saveMediaToFiles(
  BuildContext context,
  WidgetRef ref,
  Media media,
) async {
  final l = AppLocalizations.of(context)!;
  _showFeedback(l.preparingFile);
  FileExportResult result;
  try {
    result = await ref.read(fileExportServiceProvider).exportMedia(media);
  } on FileSaverUnavailable catch (e) {
    // Канал есть, хендлера нет: без catch исключение улетело бы
    // из колбэка кнопки в необработанные и роняло зону.
    if (!context.mounted) return;
    _showFeedback(l.fileSaveFailed(e.toString()), isError: true);
    return;
  } on FileSaverUnsupported {
    if (!context.mounted) return;
    _showFeedback(l.saveNotSupported, isError: true);
    return;
  }
  if (!context.mounted) return;
  switch (result) {
    case FileExportSaved():
      _showFeedback('${l.fileSaved}: ${result.destination}', isSuccess: true);
    case FileExportCancelled():
      // Отмена диалога — не событие: прячем висевший preparingFile,
      // иначе он остаётся до следующего снекбара.
      scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    case FileExportFailed(:final message):
      final cacheError = ref
          .read(downloadsStateProvider.notifier)
          .stateOf(media.id);
      final detail = cacheError is DownloadError ? cacheError.message : message;
      _showFeedback(l.fileSaveFailed(detail), isError: true);
  }
}

/// Резолв медиа как в [toggleDownload]: сначала загруженные страницы,
/// иначе детали с сервера. Без метаданных не сохраняем.
Future<Media?> resolveMediaForExport(
  WidgetRef ref,
  int mediaId,
  String mediaType,
) async {
  final mediaList = ref.read(mediaListProvider(mediaType)).value;
  if (mediaList != null) {
    for (final m in mediaList.items) {
      if (m.id == mediaId) return m;
    }
  }
  final result = await ref
      .read(mediaRepositoryProvider)
      .getMediaDetail(mediaId);
  return await result.fold((_) async => null, (m) async => m);
}

void _showFeedback(
  String message, {
  bool isError = false,
  bool isSuccess = false,
}) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? Colors.red
          : isSuccess
          ? Colors.green
          : null,
    ),
  );
}
