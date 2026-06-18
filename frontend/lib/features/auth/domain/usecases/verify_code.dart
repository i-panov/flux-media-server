import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/shared/models/user.dart';

class VerifyCodeParams {
  const VerifyCodeParams({
    required this.email,
    required this.code,
  });

  final String email;
  final String code;
}

class VerifyCodeResult {
  const VerifyCodeResult({
    required this.token,
    required this.user,
  });

  final String token;
  final User user;
}

class VerifyCode {
  VerifyCode(this.repository);

  final AuthRepository repository;

  Future<Either<Failure, VerifyCodeResult>> call(VerifyCodeParams params) async {
    final result = await repository.verifyCode(params.email, params.code);
    return result.fold(
      (failure) => Left(failure),
      (data) => Right(VerifyCodeResult(
        token: data.token,
        user: data.user,
      )),
    );
  }
}
