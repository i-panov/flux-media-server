import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/media/presentation/providers/extract_controller.dart';
import 'package:flux_media_server/features/video/presentation/providers/extracted_audio_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Полный флоу извлечения аудио из видео: подтверждение → джоб → опрос →
/// фидбек. Вынесен из VideoDetailScreen, чтобы диалог → снекбар → морф
/// кнопки покрывались виджет-тестом без поднятия плеера (VideoPlayerPanel
/// требует нативный libmpv, недоступный в `flutter test`).
///
/// Возвращает трек или null. Данные (списки + связка) обновляет сам
/// контроллер на своём ref — здесь только диалог и снекбары по mounted,
/// поэтому уход с экрана посреди опроса безопасен.
Future<Media?> runExtractAudioFlow(
  WidgetRef ref,
  BuildContext context,
  int mediaId,
) async {
  final l = AppLocalizations.of(context)!;
  // Guard повторного старта: контроллер тоже дедуплицирует, но второй
  // вызов тогда показал бы второй снекбар на тот же джоб.
  if (ref.read(extractControllerProvider).isExtracting) return null;
  // Ошибка чтения связки — ретрай: сервер перепроверит её в POST,
  // а удачный GET переключит кнопку на «открыть трек».
  if (ref.read(extractedAudioProvider(mediaId)).hasError) {
    ref.invalidate(extractedAudioProvider(mediaId));
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.extractAudioConfirmTitle),
      content: Text(l.extractAudioConfirmText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.extractAudio),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  final track = await ref
      .read(extractControllerProvider.notifier)
      .start(mediaId: mediaId);
  if (!context.mounted) return null;

  // Результат — из start(), перечитывание — только флаги: провайдер
  // keepAlive (как upload), состояние между await не сбрасывается.
  final state = ref.read(extractControllerProvider);
  if (state.cancelled) {
    showTextSnackBar(context, l.extractCancelled, color: Colors.orange);
  } else if (track != null) {
    showTextSnackBar(context, l.audioExtracted, color: Colors.green);
  } else {
    // errorMessage гарантирован инвариантом выше; failedToAdd — мёртвый
    // backstop на случай будущей ветки без ошибки (см. backstop-коммент
    // у ExtractState.errorMessage про язык).
    showTextSnackBar(
      context,
      state.errorMessage != null
          ? l.extractFailed(state.errorMessage!)
          : l.failedToAdd(l.errorLabel),
      color: Colors.red,
    );
  }
  return track;
}
