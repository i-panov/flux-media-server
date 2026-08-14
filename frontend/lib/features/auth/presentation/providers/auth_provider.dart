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

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required Ref ref,
    required RequestCode requestCode,
    required VerifyCode verifyCode,
    required GetCurrentUser getCurrentUser,
  })  : _ref = ref,
        _requestCode = requestCode,
        _verifyCode = verifyCode,
        _getCurrentUser = getCurrentUser,
        super(const AuthState.initial());

  final Ref _ref;
  final RequestCode _requestCode;
  final VerifyCode _verifyCode;
  final GetCurrentUser _getCurrentUser;

  /// Guard от гонок: игнорируем повторный requestCode, пока идёт запрос.
  bool _requestInFlight = false;

  Future<void> requestCode(String email) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    try {
      // Don't set AuthLoading here — FluxApp's showSplash catches it
      // and removes LoginScreen from the widget tree, breaking navigation.
      final result = await _requestCode(email);
      result.fold(
        (failure) {
          final isOffline = failure is NetworkFailure;
          state =
              AuthState.error(message: failure.message, isOffline: isOffline);
        },
        (_) {
          state = AuthState.codeSent(
            email: email,
            debugCode: _requestCode.lastDebugCode,
          );
        },
      );
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> verifyCode(String email, String code) async {
    state = const AuthState.loading();
    final result =
        await _verifyCode(VerifyCodeParams(email: email, code: code));
    await result.fold<Future<void>>(
      (failure) async {
        final isOffline = failure is NetworkFailure;
        state = AuthState.error(message: failure.message, isOffline: isOffline);
      },
      (data) async {
        await _ref
            .read(settingsProvider.notifier)
            .setTokens(data.token, data.refreshToken);
        _invalidateSessionProviders();
        state = AuthState.authenticated(user: data.user);
      },
    );
  }

  Future<void> checkAuthStatus() async {
    state = const AuthState.loading();
    final result = await _getCurrentUser(const NoParams());
    await result.fold<Future<void>>(
      (failure) async {
        if (failure is AuthFailure) {
          // Token is invalid — clear it to prevent infinite 401 loop
          await _ref.read(settingsProvider.notifier).logout();
          state = const AuthState.initial();
        } else {
          // Network/server error — keep the stored session so the user
          // isn't logged out just because the server is unreachable.
          final isOffline = failure is NetworkFailure;
          state = AuthState.error(
            message: failure.message,
            isOffline: isOffline,
          );
        }
      },
      (user) async => state = AuthState.authenticated(user: user),
    );
  }

  Future<void> logout() async {
    // Очищаем офлайн-кеш пользователя (файлы + метаданные) до сброса
    // сессии, чтобы id пользователя ещё был доступен из состояния auth.
    await _ref.read(offlineCacheServiceProvider).clearUserCache();
    await _ref.read(settingsProvider.notifier).logout();
    _invalidateSessionProviders();
    // Do NOT invalidate settingsProvider — it holds the serverUrl which is
    // needed for the login screen to know where to send credentials.
    state = const AuthState.initial();
  }

  /// Инвалидирует кэшированные провайдеры сессии, чтобы они
  /// перечитали данные с новым токеном (или после logout).
  void _invalidateSessionProviders() {
    _ref
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

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref: ref,
    requestCode: ref.watch(requestCodeProvider),
    verifyCode: ref.watch(verifyCodeProvider),
    getCurrentUser: ref.watch(getCurrentUserProvider),
  );
});
