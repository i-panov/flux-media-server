import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';

class VerifyCodeParams {
  const new({required this.email, required this.code});

  final String email;
  final String code;
}

class VerifyCodeResult {
  const new({
    required this.token,
    required this.refreshToken,
    required this.user,
  });

  final String token;
  final String refreshToken;
  final User user;
}

class VerifyCode
    extends UseCase<Either<Failure, VerifyCodeResult>, VerifyCodeParams> {
  new(this.repository);

  final AuthRepository repository;

  @override
  Future<Either<Failure, VerifyCodeResult>> call(VerifyCodeParams params) {
    return repository
        .verifyCode(params.email, params.code)
        .then(
          (result) => result.fold(
            Left.new,
            (data) => Right(
              VerifyCodeResult(
                token: data.token,
                refreshToken: data.refreshToken,
                user: data.user,
              ),
            ),
          ),
        );
  }
}
