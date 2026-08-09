import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this.remoteDataSource);

  final AuthRemoteDataSource remoteDataSource;

  @override
  Future<Either<Failure, String?>> requestCode(String email) =>
      safeRepositoryCall(() => remoteDataSource.requestCode(email));

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
