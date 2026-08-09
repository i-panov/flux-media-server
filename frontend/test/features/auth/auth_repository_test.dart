import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';

class FakeAuthRepository implements AuthRepository {
  Future<Either<Failure, String?>> Function(String)? onRequestCode;
  Future<Either<Failure, ({String token, String refreshToken, User user})>>
      Function(String, String)? onVerifyCode;
  Future<Either<Failure, User>> Function()? onGetCurrentUser;
  Future<Either<Failure, ({String token, String refreshToken})>> Function(
    String,
  )? onRefreshToken;

  @override
  Future<Either<Failure, String?>> requestCode(String email) =>
      onRequestCode!(email);

  @override
  Future<Either<Failure, ({String token, String refreshToken, User user})>>
      verifyCode(String email, String code) => onVerifyCode!(email, code);

  @override
  Future<Either<Failure, User>> getCurrentUser() => onGetCurrentUser!();

  @override
  Future<Either<Failure, ({String token, String refreshToken})>> refreshToken(
    String refreshToken,
  ) =>
      onRefreshToken!(refreshToken);
}

void main() {
  late AuthRepository repository;

  setUp(() {
    repository = FakeAuthRepository();
  });

  group('requestCode', () {
    test('returns Right(null) when not in debug mode', () async {
      (repository as FakeAuthRepository).onRequestCode =
          (_) async => const Right<Failure, String?>(null);

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Right<Failure, String?>>());
      expect(result.getOrElse((_) => null), isNull);
    });

    test('returns Right(debugCode) when in debug mode', () async {
      (repository as FakeAuthRepository).onRequestCode =
          (_) async => const Right<Failure, String>('123456');

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Right<Failure, String>>());
      expect(result.getOrElse((_) => ''), '123456');
    });

    test('returns Left(ServerFailure) on error', () async {
      (repository as FakeAuthRepository).onRequestCode =
          (_) async => const Left<Failure, String?>(
                ServerFailure(message: 'Email not allowed'),
              );

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Left<Failure, String?>>());
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Email not allowed',
      );
    });
  });

  group('verifyCode', () {
    test('returns Right(token, refreshToken, user) on success', () async {
      const user = User(id: 1, email: 'test@example.com');
      (repository as FakeAuthRepository).onVerifyCode = (_, __) async =>
          const Right<Failure,
              ({String token, String refreshToken, User user})>(
            (token: 'jwt-123', refreshToken: 'refresh-456', user: user),
          );

      final result = await repository.verifyCode('test@example.com', '123456');

      expect(
        result,
        isA<Right<Failure, ({String token, String refreshToken, User user})>>(),
      );
      final data = result.getOrElse(
        (_) =>
            (token: '', refreshToken: '', user: const User(id: 0, email: '')),
      );
      expect(data.token, 'jwt-123');
      expect(data.refreshToken, 'refresh-456');
      expect(data.user.email, 'test@example.com');
    });

    test('returns Left(ServerFailure) on invalid code', () async {
      (repository as FakeAuthRepository).onVerifyCode = (_, __) async =>
          const Left<Failure, ({String token, String refreshToken, User user})>(
            ServerFailure(message: 'Invalid or expired code'),
          );

      final result = await repository.verifyCode('test@example.com', '000000');

      expect(
        result,
        isA<Left<Failure, ({String token, String refreshToken, User user})>>(),
      );
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Invalid or expired code',
      );
    });
  });

  group('getCurrentUser', () {
    test('returns Right(user) on success', () async {
      const user = User(id: 1, email: 'test@example.com');
      (repository as FakeAuthRepository).onGetCurrentUser =
          () async => const Right<Failure, User>(user);

      final result = await repository.getCurrentUser();

      expect(result, isA<Right<Failure, User>>());
      expect(
        result.getOrElse((_) => const User(id: 0, email: '')).email,
        'test@example.com',
      );
    });

    test('returns Left(ServerFailure) on unauthorized', () async {
      (repository as FakeAuthRepository).onGetCurrentUser = () async =>
          const Left<Failure, User>(ServerFailure(message: 'Unauthorized'));

      final result = await repository.getCurrentUser();

      expect(result, isA<Left<Failure, User>>());
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Unauthorized',
      );
    });
  });
}
