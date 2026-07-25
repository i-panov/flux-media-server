import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

abstract class LyricsRepository {
  Future<Either<Failure, Lyrics?>> getLyrics(int mediaId);
  Future<Either<Failure, Lyrics>> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    String? translation,
    String? syncData,
    required String source,
  });
}
