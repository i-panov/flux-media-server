import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/media_image_url.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/video/presentation/widgets/source_link_row.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Metadata + action buttons for a video. Stateless presentation: parent
/// (VideoDetailScreen) owns any stateful side effects (e.g. cover-upload
/// spinner) and passes them through callbacks.
///
/// Панель намеренно на фиксированной тёмной подложке (экран задаёт
/// `Colors.black87` в обеих темах), поэтому текст — захардкоженные белые
/// оттенки, а не `colorScheme`: в светлой теме `onSurface` был бы тёмным
/// и стал невидимым. Контраст пар: белый/70%/60% на near-black — от ~5:1
/// и выше при требовании 4.5:1; акцент ссылки — lightBlueAccent.
class VideoDetailsPanel extends ConsumerWidget {
  const new({
    required this.media,
    this.onChangeCover,
    this.onEditMetadata,
    this.onDelete,
    this.onToggleFavorite,
    this.onAddToCollection,
    this.onDownload,
    this.onAddToQueue,
    this.onPlay,
    this.onExtractAudio,
    this.onCancelExtract,
    this.onOpenExtractedAudio,
    this.isExtracting = false,
    this.linkLoading = false,
    super.key,
  });

  final Media media;
  final Future<void> Function()? onChangeCover;
  final Future<void> Function()? onEditMetadata;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onToggleFavorite;
  final Future<void> Function()? onAddToCollection;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onAddToQueue;
  final Future<void> Function()? onPlay;

  /// Запустить извлечение аудио (связки ещё нет).
  final Future<void> Function()? onExtractAudio;

  /// Отменить летящий джоб извлечения. Показывается вместо запуска,
  /// пока [isExtracting] — долгую операцию должно быть чем прервать.
  final Future<void> Function()? onCancelExtract;

  /// Перейти к уже извлечённому треку. Ровно один из двух колбэков
  /// задаёт родитель: либо извлекаем, либо открываем готовое.
  final Future<void> Function()? onOpenExtractedAudio;

  /// Джоб извлечения в полёте: кнопка превращается в отмену.
  final bool isExtracting;

  /// Связка ещё грузится: извлечение недоступно (нельзя решать вслепую),
  /// кнопка заблокирована. Ошибка чтения связки — НЕ блокер: сервер
  /// перепроверит её в POST, поэтому onExtractAudio остаётся.
  final bool linkLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final favoriteState = ref.watch(favoriteToggleProvider(media.id));
    final isFavorite = favoriteState.value;
    final downloadState = ref.watch(downloadStateProvider(media.id));

