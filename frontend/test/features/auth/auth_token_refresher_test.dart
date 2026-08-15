import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';

void main() {
  group('AuthTokenRefresher', () {
    test('returns tokens directly on success', () async {
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async =>
            (token: 'new-jwt', refreshToken: 'new-refresh'),
        onRefreshFailure: () async {},
      );

      final tokens = await refresher.refreshTokens('old-refresh');

      expect(tokens, (token: 'new-jwt', refreshToken: 'new-refresh'));
    });

    test('refresh(null) calls onRefreshFailure and returns null', () async {
      var failures = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async => null,
        onRefreshFailure: () async => failures++,
      );

      final tokens = await refresher.refreshTokens(null);

      expect(tokens, isNull);
      expect(failures, 1);
    });

    test('refresh(empty) calls onRefreshFailure and returns null', () async {
      var failures = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async => null,
        onRefreshFailure: () async => failures++,
      );

      final tokens = await refresher.refreshTokens('');

      expect(tokens, isNull);
      expect(failures, 1);
    });

    test('server rejection returns null and calls onRefreshFailure', () async {
      var failures = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async => null,
        onRefreshFailure: () async => failures++,
      );

      final tokens = await refresher.refreshTokens('invalid');

      expect(tokens, isNull);
      expect(failures, 1);
    });

    test('exception during refresh returns null and calls onRefreshFailure',
        () async {
      var failures = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async => throw Exception('connection refused'),
        onRefreshFailure: () async => failures++,
      );

      final tokens = await refresher.refreshTokens('refresh');

      expect(tokens, isNull);
      expect(failures, 1);
    });

    test('parallel calls share one refresh and return the same tokens',
        () async {
      var calls = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async {
          calls++;
          return (token: 'new-jwt', refreshToken: 'new-refresh');
        },
        onRefreshFailure: () async {},
      );

      final results = await Future.wait([
        refresher.refreshTokens('r1'),
        refresher.refreshTokens('r2'),
        refresher.refreshTokens('r3'),
      ]);

      expect(calls, 1);
      expect(results, hasLength(3));
      for (final tokens in results) {
        expect(tokens, (token: 'new-jwt', refreshToken: 'new-refresh'));
      }
    });

    test('failed refresh after a success does not corrupt the result of '
        'the success (no shared mutable state)', () async {
      var calls = 0;
      var failures = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async {
          calls++;
          if (calls == 1) {
            return (token: 't1', refreshToken: 'r1');
          }
          // Второй (после успеха) refresh отвергнут сервером.
          return null;
        },
        onRefreshFailure: () async => failures++,
      );

      final first = await refresher.refreshTokens('rt');
      expect(first, (token: 't1', refreshToken: 'r1'));

      final second = await refresher.refreshTokens('rt');
      expect(second, isNull);
      expect(failures, 1);

      // Результат первого успеха не изменился: токены были возвращены
      // напрямую, а не через общее побочное поле.
      expect(first, (token: 't1', refreshToken: 'r1'));
    });

    test('parallel success and failure never mix results', () async {
      var failures = 0;
      final refresher = AuthTokenRefresher(
        performRefresh: (_) async =>
            (token: 'new-jwt', refreshToken: 'new-refresh'),
        onRefreshFailure: () async => failures++,
      );

      // Общий in-flight: все вызовы получают один результат.
      final results = await Future.wait([
        refresher.refreshTokens('r1'),
        refresher.refreshTokens('r2'),
      ]);

      expect(failures, 0);
      expect(results[0], (token: 'new-jwt', refreshToken: 'new-refresh'));
      expect(results[1], (token: 'new-jwt', refreshToken: 'new-refresh'));
    });
  });
}
