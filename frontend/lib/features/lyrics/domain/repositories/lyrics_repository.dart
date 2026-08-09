import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:fpdart/fpdart.dart';

abstract class LyricsRepository {
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId);
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    required String source,
    String? translation,
    String? syncData,
  });
}