    final downloadProgress = switch (downloadState) {
      DownloadDownloading(:final progress) => progress,
      _ => 0.0,
    };
    final isDownloading = downloadState is DownloadDownloading;
    final hasCover = media.coverUrl != null && media.coverUrl!.isNotEmpty;
    final baseUrl = ref.watch(baseUrlProvider);
    final coverUrl = buildMediaImageUrl(
      baseUrl: baseUrl,
      mediaId: media.id,
      kind: hasCover ? MediaImageKind.cover : MediaImageKind.thumb,
      cacheBust: media.updatedAt?.millisecondsSinceEpoch,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCover) ...[
            Semantics(
              label: l.coverImage,
              image: true,
              child: AuthNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                height: 200,
                width: double.infinity,
                // Состояния загрузки/ошибки из семантики исключены: иначе
                // скринридер анонсировал бы спиннер и иконку поверх метки
                // «Обложка».
                placeholder: (_, _) => const ExcludeSemantics(
                  child: SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                errorWidget: (_, _, _) => const ExcludeSemantics(
                  child: SizedBox(
                    height: 200,
                    child: Center(child: Icon(Icons.broken_image, size: 64)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Semantics(
            header: true,
            child: Text(
              media.title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          // Подзаголовок — только год: тип («video») на экране видео
          // избыточен, контекст и так ясен.
          if (hasMediaYear(media.year)) ...[
            const SizedBox(height: 8),
            Text(
              '${media.year}',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Colors.white70),
            ),
          ],
          if (media.artists.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              media.artists.map((a) => a.name).join(', '),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
          ],
          if (media.album != null && media.album!.isNotEmpty) ...[
            Text(
              media.album!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
          ],
          if (media.genre != null && media.genre!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Chip(
              label: Text(
                media.genre!,
                style: const TextStyle(color: Colors.white),
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white24,
            ),
          ],
          if (media.description != null) ...[
            const SizedBox(height: 16),
            Text(
              media.description!,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (media.duration != null && media.duration! > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${l.duration}: '
              '${Duration(seconds: media.duration!).formatted}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
          ],
          if (media.sourceUrl != null && media.sourceUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            SourceLinkRow(url: media.sourceUrl!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: l.play,
              child: FilledButton.icon(
                onPressed: onPlay == null ? null : () => onPlay!.call(),
                icon: const Icon(Icons.play_arrow),
                label: Text(l.play),
              ),
            ),
          ),
          if (onOpenExtractedAudio != null || onExtractAudio != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: onOpenExtractedAudio != null
                  ? Tooltip(
                      message: l.openAudioTrack,
                      child: OutlinedButton.icon(
                        onPressed: () => onOpenExtractedAudio!.call(),
                        icon: const Icon(Icons.audio_file_outlined),
                        label: Text(l.openAudioTrack),
                      ),
                    )
                  : isExtracting
                  ? Tooltip(
                      message: l.extractCancelled,
                      child: OutlinedButton.icon(
                        onPressed: () => onCancelExtract?.call(),
                        icon: const Icon(Icons.close),
                        label: Text(l.extractingAudio),
                      ),
                    )
                  : Tooltip(
                      message: l.extractAudio,
                      child: OutlinedButton.icon(
                        onPressed: linkLoading
                            ? null
                            : () => onExtractAudio?.call(),
                        icon: const Icon(Icons.music_note_outlined),
                        label: Text(l.extractAudio),
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 12),
          // Три быстрых действия — только иконки: текстовые кнопки
          // не влезали в ширину смартфона, надписи переносились.
          // Discoverability — через tooltip (он же семантический лейбл
          // для скринридера, как в media_card/audio_track_row): тултип
          // называет ДЕЙСТВИЕ тапа, а не состояние.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l.favorites,
                onPressed: isFavorite == null
                    ? null
                    : onToggleFavorite == null
                    ? null
                    : () => onToggleFavorite?.call(),
                icon: Icon(
                  (isFavorite ?? false)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: isFavorite == null
                      // Первичная загрузка состояния: приглушённый
                      // серый вместо мигания «не избранное» (как в
                      // мини-плеере, но под тёмную подложку панели).
                      ? Colors.white38
                      : (isFavorite ? Colors.red : Colors.white),
                ),
              ),
              IconButton(
                tooltip: l.myCollections,
                onPressed: () => onAddToCollection?.call(),
                icon: const Icon(Icons.add_to_queue, color: Colors.white),
              ),
              IconButton(
                tooltip: isDownloading
                    ? l.cancel
                    : downloadState is DownloadDownloaded
                    ? l.downloaded
                    : downloadState is DownloadError
                    ? l.errorLabel
                    : l.download,
                onPressed: () => onDownload?.call(),
                icon: isDownloading
                    ? ExcludeSemantics(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: downloadProgress > 0
                                ? downloadProgress
                                : null,
                          ),
                        ),
                      )
                    : downloadState is DownloadDownloaded
                    ? const Icon(
                        Icons.check_circle,
                        // Белый вместо primary: primary на near-black
                        // подложке не дотягивает до контраста 4.5:1.
                        color: Colors.white,
                      )
                    : downloadState is DownloadError
                    ? const Icon(Icons.error_outline, color: Colors.white)
                    : const Icon(Icons.cloud_download, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: l.addToQueue,
              child: OutlinedButton.icon(
                onPressed: () => onAddToQueue?.call(),
                icon: const Icon(Icons.queue_music_outlined),
                label: Text(l.addToQueue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
