import 'package:auto_route/auto_route.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/audio/presentation/utils/download_batch.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/audio_track_row.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/error_retry_view.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/track_actions_mixin.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/add_to_collection_dialog.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/usecases/update_artist_name.dart';
import 'package:flux_media_server/features/media/domain/usecases/upload_artist_cover.dart';
import 'package:flux_media_server/features/media/presentation/providers/artists_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/utils/media_actions.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/player/data/providers/play_queue_provider.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';

@RoutePage()
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({
    required this.artistId,
    required this.artistName,
    super.key,
  });

  final int artistId;
  final String artistName;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage>
    with TrackActionsMixin<ArtistPage> {
  static const _mediaType = 'audio';
  bool _downloadingAll = false;
  int _downloadedCount = 0;
  int _downloadTotal = 0;

  /// Скачивает все треки артиста пачкой.
  ///
  /// CRITICAL #20: исключение в одном треке не роняет пачку и не
  /// застреляет AppBar в «0/N» — try/finally + подсчёт ошибок; прогресс
  /// обновляется живьём после каждого трека.
  Future<void> _downloadAll(List<Media> tracks) async {
    if (tracks.isEmpty) return;

    setState(() {
      _downloadingAll = true;
      _downloadedCount = 0;
      _downloadTotal = 0;
    });

    var downloaded = 0;
    var failed = 0;
    try {
      // Уже скачанные не входят ни в total, ни в счётчик.
      final pending = await filterUncachedTracks(
        tracks,
        (id) => ref.read(offlineCacheServiceProvider).isCached(id),
      );
      if (!mounted) return;
      setState(() => _downloadTotal = pending.length);
      if (pending.isEmpty) return;

      final result = await downloadTracksBatch(
        pending: pending,
        download: (track) => ref
            .read(downloadNotifierProvider(track.id).notifier)
            .download(track),
        isDownloaded: (id) =>
            ref.read(downloadNotifierProvider(id)) is DownloadDownloaded,
        isFailed: (id) =>
            ref.read(downloadNotifierProvider(id)) is DownloadError,
        onTrackDone: (done, fail) {
          // Живой прогресс в AppBar, а не только по завершении пачки.
          if (!mounted) return;
          setState(() => _downloadedCount = done + fail);
        },
      );
      downloaded = result.downloaded;
      failed = result.failed;
    } catch (_) {
      // Кеш-проверка может упасть — не застреляем UI.
      failed = 1;
    } finally {
      if (mounted) {
        setState(() {
          _downloadingAll = false;
          _downloadedCount = downloaded + failed;
        });
        final l = AppLocalizations.of(context)!;
        final message = failed > 0
            ? '${l.downloadedOfTotalTracks(downloaded, _downloadTotal)}, '
                '${l.errorLabel}: $failed'
            : l.downloadedOfTotalTracks(downloaded, _downloadTotal);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  void _playTrack(List<Media> queue, int index) {
    ref.read(playQueueProvider.notifier).setQueue(queue, startIndex: index);
  }

  void _loadMore() {
    ref.read(mediaListProvider(_mediaType).notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final mediaListState = ref.watch(mediaListProvider(_mediaType));
    final favoritesHasError =
        ref.watch(favoritesProvider.select((s) => s.hasError));
    final favoritesLoading =
        ref.watch(favoritesProvider.select((s) => s.isLoading));
    final favoriteIds =
        ref.watch(favoriteMediaIdsProvider).valueOrNull ?? const <int>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artistName),
        actions: [
          IconButton(
            icon: const Icon(Icons.image),
            tooltip: l.changeCover,
            onPressed: _changeArtistCover,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l.editArtistName,
            onPressed: _renameArtist,
          ),
          if (_downloadingAll)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text('$_downloadedCount/$_downloadTotal'),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: l.download,
              onPressed: _buildDownloadAll(mediaListState),
            ),
        ],
      ),
      body: _buildBody(
        context: context,
        l: l,
        mediaListState: mediaListState,
        favoritesHasError: favoritesHasError,
        favoritesLoading: favoritesLoading,
        favoriteIds: favoriteIds,
      ),
    );
  }

  /// Диалог переименования артиста: имя обновляется у всех его треков.
  Future<void> _renameArtist() async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: widget.artistName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editArtistName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l.artistName),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == widget.artistName) {
      return;
    }

    final result = await ref.read(updateArtistNameProvider)(
      UpdateArtistNameParams(
        artistId: widget.artistId,
        name: newName,
      ),
    );
    if (!mounted) return;

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
        // Имя меняется у всех треков — обновляем списки и страницу.
        _refreshAfterArtistChange();
        setState(() {});
      },
    );
  }

  /// Замена обложки артиста.
  Future<void> _changeArtistCover() async {
    final l = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final uploadResult = await ref.read(uploadArtistCoverProvider)(
      UploadArtistCoverParams(
        artistId: widget.artistId,
        filePath: file.path!,
      ),
    );
    if (!mounted) return;

    uploadResult.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.errorLabel}: ${failure.message}'),
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
        _refreshAfterArtistChange();
      },
    );
  }

  /// Инвалидирует данные, зависящие от артиста: списки медиа (имена в
  /// треках), список артистов и скачанные метаданные.
  void _refreshAfterArtistChange() {
    ref
      ..invalidate(mediaListProvider('audio'))
      ..invalidate(mediaListProvider('video'))
      ..invalidate(artistsProvider);
  }

  VoidCallback? _buildDownloadAll(AsyncValue<MediaListResult> mediaListState) {
    if (mediaListState.valueOrNull == null) return null;
    final mediaList = mediaListState.valueOrNull!;
    final tracks = mediaList.items
        .where(
          (m) =>
              m.type == MediaType.audio &&
              m.artists.any((a) => a.id == widget.artistId),
        )
        .toList();
    if (tracks.isEmpty) return null;
    return () => _downloadAll(tracks);
  }

  Widget _buildBody({
    required BuildContext context,
    required AppLocalizations l,
    required AsyncValue<MediaListResult> mediaListState,
    required bool favoritesHasError,
    required bool favoritesLoading,
    required Set<int> favoriteIds,
  }) {
    if (mediaListState.isLoading || favoritesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (mediaListState.hasError || favoritesHasError) {
      return ErrorRetryView(
        message: mediaListState.hasError
            ? mediaListState.error?.toString()
            : ref.read(favoritesProvider).error?.toString(),
        onRetry: () {
          ref
            ..invalidate(mediaListProvider(_mediaType))
            ..invalidate(favoritesProvider);
        },
      );
    }

    final mediaList = mediaListState.valueOrNull ??
        MediaListResult(items: <Media>[].toIList(), total: 0);

    final allTracks = mediaList.items
        .where(
          (Media m) =>
              m.type == MediaType.audio &&
              m.artists.any((a) => a.id == widget.artistId),
        )
        .toList();

    if (allTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l.noTracksFoundForArtist(widget.artistName),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final likedTracks =
        allTracks.where((Media t) => favoriteIds.contains(t.id)).toList();
    final otherTracks =
        allTracks.where((Media t) => !favoriteIds.contains(t.id)).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(mediaListProvider(_mediaType))
          ..invalidate(favoritesProvider);
        // Ошибка уже отражена в состоянии провайдера.
        try {
          await ref.read(mediaListProvider(_mediaType).future);
        } catch (_) {}
      },
      child: CustomScrollView(
        slivers: [
          if (likedTracks.isNotEmpty) ...[
            SliverSectionHeader(icon: Icons.favorite, title: l.likedTracks),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = likedTracks[index];
                  return AudioTrackRow(
                    media: track,
                    isFavorite: true,
                    onPlay: () => _playTrack(likedTracks, index),
                    onFavorite: () => toggleFavoriteTrack(ref, track.id),
                    onDownload: () =>
                        toggleDownloadTrack(ref, _mediaType, track.id),
                    onAddToQueue: () => addTrackToQueue(ref, track),
                    onAddToCollection: () => showAddToCollectionDialog(
                      context,
                      track.id,
                      mediaType: 'audio',
                    ),
                    onEditMetadata: () =>
                        showEditMetadataDialog(context, ref, track),
                    onChangeCover: () =>
                        changeMediaCover(context, ref, track.id),
                    onDelete: () =>
                        deleteMediaWithConfirm(context, ref, track.id),
                  );
                },
                childCount: likedTracks.length,
              ),
            ),
          ],
          if (otherTracks.isNotEmpty) ...[
            SliverSectionHeader(icon: Icons.music_note, title: l.allTracks),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = otherTracks[index];
                  return AudioTrackRow(
                    media: track,
                    onPlay: () => _playTrack(otherTracks, index),
                    onFavorite: () => toggleFavoriteTrack(ref, track.id),
                    onDownload: () =>
                        toggleDownloadTrack(ref, _mediaType, track.id),
                    onAddToQueue: () => addTrackToQueue(ref, track),
                    onAddToCollection: () => showAddToCollectionDialog(
                      context,
                      track.id,
                      mediaType: 'audio',
                    ),
                    onEditMetadata: () =>
                        showEditMetadataDialog(context, ref, track),
                    onChangeCover: () =>
                        changeMediaCover(context, ref, track.id),
                    onDelete: () =>
                        deleteMediaWithConfirm(context, ref, track.id),
                  );
                },
                childCount: otherTracks.length,
              ),
            ),
          ],
          // Вместо бесконечного скролла (который догружал весь аудио-список
          // ради фильтра по артисту) — явная кнопка «загрузить ещё».
          if (mediaList.items.length < mediaList.total)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    onPressed: _loadMore,
                    child: Text(l.loadMore),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
