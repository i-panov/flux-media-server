import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Exposes Ref for building the token refresh interceptor in tests.
final _refProvider = Provider<Ref>((ref) => ref);

class FakeAuthRepository implements AuthRepository {
  Future<Either<Failure, Unit>> Function(String)? onRequestCode;
  Future<Either<Failure, ({String token, String refreshToken, User user})>>
      Function(String, String)? onVerifyCode;
  Future<Either<Failure, User>> Function()? onGetCurrentUser;
  Future<Either<Failure, ({String token, String refreshToken})>> Function(
    String,
  )? onRefreshToken;

  int requestCodeCalls = 0;

  String? _lastDebugCode;

  @override
  String? get lastDebugCode => _lastDebugCode;

  @override
  Future<Either<Failure, Unit>> requestCode(String email) async {
    requestCodeCalls++;
    return onRequestCode!(email);
  }

  set lastDebugCode(String? value) => _lastDebugCode = value;

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

/// Фейк офлайн-кеша: считает вызовы clearUserCache без реального IO.
class FakeOfflineCacheService extends OfflineCacheService {
  FakeOfflineCacheService(Ref ref) : super(ref, 'http://localhost:8080/api');

  int clearUserCacheCalls = 0;

  @override
  Future<void> clearUserCache() async {
    clearUserCacheCalls++;
  }
}

void main() {
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final mockStorage = <String, String>{};
  const keyPrefix = kDebugMode ? 'debug_' : 'release_';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel,
            (MethodCall methodCall) async {
      final args = methodCall.arguments as Map<dynamic, dynamic>;
      switch (methodCall.method) {
        case 'read':
          return mockStorage[args['key'] as String];
        case 'write':
          mockStorage[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          mockStorage.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  late ProviderContainer container;
  late FakeAuthRepository fakeRepo;
  late FakeOfflineCacheService fakeCache;

  setUp(() async {
    mockStorage.clear();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeRepo = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineCacheServiceProvider.overrideWith(FakeOfflineCacheService.new),
        requestCodeProvider.overrideWithValue(RequestCode(fakeRepo)),
        verifyCodeProvider.overrideWithValue(VerifyCode(fakeRepo)),
        getCurrentUserProvider.overrideWithValue(GetCurrentUser(fakeRepo)),
        // Фейковый refresher: не ходит в сеть, refresh всегда неудачен.
        authTokenRefresherProvider.overrideWith(
          (ref) => AuthTokenRefresher(
            performRefresh: (_) async => null,
            onRefreshFailure: () async {},
          ),
        ),
      ],
    );
    fakeCache = container.read(offlineCacheServiceProvider)
        as FakeOfflineCacheService;
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
      fakeRepo.onRequestCode = (_) async {
        fakeRepo.lastDebugCode = '123456';
        return const Right(unit);
      };

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

    test('requestCode emits codeSent with null debugCode', () async {
      fakeRepo.onRequestCode = (_) async => const Right(unit);

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

      final codeSent = states.whereType<AuthCodeSent>().first;
      expect(codeSent.email, 'test@example.com');
      expect(codeSent.debugCode, isNull);
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

    test('concurrent requestCode calls do not duplicate the request',
        () async {
      final gate = Completer<void>();
      fakeRepo.onRequestCode = (_) async {
        await gate.future;
        return const Right(unit);
      };

      final first =
          container.read(authProvider.notifier).requestCode('test@example.com');
      final second =
          container.read(authProvider.notifier).requestCode('test@example.com');
      gate.complete();
      await Future.wait([first, second]);

      expect(fakeRepo.requestCodeCalls, 1);
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

    test('verifyCode persists tokens to secure storage', () async {
      const user = User(id: 1, email: 'test@example.com');
      fakeRepo.onVerifyCode = (_, __) async => const Right(
            (token: 'jwt-token', refreshToken: 'refresh-token', user: user),
          );

      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '123456');

      expect(mockStorage['${keyPrefix}auth_token'], 'jwt-token');
      expect(mockStorage['${keyPrefix}refresh_token'], 'refresh-token');
      final settings = container.read(settingsProvider).settings;
      expect(settings.authToken, 'jwt-token');
      expect(settings.refreshToken, 'refresh-token');
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

    test('checkAuthStatus emits authenticated on success', () async {
      fakeRepo.onGetCurrentUser = () async => const Right(
            User(id: 1, email: 'test@example.com'),
          );

      await container.read(authProvider.notifier).checkAuthStatus();

      final state = container.read(authProvider);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'test@example.com');
    });

    test('checkAuthStatus resets session on AuthFailure', () async {
      await container
          .read(settingsProvider.notifier)
          .setTokens('stale-token', 'stale-refresh');
      fakeRepo.onGetCurrentUser =
          () async => const Left(AuthFailure(message: 'Session expired'));

      await container.read(authProvider.notifier).checkAuthStatus();

      final state = container.read(authProvider);
      expect(state, isA<AuthInitial>());
      // Токены очищены, чтобы избежать бесконечного цикла 401.
      expect(mockStorage.containsKey('${keyPrefix}auth_token'), isFalse);
      expect(mockStorage.containsKey('${keyPrefix}refresh_token'), isFalse);
    });

    test('checkAuthStatus keeps session on network error', () async {
      await container
          .read(settingsProvider.notifier)
          .setTokens('stale-token', 'stale-refresh');
      fakeRepo.onGetCurrentUser =
          () async => const Left(NetworkFailure(message: 'No connection'));

      await container.read(authProvider.notifier).checkAuthStatus();

      final state = container.read(authProvider);
      expect(state, isA<AuthError>());
      final error = state as AuthError;
      expect(error.isOffline, isTrue);
      expect(error.message, 'No connection');
      // Токены не сброшены: пользователь не разлогинен из-за сети.
      expect(mockStorage['${keyPrefix}auth_token'], 'stale-token');
      expect(mockStorage['${keyPrefix}refresh_token'], 'stale-refresh');
    });

    test('logout clears tokens and user cache', () async {
      await container
          .read(settingsProvider.notifier)
          .setTokens('token', 'refresh');

      await container.read(authProvider.notifier).logout();

      expect(fakeCache.clearUserCacheCalls, 1);
      expect(mockStorage.containsKey('${keyPrefix}auth_token'), isFalse);
      expect(mockStorage.containsKey('${keyPrefix}refresh_token'), isFalse);
      final state = container.read(authProvider);
      expect(state, isA<AuthInitial>());
    });

    test('verifyCode does not emit AuthLoading (CodeScreen stays mounted)',
        () async {
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

      // Глобальный AuthLoading размонтировал бы Navigator через splash
      // (потеря cooldown и формы) — его не должно быть ни до, ни после.
      expect(states.whereType<AuthLoading>(), isEmpty);
      expect(states.last, isA<AuthError>());
    });

    test('requestCode returns true when the code was sent', () async {
      fakeRepo.onRequestCode = (_) async {
        fakeRepo.lastDebugCode = '123456';
        return const Right(unit);
      };

      final sent =
          await container.read(authProvider.notifier).requestCode('a@b.c');
      expect(sent, isTrue);
      expect(
        container.read(authProvider.notifier).lastRequestedEmail,
        'a@b.c',
      );
    });

    test('requestCode returns false on failure', () async {
      fakeRepo.onRequestCode =
          (_) async => const Left(NetworkFailure(message: 'No connection'));

      final sent =
          await container.read(authProvider.notifier).requestCode('a@b.c');
      expect(sent, isFalse);
    });

    test('concurrent requestCode returns false for the swallowed call',
        () async {
      final gate = Completer<void>();
      fakeRepo.onRequestCode = (_) async {
        await gate.future;
        return const Right(unit);
      };

      final first =
          container.read(authProvider.notifier).requestCode('a@b.c');
      final second =
          container.read(authProvider.notifier).requestCode('a@b.c');
      gate.complete();
      final results = await Future.wait([first, second]);

      expect(results, [true, false]);
      expect(fakeRepo.requestCodeCalls, 1);
    });

    test('checkAuthStatus result is ignored after logout', () async {
      final gate = Completer<void>();
      fakeRepo.onGetCurrentUser = () async {
        await gate.future;
        return const Right(User(id: 1, email: 'test@example.com'));
      };

      final pending = container.read(authProvider.notifier).checkAuthStatus();
      await container.read(authProvider.notifier).logout();
      gate.complete();
      await pending;

      // Устаревший ответ не должен вернуть AuthAuthenticated после logout.
      expect(container.read(authProvider), isA<AuthInitial>());
    });

    test('expireSession resets state to initial', () async {
      const user = User(id: 1, email: 'test@example.com');
      fakeRepo.onVerifyCode = (_, __) async => const Right(
            (token: 't', refreshToken: 'r', user: user),
          );
      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '123456');
      expect(container.read(authProvider), isA<AuthAuthenticated>());

      container.read(authProvider.notifier).expireSession();

      expect(container.read(authProvider), isA<AuthInitial>());
    });

    test('failed token refresh resets auth state via interceptor', () async {
      await container
          .read(settingsProvider.notifier)
          .setTokens('token', 'refresh');
      const user = User(id: 1, email: 'test@example.com');
      fakeRepo.onVerifyCode = (_, __) async => const Right(
            (token: 't', refreshToken: 'r', user: user),
          );
      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '123456');
      expect(container.read(authProvider), isA<AuthAuthenticated>());

      final interceptor = TokenRefreshInterceptor(
        container.read(_refProvider),
      );
      final response =
          Response<String>(http.Response('unauthorized', 401), 'unauthorized');
      final result = await interceptor.onResponse(response);

      // 401 + неудачный refresh → сессия сброшена в AuthInitial,
      // а не «залогиненный» пользователь со стейлыми токенами.
      expect(result.statusCode, 401);
      expect(container.read(authProvider), isA<AuthInitial>());
    });
  });
}
