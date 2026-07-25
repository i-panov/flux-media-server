import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/lyrics/data/datasources/lyrics_remote_datasource.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  LyricsRepositoryImpl(this.remoteDataSource);

  final LyricsRemoteDataSource remoteDataSource;

  Future<Either<Failure, T>> _wrap<T>(Future<T> Function() fn) async {
    try {
      return Right(await fn());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId) =>
      _wrap(() => remoteDataSource.getLyrics(mediaId));

  @override
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    String? translation,
    String? syncData,
    required String source,
  }) =>
      _wrap(() => remoteDataSource.upsertLyrics(
        mediaId,
        lyricsText: lyricsText,
        translation: translation,
        syncData: syncData,
        source: source,
      ));
}
