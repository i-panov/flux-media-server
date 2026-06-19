import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/shared/models/user.dart';

class FakeAuthRepository implements AuthRepository {
  Future<Either<Failure, String?>> Function(String)? onRequestCode;
  Future<Either<Failure, ({String token, User user})>> Function(String, String)?
      onVerifyCode;
  Future<Either<Failure, User>> Function()? onGetCurrentUser;

  @override
  Future<Either<Failure, String?>> requestCode(String email) =>
      onRequestCode!(email);

  @override
  Future<Either<Failure, ({String token, User user})>> verifyCode(
    String email,
    String code,
  ) =>
      onVerifyCode!(email, code);

  @override
  Future<Either<Failure, User>> getCurrentUser() => onGetCurrentUser!();
}

void main() {
  late AuthRepository repository;

  setUp(() {
    repository = FakeAuthRepository();
  });

  group('requestCode', () {
    test('returns Right(null) when not in debug mode', () async {
      (repository as FakeAuthRepository).onRequestCode = (_) async =>
          const Right(null);

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Right>());
      expect(result.getOrElse((_) => null), isNull);
    });

    test('returns Right(debugCode) when in debug mode', () async {
      (repository as FakeAuthRepository).onRequestCode = (_) async =>
          const Right('123456');

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Right>());
      expect(result.getOrElse((_) => null), '123456');
    });

    test('returns Left(ServerFailure) on error', () async {
      (repository as FakeAuthRepository).onRequestCode = (_) async =>
          const Left(ServerFailure(message: 'Email not allowed'));

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Left>());
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Email not allowed',
      );
    });
  });

  group('verifyCode', () {
    test('returns Right(token, user) on success', () async {
      final user = User(id: 1, email: 'test@example.com');
      (repository as FakeAuthRepository).onVerifyCode = (_, __) async =>
          Right((token: 'jwt-123', user: user));

      final result = await repository.verifyCode('test@example.com', '123456');

      expect(result, isA<Right>());
      final data = result.getOrElse(
        (_) => (token: '', user: User(id: 0, email: '')),
      );
      expect(data.token, 'jwt-123');
      expect(data.user.email, 'test@example.com');
    });

    test('returns Left(ServerFailure) on invalid code', () async {
      (repository as FakeAuthRepository).onVerifyCode = (_, __) async =>
          const Left(ServerFailure(message: 'Invalid or expired code'));

      final result = await repository.verifyCode('test@example.com', '000000');

      expect(result, isA<Left>());
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Invalid or expired code',
      );
    });
  });

  group('getCurrentUser', () {
    test('returns Right(user) on success', () async {
      final user = User(id: 1, email: 'test@example.com');
      (repository as FakeAuthRepository).onGetCurrentUser = () async =>
          Right(user);

      final result = await repository.getCurrentUser();

      expect(result, isA<Right>());
      expect(
        result.getOrElse((_) => User(id: 0, email: '')).email,
        'test@example.com',
      );
    });

    test('returns Left(ServerFailure) on unauthorized', () async {
      (repository as FakeAuthRepository).onGetCurrentUser = () async =>
          const Left(ServerFailure(message: 'Unauthorized'));

      final result = await repository.getCurrentUser();

      expect(result, isA<Left>());
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Unauthorized',
      );
    });
  });
}
