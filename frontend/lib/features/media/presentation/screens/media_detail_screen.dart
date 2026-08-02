import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/widgets/audio_placeholder.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_detail_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

@RoutePage()
class MediaDetailScreen extends ConsumerStatefulWidget {
  const MediaDetailScreen({super.key, required this.mediaId});

  final int mediaId;

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(mediaDetailProvider(widget.mediaId).notifier).load(widget.mediaId);
    _initFavoriteState();
  }

  Future<void> _initFavoriteState() async {
    final favorites = await ref.read(favoritesProvider(null).future);
    final isFav = favorites.any((f) => f.mediaId == widget.mediaId);
    if (mounted) {
      ref.read(favoriteToggleProvider(widget.mediaId).notifier).init(isFav);
    }
  }

  String _imageUrl() {
    final baseUrl = ref.read(baseUrlProvider);
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
      loaded: (m) => m,
      orElse: () => null,
    );
    if (media == null) return '$baseUrl/media/${widget.mediaId}/thumb';
    // Use embedded cover if available, thumbnail otherwise
    if (media.coverUrl != null && media.coverUrl!.isNotEmpty) {
      return '$baseUrl/media/${media.id}/cover';
    }
    return '$baseUrl/media/${media.id}/thumb';
  }

  bool _hasCover() {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
      loaded: (m) => m,
      orElse: () => null,
    );
    return media != null && media.coverUrl != null && media.coverUrl!.isNotEmpty;
  }

  Future<void> _toggleFavorite() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
      loaded: (m) => m,
      orElse: () => null,
    );
    if (media == null) return;

    final type = media.type; // 'video' or 'audio'
    await ref.read(favoriteToggleProvider(widget.mediaId).notifier).toggle(
          widget.mediaId,
          type,
        );
  }

  Future<void> _addToCollection() async {
    await showAddToCollectionDialog(context, ref, widget.mediaId);
  }

  Future<void> _download() async {
    final media = ref.read(mediaDetailProvider(widget.mediaId)).maybeWhen(
      loaded: (m) => m,
      orElse: () => null,
    );
    if (media == null) return;

    final downloadState = ref.read(downloadNotifierProvider(widget.mediaId));

    if (downloadState is DownloadDownloaded) {
      await ref.read(downloadNotifierProvider(widget.mediaId).notifier).remove(widget.mediaId);
    } else if (downloadState is! DownloadDownloading) {
      await ref.read(downloadNotifierProvider(widget.mediaId).notifier).download(media);

      if (!mounted) return;
      final newState = ref.read(downloadNotifierProvider(widget.mediaId));
      if (newState is DownloadError && mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.errorLabel}: ${newState.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaDetailProvider(widget.mediaId));
    final favoriteState = ref.watch(favoriteToggleProvider(widget.mediaId));
    final downloadState = ref.watch(downloadNotifierProvider(widget.mediaId));

    final isFavorite = favoriteState.valueOrNull ?? false;

    final downloadProgress = switch (downloadState) {
      DownloadDownloading(:final progress) => progress,
      _ => 0.0,
    };
    final isDownloading = downloadState is DownloadDownloading;

    return Scaffold(
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (media) => Stack(
          children: [
            // Backdrop image / placeholder
            if (_hasCover())
              Hero(
                tag: 'media-thumb-${media.id}',
                child: AuthNetworkImage(
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
                ),
              )
            else if (media.type == 'audio')
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: [0.5, 1.0],
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
                          '${media.year} · ${media.type}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.white70),
                        ),
                        if (media.artist != null &&
                            media.artist!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            media.artist!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ],
                        if (media.album != null &&
                            media.album!.isNotEmpty) ...[
                          Text(
                            media.album!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white60),
                          ),
                        ],
                        if (media.genre != null &&
                            media.genre!.isNotEmpty) ...[
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
                        if (media.duration != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${l.duration}: ${Duration(seconds: media.duration!).formatted}',
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
                                if (media.type == 'audio') {
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
                                  onPressed: _toggleFavorite,
                                  icon: Icon(
                                    isFavorite ? Icons.favorite : Icons.favorite_border,
                                    color: isFavorite ? Colors.red : null,
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
                                message: l.download,
                                child: OutlinedButton.icon(
                                  onPressed: isDownloading
                                      ? null
                                      : _download,
                                  icon: isDownloading
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            value: downloadProgress > 0 ? downloadProgress : null,
                                          ),
                                        )
                                      : Icon(
                                          downloadState is DownloadDownloaded
                                              ? Icons.check_circle
                                              : Icons.cloud_download,
                                          color: downloadState is DownloadDownloaded
                                              ? Theme.of(context).colorScheme.primary
                                              : null,
                                        ),
                                  label: Text(
                                    switch (downloadState) {
                                      DownloadDownloading(:final progress) =>
                                          progress > 0 ? '${(progress * 100).toInt()}%' : l.downloading,
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
            Positioned(
              top: 8,
              left: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.maybePop(),
                  tooltip: l.mediaDetail,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      showEditMetadataDialog(context, ref, media),
                  tooltip: l.edit,
                ),
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
