import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/scaffold_messenger.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Общий хелпер переключения загрузки трека/видео: скачать или удалить.
///
/// Дублировался в audio_screen, artist_page и video_screen.
///
/// Фидбеки показываются здесь — единая точка, общая для всех экранов:
/// начало, успех, отмена и ошибка скачивания.
Future<void> toggleDownload(
  WidgetRef ref, {
  required int mediaId,
  required String mediaType,
}) async {
  final downloadState = ref.read(downloadNotifierProvider(mediaId));
  if (downloadState is DownloadDownloaded) {
    await ref.read(downloadNotifierProvider(mediaId).notifier).remove(mediaId);
    return;
  }
  if (downloadState is DownloadDownloading) {
    // Повторный тап во время загрузки отменяет её.
    await ref.read(downloadNotifierProvider(mediaId).notifier).cancel(mediaId);
    _showFeedback(_messengerMessage((l) => l.downloadCancelled));
    return;
  }

  var media = _findInLoadedPages(ref, mediaId, mediaType);
  if (media == null) {
    // Трек вне загруженных страниц пагинации — берём детали с сервера.
    final result =
        await ref.read(mediaRepositoryProvider).getMediaDetail(mediaId);
    media = result.fold((_) => null, (m) => m);
  }
  // Фолбэк-заглушки больше нет: без реальных метаданных не скачиваем,
  // иначе в кеш попадут пустые записи.
  if (media == null) return;

  _showFeedback(_messengerMessage((l) => l.downloadStarted));
  await ref.read(downloadNotifierProvider(mediaId).notifier).download(media);

  // После завершения download() состояние не может быть downloading:
  // notifier сам выставляет downloaded/idle/error.
  final state = ref.read(downloadNotifierProvider(mediaId));
  if (state is DownloadDownloaded) {
    _showFeedback(_messengerMessage((l) => l.downloaded));
  } else if (state is DownloadError) {
    _showFeedback(
      _messengerMessage((l) => l.downloadFailed(state.message)),
      isError: true,
    );
  }
}

Media? _findInLoadedPages(WidgetRef ref, int mediaId, String mediaType) {
  final mediaList = ref.read(mediaListProvider(mediaType)).valueOrNull;
  if (mediaList == null) return null;
  for (final m in mediaList.items) {
    if (m.id == mediaId) return m;
  }
  return null;
}

/// Считывает локализации через контекст ScaffoldMessenger: у
/// [scaffoldMessengerKey] нет собственного BuildContext, но его State
/// живёт внутри MaterialApp и видит Localizations.
String? _messengerMessage(String Function(AppLocalizations) resolve) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return null;
  final l = AppLocalizations.of(messenger.context);
  if (l == null) return null;
  return resolve(l);
}

void _showFeedback(String? message, {bool isError = false}) {
  if (message == null) return;
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : null,
    ),
  );
}
