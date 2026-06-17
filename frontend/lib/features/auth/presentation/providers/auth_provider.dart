import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/auth/domain/usecases/request_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/verify_code.dart';
import 'package:flux_media_server/features/auth/domain/usecases/get_current_user.dart';
import 'package:flux_media_server/shared/models/user.dart';

part 'auth_provider.freezed.dart';

@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthInitial;
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.codeSent({required String email}) = AuthCodeSent;
  const factory AuthState.authenticated({required User user}) = AuthAuthenticated;
  const factory AuthState.error({required String message}) = AuthError;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required RequestCode requestCode,
    required VerifyCode verifyCode,
    required GetCurrentUser getCurrentUser,
  })  : _requestCode = requestCode,
        _verifyCode = verifyCode,
        _getCurrentUser = getCurrentUser,
        super(const AuthState.initial());

  final RequestCode _requestCode;
  final VerifyCode _verifyCode;
  final GetCurrentUser _getCurrentUser;

  Future<void> requestCode(String email) async {
    state = const AuthState.loading();
    final result = await _requestCode(email);
    result.fold(
      (failure) => state = AuthState.error(message: failure.message),
      (_) => state = AuthState.codeSent(email: email),
    );
  }

  Future<void> verifyCode(String email, String code) async {
    state = const AuthState.loading();
    final result = await _verifyCode(VerifyCodeParams(email: email, code: code));
    result.fold(
      (failure) => state = AuthState.error(message: failure.message),
      (data) => state = AuthState.authenticated(user: data.user),
    );
  }

  Future<void> checkAuthStatus() async {
    state = const AuthState.loading();
    final result = await _getCurrentUser(const NoParams());
    result.fold(
      (failure) => state = const AuthState.initial(),
      (user) => state = AuthState.authenticated(user: user),
    );
  }
}
