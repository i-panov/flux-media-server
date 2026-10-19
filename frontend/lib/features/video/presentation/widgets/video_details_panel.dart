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
/// и выше при требовании 4.5:1; приглушённый 38% — только для
/// заблокированных действий.
class VideoDetailsPanel extends ConsumerWidget {
  const new({
    required this.media,
    this.onChangeCover,
    this.onEditMetadata,
    this.onDelete,
    this.onToggleFavorite,
    this.onAddToCollection,
    this.onDownload,
    this.onSaveToFiles,
    this.onAddToQueue,
    this.onExtractAudio,
    this.onCancelExtract,
    this.onOpenExtractedAudio,
    this.isExtracting = false,
    this.isUploadingCover = false,
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
  final Future<void> Function()? onSaveToFiles;
  final Future<void> Function()? onAddToQueue;

  /// Запустить извлечение аудио (связки ещё нет).
  final Future<void> Function()? onExtractAudio;

  /// Отменить летящий джоб извлечения. Показывается рядом с извлечением,
  /// пока [isExtracting] — долгую операцию должно быть чем прервать.
  final Future<void> Function()? onCancelExtract;

  /// Перейти к уже извлечённому треку. Ровно один из двух колбэков
  /// задаёт родитель: либо извлекаем, либо открываем готовое.
  final Future<void> Function()? onOpenExtractedAudio;

  /// Джоб извлечения в полёте: действие превращается в отмену.
  final bool isExtracting;

  /// Загрузка новой обложки: действие заблокировано, пока летит файл.
  final bool isUploadingCover;

  /// Связка ещё грузится: извлечение недоступно (нельзя решать вслепую),
  /// действие заблокировано. Ошибка чтения связки — НЕ блокер: сервер
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

    // Первичная загрузка состояния избранного: приглушённый красный
    // вместо мигания «не избранное» (как в мини-плеере, но под тёмную
    // подложку панели).
    final favoriteColor = switch (isFavorite) {
      null => Colors.white38,
      true => Colors.red,
      false => Colors.white,
    };

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
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          // Подзаголовок — только год: тип («video») на экране видео
          // избыточен, контекст и так ясен.
          if (hasMediaYear(media.year)) ...[
            const SizedBox(height: 8),
            Text(
              '${media.year}',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
          ],
          if (media.artists.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              media.artists.map((a) => a.name).join(', '),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
          if (media.album != null && media.album!.isNotEmpty) ...[
            Text(
              media.album!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          ],
          if (media.sourceUrl != null && media.sourceUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            SourceLinkRow(url: media.sourceUrl!),
          ],
          const SizedBox(height: 24),
          // Единый вертикальный список действий. Раньше действия были
          // смесью текстовых кнопок во всю ширину и голых иконок в ряд
          // без подписей: часть читалась по надписи, часть — только по
          // иконке, и единого вида не было. Список с иконкой И текстом
          // убирает вопрос «что это за кнопка».
          //
          // Кнопки play здесь больше нет: она живёт полупрозрачным
          // треугольником поверх превью — так она видна всегда и
          // относится к тому, что запускает.
          _ActionRow(
            icon: (isFavorite ?? false)
                ? Icons.favorite
                : Icons.favorite_border,
            iconColor: favoriteColor,
            label: l.favorites,
            onPressed: isFavorite == null || onToggleFavorite == null
                ? null
                : () => onToggleFavorite?.call(),
          ),
          _ActionRow(
            icon: Icons.playlist_add,
            label: l.myCollections,
            onPressed: onAddToCollection == null
                ? null
                : () => onAddToCollection!.call(),
          ),
          if (onAddToQueue != null)
            _ActionRow(
              icon: Icons.queue_music,
              label: l.addToQueue,
              onPressed: () => onAddToQueue!.call(),
            ),
          if (onOpenExtractedAudio != null)
            _ActionRow(
              icon: Icons.audio_file_outlined,
              label: l.openAudioTrack,
              onPressed: () => onOpenExtractedAudio!.call(),
            )
          else if (onExtractAudio != null)
            _ActionRow(
              // Пока джоб летит — иконка «в работе», а НЕ крестик: крестик
              // читается как отмена, а отмена живёт отдельной строкой
              // ниже, и два «отменяющих» значка в одном списке путают.
              icon: isExtracting
                  ? Icons.hourglass_empty
                  : Icons.music_note_outlined,
              label: isExtracting ? l.extractingAudio : l.extractAudio,
              // Пока летит джоб — заблокировано: второй POST на
              // извлечение сервер всё равно отобьёт. Связка ещё грузится —
              // решать вслепую нельзя, но ошибка чтения связи не
              // блокирует: сервер перепроверит её в POST.
              onPressed: linkLoading || isExtracting
                  ? null
                  : () => onExtractAudio?.call(),
            ),
          // Отмена — только пока джоб летит: до старта и после него
          // отменять нечего, а строка «Отменить» рядом с готовым действием
          // только путает.
          if (onCancelExtract != null && isExtracting)
            _ActionRow(
              icon: Icons.cancel_outlined,
              label: l.cancelExtraction,
              onPressed: () => onCancelExtract!.call(),
            ),
          _ActionRow(
            icon: downloadIcon(downloadState),
            label: downloadLabel(l, downloadState),
            onPressed: onDownload == null ? null : () => onDownload!.call(),
            trailing: isDownloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: downloadProgress > 0 ? downloadProgress : null,
                    ),
                  )
                : null,
          ),
          if (onSaveToFiles != null)
            _ActionRow(
              icon: Icons.file_download,
              label: l.saveFile,
              onPressed: () => onSaveToFiles!.call(),
            ),
          if (onChangeCover != null)
            _ActionRow(
              icon: Icons.image,
              label: isUploadingCover ? l.uploadingCover : l.changeCover,
              onPressed: isUploadingCover
                  ? null
                  : () => onChangeCover!.call(),
            ),
          if (onEditMetadata != null)
            _ActionRow(
              icon: Icons.edit,
              label: l.edit,
              onPressed: () => onEditMetadata!.call(),
            ),
          if (onDelete != null)
            _ActionRow(
              icon: Icons.delete_outline,
              label: l.delete,
              color: Colors.red,
              onPressed: () => onDelete!.call(),
            ),
        ],
      ),
    );
  }
}

