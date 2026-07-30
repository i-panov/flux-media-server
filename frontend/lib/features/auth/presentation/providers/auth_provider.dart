import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:flux_media_server/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/providers/watch_progress_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flux_media_server/shared/models/user.dart';

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
  const factory AuthState.error({required String message}) = AuthError;
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

  Future<void> requestCode(String email) async {
    state = const AuthState.loading();
    debugPrint('[Auth] requestCode: calling API for $email');
    final result = await _requestCode(email);
    debugPrint('[Auth] requestCode: result=$result');
    result.fold(
      (failure) {
        debugPrint('[Auth] requestCode: failure=${failure.message}');
        state = AuthState.error(message: failure.message);
      },
      (debugCode) {
        debugPrint('[Auth] requestCode: success, debugCode=$debugCode');
        state = AuthState.codeSent(
          email: email,
          debugCode: debugCode,
        );
      },
    );
  }

  Future<void> verifyCode(String email, String code) async {
    state = const AuthState.loading();
    final result =
        await _verifyCode(VerifyCodeParams(email: email, code: code));
    await result.fold<Future<void>>(
      (failure) async => state = AuthState.error(message: failure.message),
      (data) async {
        await _ref
            .read(settingsProvider.notifier)
            .setTokens(data.token, data.refreshToken);
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
          state = AuthState.error(message: failure.message);
        }
      },
      (user) async => state = AuthState.authenticated(user: user),
    );
  }

  Future<void> logout() async {
    await _ref.read(settingsProvider.notifier).logout();
    _ref.invalidate(mediaListProvider('video'));
    _ref.invalidate(mediaListProvider('audio'));
    _ref.invalidate(favoritesProvider);
    _ref.invalidate(collectionsProvider);
    _ref.invalidate(libraryProvider);
    _ref.invalidate(watchProgressProvider);
    _ref.invalidate(settingsProvider);
    state = const AuthState.initial();
  }
}

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.watch(apiClientProvider));
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
