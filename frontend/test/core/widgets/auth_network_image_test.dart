import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';
import 'package:flux_media_server/core/widgets/auth_network_image.dart';

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.settings);

  AppSettings settings;

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> setServerUrl(String url) async {
    settings = settings.copyWith(serverUrl: url);
  }

  @override
  Future<void> setAuthToken(String token) async {
    settings = settings.copyWith(authToken: token);
  }

  @override
  Future<void> clearAuthToken() async {
    settings = settings.copyWith(authToken: null);
  }

  @override
  Future<void> setRefreshToken(String token) async {
    settings = settings.copyWith(refreshToken: token);
  }

  @override
  Future<void> clearRefreshToken() async {
    settings = settings.copyWith(refreshToken: null);
  }

  @override
  String getLocale() => 'en';

  @override
  Future<void> setLocale(String locale) async {}
}

void main() {
  group('shouldAttachAuthHeader', () {
    const baseUrl = 'http://host:8080/api';

    test('attaches token for same-origin URLs', () {
      expect(
        shouldAttachAuthHeader(
          'http://host:8080/api/media/1/thumb',
          baseUrl,
          'token',
        ),
        isTrue,
      );
    });

    test('no token for foreign hosts (Bearer must not leak)', () {
      expect(
        shouldAttachAuthHeader(
          'https://imgur.com/cover.jpg',
          baseUrl,
          'token',
        ),
        isFalse,
      );
      expect(
        shouldAttachAuthHeader(
          'https://evil.com/host:8080',
          baseUrl,
          'token',
        ),
        isFalse,
      );
    });

    test('no headers without a token or base URL', () {
      expect(
        shouldAttachAuthHeader('http://host:8080/api/x', baseUrl, null),
        isFalse,
      );
      expect(
        shouldAttachAuthHeader('http://host:8080/api/x', null, 'token'),
        isFalse,
      );
    });
  });

  group('AuthNetworkImage', () {
    testWidgets('recreates the image load when the token changes',
        (tester) async {
      final repo = _FakeSettingsRepository(
        const AppSettings(
          serverUrl: 'http://host:8080/api',
          authToken: 'token-1',
        ),
      );
      final notifier = SettingsNotifier(repo);
      await notifier.init();

      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AuthNetworkImage(
              imageUrl: 'http://host:8080/api/media/1/thumb',
            ),
          ),
        ),
      );

      Key? keyOf() => tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .key;

      final keyBefore = keyOf();

      // Смена токена (refresh) обязана пересоздать загрузку.
      await notifier.setTokens('token-2', 'refresh-2');
      await tester.pump();

      expect(keyOf(), isNot(keyBefore));
    });
  });
}
