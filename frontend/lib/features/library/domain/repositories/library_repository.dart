import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/utils/either.dart';
import 'package:flux_media_server/shared/models/library.dart';

abstract class LibraryRepository {
  Future<Either<Failure, List<MediaLibrary>>> getLibraries();

  Future<Either<Failure, MediaLibrary>> scanLibrary(int id);
}
