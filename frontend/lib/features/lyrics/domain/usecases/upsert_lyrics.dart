import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:fpdart/fpdart.dart';

class UpsertLyricsParams {
  const UpsertLyricsParams({
    required this.mediaId,
    required this.lyricsText,
    required this.source,
    this.translation,
    this.syncData,
  });
  final int mediaId;
  final String lyricsText;
  final String? translation;
  final String? syncData;
  final String source;
}

class UpsertLyrics
    extends UseCase<Either<Failure, Lyrics>, UpsertLyricsParams> {
  UpsertLyrics(this.repository);
  final LyricsRepository repository;

  @override
  Future<Either<Failure, Lyrics>> call(UpsertLyricsParams params) {
    return repository.upsertLyrics(
      params.mediaId,
      lyricsText: params.lyricsText,
      translation: params.translation,
      syncData: params.syncData,
      source: params.source,
    );
  }
}
