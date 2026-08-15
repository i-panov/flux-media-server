import 'dart:async';


import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/domain/repositories/auth_repository.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/auth/presentation/auth_guard.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/player/data/providers/player_sources.dart';
import 'package:flux_media_server/main.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuthRepository implements AuthRepository {
  Future<Either<Failure, Unit>> Function(String)? onRequestCode;
  Future<Either<Failure, ({String token, String refreshToken, User user})>>
      Function(String, String)? onVerifyCode;
  Future<Either<Failure, User>> Function()? onGetCurrentUser;
  Future<Either<Failure, ({String token, String refreshToken})>> Function(
    String,
  )? onRefreshToken;

  String? _lastDebugCode;

  @override
  String? get lastDebugCode => _lastDebugCode;

  set lastDebugCode(String? value) => _lastDebugCode = value;

  @override
  Future<Either<Failure, Unit>> requestCode(String email) async {
    return onRequestCode!(email);
  }

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

class FakeOfflineCacheService extends OfflineCacheService {
  FakeOfflineCacheService(Ref ref) : super(ref, 'http://localhost:8080/api');

  @override
  Future<void> clearUserCache() async {}

  @override
  Future<int> getCacheSize() async => 0;
}

class FakeAudioSource implements AudioPlaybackSource {
  @override
  Future<void> loadSource({
    required String url,
    required String title,
    String? artist,
    String? artUri,
    Duration? duration,
    Map<String, String>? httpHeaders,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration> get durationStream => const Stream.empty();

  @override
  Stream<bool> get playingStream => const Stream.empty();

  @override
  Stream<bool> get completedStream => const Stream.empty();

  @override
  Stream<String> get errorStream => const Stream.empty();

  @override
  Stream<bool> get bufferingStream => const Stream.empty();

  @override
  Stream<double> get volumeStream => const Stream.empty();

  @override
  double get volume => 1;
}

void main() {
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final mockStorage = <String, String>{};

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
  late AppRouter router;

  Future<void> pumpFluxApp(WidgetTester tester) async {
    router = AppRouter(authGuard: AuthGuard(container));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FluxApp(router: router),
      ),
    );
  }

  Future<void> settleFrames(WidgetTester tester) async {
    // Не pumpAndSettle: спиннеры/сетевые запросы в тестовой среде
    // не дают кадрам «успокоиться».
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

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
        authTokenRefresherProvider.overrideWith(
          (ref) => AuthTokenRefresher(
            performRefresh: (_) async => null,
            onRefreshFailure: () async {},
          ),
        ),
        audioPlayerDatasourceProvider.overrideWithValue(FakeAudioSource()),
        baseUrlProvider.overrideWithValue('http://localhost:8080/api'),
        playbackCoordinatorProvider.overrideWith(PlaybackCoordinator.new),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('навигация при ошибке верификации', () {
    testWidgets('ошибка verifyCode не меняет маршрут (CodeRoute остаётся)',
        (tester) async {
      fakeRepo
        ..onRequestCode = (_) async {
          return const Right(unit);
        }
        ..onVerifyCode = (_, __) async {
          return const Left(ServerFailure(message: 'Invalid or expired code'));
        };

      await pumpFluxApp(tester);
      await settleFrames(tester);

      unawaited(router.push(CodeRoute(email: 'test@example.com')));
      await settleFrames(tester);
      expect(router.current.name, CodeRoute.name);

      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '000000');
      await settleFrames(tester);

      // Раньше AuthError при previous==AuthLoading уводил на MainRoute.
      expect(router.current.name, CodeRoute.name);
      expect(container.read(authProvider), isA<AuthError>());
    });

    testWidgets('неверный код не отправляет на ServerSetupRoute',
        (tester) async {
      fakeRepo
        ..onRequestCode = (_) async {
          return const Right(unit);
        }
        ..onVerifyCode = (_, __) async {
          return const Left(ServerFailure(message: 'Invalid or expired code'));
        };

      await pumpFluxApp(tester);
      await settleFrames(tester);

      unawaited(router.push(CodeRoute(email: 'test@example.com')));
      await settleFrames(tester);

      await container
          .read(authProvider.notifier)
          .verifyCode('test@example.com', '000000');
      await settleFrames(tester);

      expect(router.current.name, isNot(ServerSetupRoute.name));
    });
  });

  group('Retry офлайн-баннера', () {
    testWidgets('вызывает checkAuthStatus, а не просто invalidate',
        (tester) async {
      await container
          .read(settingsProvider.notifier)
          .setServerUrl('http://localhost:8080/api');
      await container
          .read(settingsProvider.notifier)
          .setTokens('token', 'refresh');
      fakeRepo.onGetCurrentUser = () async =>
          const Left(NetworkFailure(message: 'No connection'));
      await container.read(authProvider.notifier).checkAuthStatus();
      expect(container.read(authProvider), isA<AuthError>());

      var getUserCalls = 0;
      fakeRepo.onGetCurrentUser = () async {
        getUserCalls++;
        return const Left(NetworkFailure(message: 'No connection'));
      };

      await pumpFluxApp(tester);
      await settleFrames(tester);

      // Офлайн-режим: MainRoute показан, баннер с Retry виден.
      expect(router.current.name, MainRoute.name);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await settleFrames(tester);

      expect(getUserCalls, 1);
      // Приложение остаётся в офлайн-режиме, а не на экране логина.
      expect(router.current.name, MainRoute.name);
    });
  });

  group('AuthGuard', () {
    testWidgets('AuthError без offline отправляет на LoginRoute',
        (tester) async {
      fakeRepo.onGetCurrentUser =
          () async => const Left(ServerFailure(message: 'Server error'));
      await container.read(authProvider.notifier).checkAuthStatus();
      final state = container.read(authProvider);
      expect(state, isA<AuthError>());
      expect((state as AuthError).isOffline, isFalse);

      await pumpFluxApp(tester);
      await settleFrames(tester);

      unawaited(router.push(const SettingsRoute()));
      await settleFrames(tester);

      expect(router.current.name, LoginRoute.name);
    });

    testWidgets('AuthError + isOffline пропускает на защищённый маршрут',
        (tester) async {
      fakeRepo.onGetCurrentUser =
          () async => const Left(NetworkFailure(message: 'No connection'));
      await container.read(authProvider.notifier).checkAuthStatus();
      final state = container.read(authProvider);
      expect(state, isA<AuthError>());
      expect((state as AuthError).isOffline, isTrue);

      await pumpFluxApp(tester);
      await settleFrames(tester);

      unawaited(router.push(const SettingsRoute()));
      await settleFrames(tester);

      expect(router.current.name, SettingsRoute.name);
    });
  });
}
