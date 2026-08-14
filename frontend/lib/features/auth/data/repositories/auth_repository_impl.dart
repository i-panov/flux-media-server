import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this.remoteDataSource);

  final AuthRemoteDataSource remoteDataSource;

  String? _lastDebugCode;

  @override
  String? get lastDebugCode => _lastDebugCode;

  @override
  Future<Either<Failure, Unit>> requestCode(String email) async {
    final result =
        await safeRepositoryCall(() => remoteDataSource.requestCode(email));
    return result.fold(
      Left.new,
      (debugCode) {
        _lastDebugCode = debugCode;
        return const Right(unit);
      },
    );
  }

  @override
  Future<Either<Failure, ({String token, String refreshToken, User user})>>
      verifyCode(String email, String code) =>
          safeRepositoryCall(() => remoteDataSource.verifyCode(email, code));

  @override
  Future<Either<Failure, User>> getCurrentUser() =>
      safeRepositoryCall(remoteDataSource.getCurrentUser);

  @override
  Future<Either<Failure, ({String token, String refreshToken})>> refreshToken(
    String refreshToken,
  ) =>
      safeRepositoryCall(() => remoteDataSource.refreshTokens(refreshToken));
}
