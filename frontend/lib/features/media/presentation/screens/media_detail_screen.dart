import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/widgets/audio_placeholder.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_actions.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_image_url.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class MediaDetailScreen extends ConsumerStatefulWidget {
  const MediaDetailScreen({required this.mediaId, super.key});

  final int mediaId;

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  /// Идёт загрузка новой обложки (кнопка в AppBar показывает спиннер).
  bool _isUploadingCover = false;

  /// Пользователь отменил загрузку обложки повторным тапом.
  bool _coverUploadCancelled = false;

  @override
  void initState() {
    super.initState();
    // Загрузка запускается самим провайдером (build + microtask):
    // модифицировать Notifier из initState запрещено.
  }

  String _imageUrl() {
    final baseUrl = ref.read(baseUrlProvider);
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    // Cache-buster: force reload when the cover changes on the server.
    final cacheBust = media?.updatedAt?.millisecondsSinceEpoch;
    if (media == null) {
      return buildMediaImageUrl(
        baseUrl: baseUrl,
        mediaId: widget.mediaId,
        kind: MediaImageKind.thumb,
        cacheBust: cacheBust,
      );
    }
    // Use embedded cover if available, thumbnail otherwise.
    return buildMediaImageUrl(
      baseUrl: baseUrl,
      mediaId: media.id,
      kind: media.coverUrl != null && media.coverUrl!.isNotEmpty
          ? MediaImageKind.cover
          : MediaImageKind.thumb,
      cacheBust: cacheBust,
    );
  }

  bool _hasCover() {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    return media != null &&
        media.coverUrl != null &&
        media.coverUrl!.isNotEmpty;
  }

  Future<void> _toggleFavorite() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    if (media == null) return;

    await ref.read(favoriteToggleProvider(widget.mediaId).notifier).toggle();
  }

  Future<void> _addToCollection() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    final type = media?.type.value ?? 'video';
    await showAddToCollectionDialog(
      context,
      widget.mediaId,
      mediaType: type,
    );
  }

  Future<void> _changeCover() async {
    // Повторный тап во время загрузки отменяет её.
    if (_isUploadingCover) {
      setState(() => _coverUploadCancelled = true);
      return;
    }

    await changeMediaCover(
      context,
      ref,
      widget.mediaId,
      isCancelled: () => _coverUploadCancelled,
      onUploadStarted: () {
        if (mounted) {
          setState(() {
            _isUploadingCover = true;
            _coverUploadCancelled = false;
          });
        }
      },
      onUploadFinished: () {
        if (mounted) {
          setState(() {
            _isUploadingCover = false;
            _coverUploadCancelled = false;
          });
        }
      },
    );
  }

  Future<void> _download() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
          loaded: (m) => m,
          orElse: () => null,
        );
    if (media == null) return;

    final downloadState = ref.read(downloadNotifierProvider(widget.mediaId));

    if (downloadState is DownloadDownloaded) {
      await ref
          .read(downloadNotifierProvider(widget.mediaId).notifier)
          .remove(widget.mediaId);
    } else if (downloadState is DownloadDownloading) {
      // Повторный тап во время загрузки отменяет её.
      await ref
          .read(downloadNotifierProvider(widget.mediaId).notifier)
          .cancel(widget.mediaId);
    } else {
      await ref
          .read(downloadNotifierProvider(widget.mediaId).notifier)
          .download(media);

      if (!mounted) return;
      final newState = ref.read(downloadNotifierProvider(widget.mediaId));
      if (newState is DownloadError) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.errorLabel}: ${newState.message}')),
        );
      }
    }
  }

  Future<void> _delete() async {
    await deleteMediaWithConfirm(
      context,
      ref,
      widget.mediaId,
      popOnSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaDetailProvider(widget.mediaId));
    final favoriteState = ref.watch(favoriteToggleProvider(widget.mediaId));
    final downloadState = ref.watch(downloadNotifierProvider(widget.mediaId));

    // Пока ids избранного грузятся впервые (нет предыдущего значения),
    // кнопка нейтральная — без ложного «не избранное».
    final isFavorite = favoriteState.valueOrNull;

    final downloadProgress = switch (downloadState) {
      DownloadDownloading(:final progress) => progress,
      _ => 0.0,
    };
    final isDownloading = downloadState is DownloadDownloading;

    return Scaffold(
      backgroundColor: Colors.black87,
      extendBodyBehindAppBar: true,
      appBar: state.maybeWhen(
        loaded: (media) => AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.maybePop(),
            tooltip: l.mediaDetail,
          ),
          actions: [
            IconButton(
              color: Colors.white,
              // Во время загрузки кнопка превращается в отмену со
              // спиннером (загрузка обложки идёт без индикации ранее).
              icon: _isUploadingCover
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.image),
              tooltip: _isUploadingCover
                  ? l.uploadingCover
                  : l.changeCover,
              onPressed: _changeCover,
            ),
            IconButton(
              color: Colors.white,
              icon: const Icon(Icons.edit),
              onPressed: () => showEditMetadataDialog(
                context,
                ref,
                media,
              ),
              tooltip: l.edit,
            ),
            IconButton(
              color: Colors.red,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
              tooltip: l.delete,
            ),
          ],
        ),
        orElse: () => null,
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (media) => Stack(
          children: [
            // Backdrop image / placeholder
            if (_hasCover())
              AuthNetworkImage(
                imageUrl: _imageUrl(),
                fit: BoxFit.cover,
                height: 300,
                width: double.infinity,
                placeholder: (_, __) => const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const SizedBox(
                  height: 300,
                  child: Center(child: Icon(Icons.broken_image, size: 64)),
                ),
              )
            else if (media.type == MediaType.audio)
              const Center(
                child: AudioPlaceholder(size: 200),
              ),
            // Gradient overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _hasCover()
                        ? [
                            Colors.transparent,
                            Colors.black87,
                          ]
                        : [
                            Colors.black54,
                            Colors.black87,
                          ],
                    stops: _hasCover()
                        ? [0.5, 1.0]
                        : [0.0, 1.0],
                  ),
                ),
              ),
            ),
            // Content
            SingleChildScrollView(
              padding: const EdgeInsets.only(top: 200, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          () {
                            // 0 = «нет данных» на бэкенде — не показываем.
                            final parts = <String>[
                              if (hasMediaYear(media.year))
                                '${media.year}',
                              media.type.value,
                            ];
                            return parts.join(' · ');
                          }(),
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.white70),
                        ),
                        if (media.artists.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            media.artists.map((a) => a.name).join(', '),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ],
                        if (media.album != null && media.album!.isNotEmpty) ...[
                          Text(
                            media.album!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white60),
                          ),
                        ],
                        const SizedBox(height: 24),
                        // Play button
                        SizedBox(
                          width: double.infinity,
                          child: Tooltip(
                            message: l.play,
                            child: FilledButton.icon(
                              onPressed: () {
                                if (media.type == MediaType.audio) {
                                  context.router
                                      .push(AudioPlayerRoute(media: media));
                                } else {
                                  context.router
                                      .push(PlayerRoute(media: media));
                                }
                              },
                              icon: const Icon(Icons.play_arrow),
                              label: Text(l.play),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Action buttons row
                        Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: l.favorites,
                                child: OutlinedButton.icon(
                                  onPressed: isFavorite == null
                                      ? null
                                      : _toggleFavorite,
                                  icon: Icon(
                                    (isFavorite ?? false)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isFavorite == null
                                        ? null
                                        : (isFavorite ? Colors.red : null),
                                  ),
                                  label: Text(l.favorites),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Tooltip(
                                message: l.myCollections,
                                child: OutlinedButton.icon(
                                  onPressed: _addToCollection,
                                  icon: const Icon(Icons.add_to_queue),
                                  label: Text(l.myCollections),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Tooltip(
                                message: isDownloading
                                    ? l.cancel
                                    : l.download,
                                child: OutlinedButton.icon(
                                  onPressed: _download,
                                  icon: isDownloading
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            value: downloadProgress > 0
                                                ? downloadProgress
                                                : null,
                                          ),
                                        )
                                      : Icon(
                                          downloadState is DownloadDownloaded
                                              ? Icons.check_circle
                                              : Icons.cloud_download,
                                          color: downloadState
                                                  is DownloadDownloaded
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : null,
                                        ),
                                  label: Text(
                                    switch (downloadState) {
                                      DownloadDownloading(:final progress) =>
                                        progress > 0
                                            ? '${(progress * 100).toInt()}%'
                                            : l.downloading,
                                      DownloadDownloaded() => l.downloaded,
                                      DownloadError() => l.errorLabel,
                                      _ => l.download,
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: Tooltip(
                            message: l.addToQueue,
                            child: OutlinedButton.icon(
                              onPressed: () => ref
                                  .read(playQueueProvider.notifier)
                                  .enqueue(media),
                              icon: const Icon(Icons.queue_music_outlined),
                              label: Text(l.addToQueue),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        error: (message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(mediaDetailProvider(widget.mediaId).notifier)
                    .load(widget.mediaId),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
