import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // Mock the secure storage platform channel
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel,
            (MethodCall methodCall) async {
      if (methodCall.method == 'read') return null;
      if (methodCall.method == 'write') return null;
      if (methodCall.method == 'delete') return null;
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  late ProviderContainer container;
  late FakeAuthRepository fakeRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeRepo = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        requestCodeProvider.overrideWithValue(RequestCode(fakeRepo)),
        verifyCodeProvider.overrideWithValue(VerifyCode(fakeRepo)),
        getCurrentUserProvider.overrideWithValue(GetCurrentUser(fakeRepo)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('AuthNotifier', () {
    test('initial state is AuthInitial', () {
      final state = container.read(authProvider);
      expect(state, isA<AuthInitial>());
    });

    test('requestCode emits codeSent on success', () async {
      fakeRepo.onRequestCode = (_) async => const Right('123456');

      final states = <AuthState>[];
      container.listen<AuthState>(
        authProvider,
        (prev, next) {
          states.add(next);
        },
        fireImmediately: true,
      );

      await container
          .read(authProvider.notifier)
          .requestCode('test@example.com');

      expect(states, contains(isA<AuthCodeSent>()));
      final codeSent = states.whereType<AuthCodeSent>().first;
      expect(codeSent.email, 'test@example.com');
      expect(codeSent.debugCode, '123456');
    });

    test('requestCode emits error on failure', () async {
      fakeRepo.onRequestCode =
          (_) async => const Left(ServerFailure(message: 'Email not allowed'));

      final states = <AuthState>[];
      container.listen<AuthState>(
        authProvider,
        (prev, next) {
          states.add(next);
        },
        fireImmediately: true,
      );

      await container
          .read(authProvider.notifier)
          .requestCode('test@example.com');

      expect(states, contains(isA<AuthError>()));
      final error = states.whereType<AuthError>().first;
      expect(error.message, 'Email not allowed');
    });

    test('verifyCode emits authenticated on success', () async {
      const user = User(id: 1, email: 'test@example.com');
      fakeRepo.onVerifyCode = (_, __) async => const Right(
            (token: 'jwt-token', refreshToken: 'refresh-token', user: user),
          );

      final states = <AuthState>[];
      container.listen<AuthState>(
        authProvider,
        (prev, next) {
          states.add(next);
        },
        fireImmediately: true,
      );

      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '123456');

      expect(states, contains(isA<AuthAuthenticated>()));
      final auth = states.whereType<AuthAuthenticated>().first;
      expect(auth.user.email, 'test@example.com');
    });

    test('verifyCode emits error on invalid code', () async {
      fakeRepo.onVerifyCode = (_, __) async =>
          const Left(ServerFailure(message: 'Invalid or expired code'));

      final states = <AuthState>[];
      container.listen<AuthState>(
        authProvider,
        (prev, next) {
          states.add(next);
        },
        fireImmediately: true,
      );

      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '000000');

      expect(states, contains(isA<AuthError>()));
      final error = states.whereType<AuthError>().first;
      expect(error.message, 'Invalid or expired code');
    });
  });
}
