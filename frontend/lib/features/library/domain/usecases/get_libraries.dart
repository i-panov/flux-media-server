import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';

class GetLibraries extends UseCase<Either<Failure, List<MediaLibrary>>, NoParams> {
  GetLibraries(this.repository);

  final LibraryRepository repository;

  @override
  Future<Either<Failure, List<MediaLibrary>>> call(NoParams params) {
    return repository.getLibraries();
  }
}
