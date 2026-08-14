import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:fpdart/fpdart.dart';

class RequestCode extends UseCase<Either<Failure, Unit>, String> {
  RequestCode(this.repository);

  final AuthRepository repository;

  /// Debug-код из последнего успешного запроса (см.
  /// [AuthRepository.lastDebugCode]).
  String? get lastDebugCode => repository.lastDebugCode;

  @override
  Future<Either<Failure, Unit>> call(String params) {
    return repository.requestCode(params);
  }
}
