import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;

void main() {
  group('Response Handler', () {
    group('checkResponse', () {
      Response<dynamic> response(int statusCode, {Object? body}) =>
          Response<dynamic>(http.Response('', statusCode), body);

      test('does not throw for 200', () {
        expect(
          () => checkResponse(response(200), 'Default message'),
          returnsNormally,
        );
      });

      test('does not throw for 201', () {
        expect(
          () => checkResponse(response(201), 'Default message'),
          returnsNormally,
        );
      });

      test('throws AuthException for 401', () {
        expect(
          () => checkResponse(response(401), 'Default message'),
          throwsA(isA<AuthException>()),
        );
      });

      test('throws AuthException with error from body for 401', () {
        expect(
          () => checkResponse(
            response(401, body: {'error': 'Invalid or expired code'}),
            'Default message',
          ),
          throwsA(
            isA<AuthException>()
                .having((e) => e.message, 'message', 'Invalid or expired code'),
          ),
        );
      });

      test('uses default message for 401 without a usable error field', () {
        expect(
          () => checkResponse(response(401, body: {'error': 42}), 'Default'),
          throwsA(
            isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Session expired',
          ),
          ),
        );
      });

      test('throws ServerException with body message for 500', () {
        expect(
          () => checkResponse(
            response(500, body: {'error': 'Boom'}),
            'Default message',
          ),
          throwsA(
            isA<ServerException>()
                .having((e) => e.message, 'message', 'Boom'),
          ),
        );
      });

      test('falls back to default message when error is not a string', () {
        expect(
          () => checkResponse(
            response(500, body: {'error': 42}),
            'Default message',
          ),
          throwsA(
            isA<ServerException>()
                .having((e) => e.message, 'message', 'Default message'),
          ),
        );
      });

      test('falls back to default message when body is not a map', () {
        expect(
          () => checkResponse(
            response(500, body: 'plain text'),
            'Default message',
          ),
          throwsA(
            isA<ServerException>()
                .having((e) => e.message, 'message', 'Default message'),
          ),
        );
      });
    });

    group('safeRepositoryCall retry', () {
      test('retries once on TokenRefreshedException and succeeds', () async {
        var calls = 0;
        final result = await safeRepositoryCall(() async {
          calls++;
          if (calls == 1) throw const TokenRefreshedException();
          return 'recovered';
        });

        expect(calls, 2);
        expect(result.isRight(), isTrue);
        expect(result.getOrElse((_) => ''), 'recovered');
      });

      test('returns Left when both attempts fail', () async {
        var calls = 0;
        final result = await safeRepositoryCall(() async {
          calls++;
          if (calls == 1) throw const TokenRefreshedException();
          throw const ServerException(message: 'Still failing');
        });

        expect(calls, 2);
        expect(result.isLeft(), isTrue);
        final failure = result.fold((l) => l, (_) => null);
        expect(failure, isA<ServerFailure>());
        expect(failure?.message, 'Still failing');
      });

      test('second 401 after retry maps to AuthFailure', () async {
        var calls = 0;
        final result = await safeRepositoryCall(() async {
          calls++;
          throw const TokenRefreshedException();
        });

        expect(calls, 2);
        expect(result.isLeft(), isTrue);
        final failure = result.fold((l) => l, (_) => null);
        expect(failure, isA<AuthFailure>());
      });

      test('UploadCancelledException maps to UploadCancelledFailure', () async {
        final result = await safeRepositoryCall(
          () async => throw const UploadCancelledException(),
        );

        final failure = result.fold((l) => l, (_) => null);
        expect(failure, isA<UploadCancelledFailure>());
      });
    });

    group('safeRepositoryCall network errors', () {
      test('http.ClientException becomes NetworkFailure', () async {
        final result = await safeRepositoryCall(
          () async => throw http.ClientException('Connection refused'),
        );

        final failure = result.fold((l) => l, (_) => null);
        expect(failure, isA<NetworkFailure>());
        expect(failure?.message, 'Connection refused');
      });

      test('SocketException becomes NetworkFailure', () async {
        final result = await safeRepositoryCall(
          () async => throw const SocketException('Network is unreachable'),
        );

        final failure = result.fold((l) => l, (_) => null);
        expect(failure, isA<NetworkFailure>());
        expect(failure?.message, 'Network is unreachable');
      });

      test('TimeoutException becomes NetworkFailure', () async {
        final result = await safeRepositoryCall(
          () async => throw TimeoutException('Timed out'),
        );

        final failure = result.fold((l) => l, (_) => null);
        expect(failure, isA<NetworkFailure>());
      });
    });

    group('safeRepositoryCall', () {
      test('should return Right(data) for successful call', () async {
        final result = await safeRepositoryCall(() async => 'success');

        expect(result, const TypeMatcher<Right<Failure, String>>());
        expect(result.getOrElse((_) => ''), 'success');
      });

      test('should return Left(AuthFailure) for AuthException', () async {
        final result = await safeRepositoryCall(
          () async => throw const AuthException(message: 'Auth failed'),
        );

        expect(result, const TypeMatcher<Left<Failure, dynamic>>());
        expect(result.isLeft(), isTrue);
        result.mapLeft((failure) {
          expect(failure, const TypeMatcher<AuthFailure>());
          expect(failure.message, 'Auth failed');
          return failure;
        });
      });

      test('should return Left(ServerFailure) for ServerException', () async {
        final result = await safeRepositoryCall(
          () async => throw const ServerException(message: 'Server error'),
        );

        expect(result, const TypeMatcher<Left<Failure, dynamic>>());
        expect(result.isLeft(), isTrue);
        result.mapLeft((failure) {
          expect(failure, const TypeMatcher<ServerFailure>());
          expect(failure.message, 'Server error');
          return failure;
        });
      });

      test('should return Left(NetworkFailure) for NetworkException', () async {
        final result = await safeRepositoryCall(
          () async => throw const NetworkException(message: 'Network error'),
        );

        expect(result, const TypeMatcher<Left<Failure, dynamic>>());
        expect(result.isLeft(), isTrue);
        result.mapLeft((failure) {
          expect(failure, const TypeMatcher<NetworkFailure>());
          expect(failure.message, 'Network error');
          return failure;
        });
      });
    });
  });
}
