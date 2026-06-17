import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';

class GetLibraries implements UseCase<List<MediaLibrary>, NoParams> {
  GetLibraries(this.repository);

  final LibraryRepository repository;

  @override
  Future<List<MediaLibrary>> call(NoParams params) {
    return repository.getLibraries().then(
          (result) => result.fold(
            (failure) => throw Exception(failure.message),
            (libraries) => libraries,
          ),
        );
  }
}
