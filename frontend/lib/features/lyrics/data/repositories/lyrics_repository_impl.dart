import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/lyrics/data/datasources/lyrics_remote_datasource.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  LyricsRepositoryImpl(this.remoteDataSource);

  final LyricsRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId) =>
      safeRepositoryCall(() => remoteDataSource.getLyrics(mediaId));

  @override
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    String? translation,
    String? syncData,
    required String source,
  }) =>
      safeRepositoryCall(() => remoteDataSource.upsertLyrics(
        mediaId,
        lyricsText: lyricsText,
        translation: translation,
        syncData: syncData,
        source: source,
      ));
}
