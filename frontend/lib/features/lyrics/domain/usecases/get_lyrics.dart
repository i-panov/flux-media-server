import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class GetLyrics extends UseCase<Either<Failure, Lyrics?>, int> {
  GetLyrics(this.repository);
  final LyricsRepository repository;

  @override
  Future<Either<Failure, Lyrics?>> call(int mediaId) {
    return repository.getLyrics(mediaId);
  }
}
