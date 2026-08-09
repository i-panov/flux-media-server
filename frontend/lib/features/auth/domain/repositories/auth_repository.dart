import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';

abstract class AuthRepository {
  Future<Either<Failure, String?>> requestCode(String email);
  Future<Either<Failure, ({String token, String refreshToken, User user})>>
      verifyCode(String email, String code);
  Future<Either<Failure, User>> getCurrentUser();
  Future<Either<Failure, ({String token, String refreshToken})>> refreshToken(
    String refreshToken,
  );
}
