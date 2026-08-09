import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:fpdart/fpdart.dart';

/// Checks the HTTP response status and throws appropriate exceptions.
///
/// - 401 → [AuthException] (session expired)
/// - 200, 201 → success (no-op)
/// - anything else → [ServerException] with error message from body
void checkResponse(Response<dynamic> response, String defaultMessage) {
  if (response.statusCode == 401) {
    throw const AuthException(message: 'Session expired');
  }
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw ServerException(
      message: response.body is Map<String, dynamic>
          ? (response.body as Map<String, dynamic>)['error'] as String? ??
              defaultMessage
          : defaultMessage,
    );
  }
}

/// Wraps an async operation, converting low-level exceptions into
/// domain-level [AuthException], [NetworkException], or [ServerException].
/// Retries once on [TokenRefreshedException] (token was just refreshed).
Future<T> safeApiCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on TokenRefreshedException {
    // Token was refreshed — retry with the new token
    return call();
  } on AuthException {
    rethrow;
  } on ServerException {
    rethrow;
  } on NetworkException {
    rethrow;
  } on SocketException catch (e) {
    if (e.message.contains('Broken pipe') || e.message.contains('errno = 32')) {
      throw const ServerException(
        message: 'File too large for server to accept',
      );
    }
    throw const NetworkException(message: 'No internet connection');
  } on HttpException {
    throw const NetworkException(message: 'Network error');
  } on TimeoutException {
    throw const NetworkException(message: 'Request timed out');
  } on IOException {
    throw const NetworkException(message: 'Network error');
  } on Exception catch (e) {
    throw ServerException(message: e.toString());
  }
}

/// Wraps a repository call with token-refresh retry logic.
/// Retries once on [TokenRefreshedException], converts exceptions to [Failure].
Future<Either<Failure, T>> safeRepositoryCall<T>(
  Future<T> Function() call,
) async {
  try {
    return Right(await call());
  } on TokenRefreshedException {
    // Token was just refreshed — retry with the new token.
    try {
      return Right(await call());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: e.toString()));
    }
  } on AuthException catch (e) {
    return Left(AuthFailure(message: e.message));
  } on ServerException catch (e) {
    return Left(ServerFailure(message: e.message));
  } on NetworkException catch (e) {
    return Left(NetworkFailure(message: e.message));
  } catch (e) {
    return Left(ServerFailure(message: e.toString()));
  }
}
