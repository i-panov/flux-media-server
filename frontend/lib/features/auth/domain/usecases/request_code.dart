import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';

class RequestCode extends UseCase<Either<Failure, String?>, String> {
  RequestCode(this.repository);

  final AuthRepository repository;

  @override
  Future<Either<Failure, String?>> call(String params) {
    return repository.requestCode(params);
  }
}
