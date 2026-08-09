import 'package:chopper/chopper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:flux_media_server/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';

/// Fake AuthRemoteDataSource that overrides all methods to return
/// canned data or throw exceptions, allowing us to test the real
/// AuthRepositoryImpl + safeRepositoryCall chain.
class _FakeAuthRemoteDataSource extends AuthRemoteDataSource {
  _FakeAuthRemoteDataSource()
      : super(ApiClient.create(baseUrl: 'http://localhost:8080/api'));

  // Canned responses / exceptions for each method.
  String? Function(String)? onRequestCode;
  ({String token, String refreshToken, User user}) Function(String, String)?
      onVerifyCode;
  User Function()? onGetCurrentUser;
  ({String token, String refreshToken}) Function(String)? onRefreshToken;

  @override
  Future<String?> requestCode(String email) async {
    if (onRequestCode == null) return null;
    return onRequestCode!(email);
  }

  @override
  Future<({String token, String refreshToken, User user})> verifyCode(
    String email,
    String code,
  ) async {
    if (onVerifyCode == null) {
      throw ServerException(message: 'not configured');
    }
    return onVerifyCode!(email, code);
  }

  @override
  Future<User> getCurrentUser() async {
    if (onGetCurrentUser == null) {
      throw ServerException(message: 'not configured');
    }
    return onGetCurrentUser!();
  }

  @override
  Future<({String token, String refreshToken})> refreshTokens(
    String refreshToken,
  ) async {
    if (onRefreshToken == null) {
      throw ServerException(message: 'not configured');
    }
    return onRefreshToken!(refreshToken);
  }
}

void main() {
  late _FakeAuthRemoteDataSource datasource;
  late AuthRepositoryImpl repository;

  setUp(() {
    datasource = _FakeAuthRemoteDataSource();
    repository = AuthRepositoryImpl(datasource);
  });

  group('requestCode', () {
    test('returns Right(null) when not in debug mode', () async {
      datasource.onRequestCode = (_) => null;

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Right<Failure, String?>>());
      expect(result.getOrElse((_) => null), isNull);
    });

    test('returns Right(debugCode) when in debug mode', () async {
      datasource.onRequestCode = (_) => '123456';

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Right<Failure, String?>>());
      expect(result.getOrElse((_) => null), '123456');
    });

    test('returns Left(ServerFailure) on ServerException', () async {
      datasource.onRequestCode =
          (_) => throw ServerException(message: 'Email not allowed');

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Left<Failure, String?>>());
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Email not allowed',
      );
    });

    test('returns Left(AuthFailure) on AuthException', () async {
      datasource.onRequestCode =
          (_) => throw const AuthException(message: 'Session expired');

      final result = await repository.requestCode('test@example.com');

      expect(result, isA<Left<Failure, String?>>());
      expect(result.fold((l) => l, (_) => null), isA<AuthFailure>());
    });
  });

  group('verifyCode', () {
    test('returns Right(token, refreshToken, user) on success', () async {
      const user = User(id: 1, email: 'test@example.com');
      datasource.onVerifyCode = (_, __) => (
            token: 'jwt-123',
            refreshToken: 'refresh-456',
            user: user,
          );

      final result =
          await repository.verifyCode('test@example.com', '123456');

      expect(
        result,
        isA<Right<Failure, ({String token, String refreshToken, User user})>>(),
      );
      final data = result.getOrElse(
        (_) => (
          token: '',
          refreshToken: '',
          user: const User(id: 0, email: ''),
        ),
      );
      expect(data.token, 'jwt-123');
      expect(data.refreshToken, 'refresh-456');
      expect(data.user.email, 'test@example.com');
    });

    test('returns Left(ServerFailure) on ServerException', () async {
      datasource.onVerifyCode =
          (_, __) => throw ServerException(message: 'Invalid or expired code');

      final result =
          await repository.verifyCode('test@example.com', '000000');

      expect(
        result,
        isA<Left<
            Failure, ({String token, String refreshToken, User user})>>(),
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
      datasource.onGetCurrentUser = () => user;

      final result = await repository.getCurrentUser();

      expect(result, isA<Right<Failure, User>>());
      expect(
        result.getOrElse((_) => const User(id: 0, email: '')).email,
        'test@example.com',
      );
    });

    test('returns Left(AuthFailure) on AuthException', () async {
      datasource.onGetCurrentUser =
          () => throw const AuthException(message: 'Unauthorized');

      final result = await repository.getCurrentUser();

      expect(result, isA<Left<Failure, User>>());
      expect(result.fold((l) => l, (_) => null), isA<AuthFailure>());
    });
  });

  group('refreshToken', () {
    test('returns Right(tokens) on success', () async {
      datasource.onRefreshToken = (_) => (
            token: 'new-jwt',
            refreshToken: 'new-refresh',
          );

      final result = await repository.refreshToken('old-refresh');

      expect(
        result,
        isA<Right<Failure, ({String token, String refreshToken})>>(),
      );
      final data = result.getOrElse((_) => (token: '', refreshToken: ''));
      expect(data.token, 'new-jwt');
      expect(data.refreshToken, 'new-refresh');
    });

    test('returns Left(ServerFailure) on ServerException', () async {
      datasource.onRefreshToken =
          (_) => throw ServerException(message: 'Invalid refresh token');

      final result = await repository.refreshToken('old-refresh');

      expect(
        result,
        isA<Left<Failure, ({String token, String refreshToken})>>(),
      );
      expect(
        result.fold((l) => l.message, (_) => ''),
        'Invalid refresh token',
      );
    });
  });
}
