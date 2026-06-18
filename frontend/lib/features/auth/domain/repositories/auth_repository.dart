import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/shared/models/user.dart';

abstract class AuthRepository {
  Future<Either<Failure, String?>> requestCode(String email);
  Future<Either<Failure, ({String token, User user})>> verifyCode(
    String email,
    String code,
  );
  Future<Either<Failure, User>> getCurrentUser();
}