/// Строка действия в общем списке: иконка + подпись + справа индикатор
/// прогресса (у загрузки) и шеврон.
class _ActionRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
    this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final foreground = onPressed == null ? Colors.white38 : color ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        // Скринридер должен объявлять строку как КНОПКУ: без этого
        // InkWell читается как обычный текст, и «В офлайн» звучит
        // строкой, а не действием.
        button: true,
        enabled: onPressed != null,
        label: label,
        child: ExcludeSemantics(
          // Текст и иконка объявлены самой Semantics-меткой выше —
          // иначе скринридер прочитал бы подпись дважды.
          child: Material(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor ?? foreground),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(color: foreground, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Иконка действия «в офлайн» по состоянию загрузки.
///
/// Иконка отражает ДЕЙСТВИЕ тапа: пока идёт загрузка, тап отменяет её —
/// значит, и значок должен быть отменой, а не «облако» (оно читалось
/// бы как «скачать», хотя тап уже отменяет). Прогресс показывает спиннер
/// справа.
IconData downloadIcon(DownloadState downloadState) {
  return switch (downloadState) {
    DownloadDownloading() => Icons.close,
    DownloadDownloaded() => Icons.check_circle,
    DownloadError() => Icons.error_outline,
    _ => Icons.cloud_download,
  };
}

/// Подпись действия «в офлайн» по состоянию загрузки.
String downloadLabel(AppLocalizations l, DownloadState downloadState) {
  return switch (downloadState) {
    DownloadDownloading() => l.cancel,
    DownloadDownloaded() => l.downloaded,
    DownloadError() => l.errorLabel,
    _ => l.saveOffline,
  };
}
