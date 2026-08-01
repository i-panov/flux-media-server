import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

void main() {
  group('Response Handler', () {
    group('safeApiCall', () {
      test('should return data for successful call', () async {
        final result = await safeApiCall(() async => 'success');

        expect(result, 'success');
      });

      test('should rethrow AuthException', () async {
        expect(
          () => safeApiCall(() async => throw const AuthException(message: 'Auth failed')),
          throwsA(const TypeMatcher<AuthException>()),
        );
      });

      test('should rethrow ServerException', () async {
        expect(
          () => safeApiCall(() async => throw const ServerException(message: 'Server error')),
          throwsA(const TypeMatcher<ServerException>()),
        );
      });

      test('should convert SocketException to NetworkException', () async {
        expect(
          () => safeApiCall(() async => throw const SocketException('Connection failed')),
          throwsA(const TypeMatcher<NetworkException>()),
        );
      });

      test('should convert HttpException to NetworkException', () async {
        expect(
          () => safeApiCall(() async => throw const HttpException('HTTP error')),
          throwsA(const TypeMatcher<NetworkException>()),
        );
      });

      test('should convert TimeoutException to NetworkException', () async {
        expect(
          () => safeApiCall(() async => throw TimeoutException('Request timed out', const Duration(seconds: 30))),
          throwsA(const TypeMatcher<NetworkException>()),
        );
      });

      test('should convert IOException to NetworkException', () async {
        expect(
          () => safeApiCall(() async => throw const FileSystemException('IO error')),
          throwsA(const TypeMatcher<NetworkException>()),
        );
      });
    });

    group('safeRepositoryCall', () {
      test('should return Right(data) for successful call', () async {
        final result = await safeRepositoryCall(() async => 'success');

        expect(result, const TypeMatcher<Right<Failure, String>>());
        expect(result.getOrElse((_) => ''), 'success');
      });

      test('should return Left(AuthFailure) for AuthException', () async {
        final result = await safeRepositoryCall(() async => throw const AuthException(message: 'Auth failed'));

        expect(result, const TypeMatcher<Left<Failure, dynamic>>());
        expect(result.isLeft(), isTrue);
        result.mapLeft((failure) {
          expect(failure, const TypeMatcher<AuthFailure>());
          expect(failure.message, 'Auth failed');
          return failure;
        });
      });

      test('should return Left(ServerFailure) for ServerException', () async {
        final result = await safeRepositoryCall(() async => throw const ServerException(message: 'Server error'));

        expect(result, const TypeMatcher<Left<Failure, dynamic>>());
        expect(result.isLeft(), isTrue);
        result.mapLeft((failure) {
          expect(failure, const TypeMatcher<ServerFailure>());
          expect(failure.message, 'Server error');
          return failure;
        });
      });

      test('should return Left(NetworkFailure) for NetworkException', () async {
        final result = await safeRepositoryCall(() async => throw const NetworkException(message: 'Network error'));

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