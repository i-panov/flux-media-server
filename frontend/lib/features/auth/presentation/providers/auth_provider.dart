import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:flux_media_server/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/watch_progress_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_provider.freezed.dart';

extension FailureNetworkX on Failure {
  bool get isNetworkFailure => this is NetworkFailure;
}

@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthInitial;
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.codeSent({
    required String email,
    String? debugCode,
  }) = AuthCodeSent;
  const factory AuthState.authenticated({required User user}) =
      AuthAuthenticated;
  const factory AuthState.error({
    required String message,
    @Default(false) bool isOffline,
  }) = AuthError;
}

class AuthNotifier extends Notifier<AuthState> {
  late final RequestCode _requestCode;
  late final VerifyCode _verifyCode;
  late final GetCurrentUser _getCurrentUser;

  @override
  AuthState build() {
    _requestCode = ref.watch(requestCodeProvider);
    _verifyCode = ref.watch(verifyCodeProvider);
    _getCurrentUser = ref.watch(getCurrentUserProvider);
    return const AuthState.initial();
  }

  /// Guard от гонок: повторный requestCode, пока идёт запрос,
  /// возвращает false (запрос не выполнен).
  bool _requestInFlight = false;

  /// Поколение асинхронных проверок сессии: ответ checkAuthStatus,
  /// начатой до logout/новой проверки, игнорируется.
  int _generation = 0;

  /// Email последнего успешного requestCode — для восстановления формы
  /// логина после ошибки верификации.
  String? lastRequestedEmail;

  /// Отправляет код на [email]. Возвращает true, если запрос реально
  /// выполнен и код отправлен; false — повторный вызов во время
  /// летящего запроса или ошибка.
  Future<bool> requestCode(String email) async {
    if (_requestInFlight) return false;
    _requestInFlight = true;
    try {
      final result = await _requestCode(email);
      return result.fold(
        (failure) {
          state = AuthState.error(
            message: failure.message,
            isOffline: failure.isNetworkFailure,
          );
          return false;
        },
        (_) {
          lastRequestedEmail = email;
          state = AuthState.codeSent(
            email: email,
            debugCode: _requestCode.lastDebugCode,
          );
          return true;
        },
      );
    } finally {
      _requestInFlight = false;
    }
  }

  /// Верифицирует код. Глобальный AuthLoading здесь НЕ выставляется:
  /// splash размонтировал бы Navigator и CodeScreen (потеря cooldown
  /// и состояния формы) — локальную загрузку показывает сам экран.
  Future<void> verifyCode(String email, String code) async {
    final result =
        await _verifyCode(VerifyCodeParams(email: email, code: code));
    await result.fold<Future<void>>(
      (failure) async {
        state = AuthState.error(
          message: failure.message,
          isOffline: failure.isNetworkFailure,
        );
      },
      (data) async {
        await ref
            .read(settingsProvider.notifier)
            .setTokens(data.token, data.refreshToken);
        _invalidateSessionProviders();
        state = AuthState.authenticated(user: data.user);
      },
    );
  }

  Future<void> checkAuthStatus() async {
    final generation = ++_generation;
    state = const AuthState.loading();
    final result = await _getCurrentUser(const NoParams());
    // Ответ проверки, начатой до logout/повторной проверки, устарел.
    if (generation != _generation) return;
    await result.fold<Future<void>>(
      (failure) async {
        if (failure is AuthFailure) {
          // Token is invalid — clear it to prevent infinite 401 loop
          await ref.read(settingsProvider.notifier).logout();
          _invalidateSessionProviders();
          state = const AuthState.initial();
        } else {
          // Network/server error — keep the stored session so the user
          // isn't logged out just because the server is unreachable.
          state = AuthState.error(
            message: failure.message,
            isOffline: failure.isNetworkFailure,
          );
        }
      },
      (user) async => state = AuthState.authenticated(user: user),
    );
  }

  /// Сессия истекла на уровне токенов (refresh отвергнут): токены уже
  /// очищены refresher'ом, сбрасываем состояние, чтобы UI ушёл на логин.
  void expireSession() {
    state = const AuthState.initial();
  }

  Future<void> logout() async {
    // Ответы незавершённых checkAuthStatus после logout не применяем.
    _generation++;
    // Очищаем офлайн-кеш пользователя (файлы + метаданные) до сброса
    // сессии, чтобы id пользователя ещё был доступен из состояния auth.
    await ref.read(offlineCacheServiceProvider).clearUserCache();
    await ref.read(settingsProvider.notifier).logout();
    _invalidateSessionProviders();
    // Do NOT invalidate settingsProvider — it holds the serverUrl which is
    // needed for the login screen to know where to send credentials.
    state = const AuthState.initial();
  }

  /// Инвалидирует кэшированные провайдеры сессии, чтобы они
  /// перечитали данные с новым токеном (или после logout).
  void _invalidateSessionProviders() {
    ref
      ..invalidate(mediaListProvider('video'))
      ..invalidate(mediaListProvider('audio'))
      ..invalidate(favoritesProvider)
      ..invalidate(collectionsProvider)
      ..invalidate(watchProgressProvider);
  }
}

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(
    ref.watch(authApiClientProvider),
    refresher: ref.watch(authTokenRefresherProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepositoryImpl>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final requestCodeProvider = Provider<RequestCode>((ref) {
  return RequestCode(ref.watch(authRepositoryProvider));
});

final verifyCodeProvider = Provider<VerifyCode>((ref) {
  return VerifyCode(ref.watch(authRepositoryProvider));
});

final getCurrentUserProvider = Provider<GetCurrentUser>((ref) {
  return GetCurrentUser(ref.watch(authRepositoryProvider));
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
