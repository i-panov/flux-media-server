import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Клиент, фиксирующий закрытие: доказывает, что старый инстанс
/// действительно уходит через `ref.onDispose(close)`, а не висит
/// с открытыми сокетами.
class _CloseTrackingClient extends TimeoutHttpClient {
  new({required super.trustSelfSignedCertificates});

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

/// Флаг доверия самоподписанному сертификату: дефолт, персист и
/// пересоздание обоих HTTP-клиентов.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(SharedPreferences prefs) => ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  group('trustSelfSignedCertificates', () {
    test('дефолт — false, оба клиента без доверия', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).init();

      final chopperClient = container.read(httpClientProvider);
      expect(chopperClient.trustSelfSignedCertificates, isFalse);

      final directClient =
          container.read(directHttpClientProvider) as TimeoutHttpClient;
      expect(directClient.trustSelfSignedCertificates, isFalse);
    });

    test('персист флага и пересоздание обоих клиентов', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).init();
      await container
          .read(settingsProvider.notifier)
          .setTrustSelfSignedCertificates(value: true);

      expect(
        container.read(httpClientProvider).trustSelfSignedCertificates,
        isTrue,
      );
      expect(
        (container.read(
          directHttpClientProvider,
        ) as TimeoutHttpClient).trustSelfSignedCertificates,
        isTrue,
      );
      // Флаг пережил рестарт приложения.
      expect(
        container.read(settingsProvider).settings.trustSelfSignedCertificates,
        isTrue,
      );
    });

    test('тогл туда-обратно пересоздаёт клиенты с актуальным флагом', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).init();
      final first = container.read(directHttpClientProvider);

      await container
          .read(settingsProvider.notifier)
          .setTrustSelfSignedCertificates(value: true);
      final second = container.read(directHttpClientProvider);
      expect(identical(first, second), isFalse);
      expect((second as TimeoutHttpClient).trustSelfSignedCertificates, isTrue);

      await container
          .read(settingsProvider.notifier)
          .setTrustSelfSignedCertificates(value: false);
      final third = container.read(directHttpClientProvider);
      expect(identical(second, third), isFalse);
      expect((third as TimeoutHttpClient).trustSelfSignedCertificates, isFalse);
      // Старые инстансы при пересоздании уходят через ref.onDispose(close)
      // и не копятся: каждый тогл даёт ровно один живой клиент.
    });

    test('старый клиент закрывается при пересоздании', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          directHttpClientProvider.overrideWith((ref) {
            final flag = ref.watch(
              settingsProvider.select(
                (s) => s.settings.trustSelfSignedCertificates,
              ),
            );
            final client = _CloseTrackingClient(
              trustSelfSignedCertificates: flag,
            );
            ref.onDispose(client.close);
            return client;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).init();
      final first =
          container.read(directHttpClientProvider) as _CloseTrackingClient;

      await container
          .read(settingsProvider.notifier)
          .setTrustSelfSignedCertificates(value: true);
      final second = container.read(directHttpClientProvider);

      expect(identical(first, second), isFalse);
      expect(first.closed, isTrue);
    });

    test('chopper-клиент тоже закрывается при пересоздании', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          httpClientProvider.overrideWith((ref) {
            final flag = ref.watch(
              settingsProvider.select(
                (s) => s.settings.trustSelfSignedCertificates,
              ),
            );
            final client = _CloseTrackingClient(
              trustSelfSignedCertificates: flag,
            );
            ref.onDispose(client.close);
            return client;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).init();
      final first = container.read(httpClientProvider) as _CloseTrackingClient;

      await container
          .read(settingsProvider.notifier)
          .setTrustSelfSignedCertificates(value: true);
      final second = container.read(httpClientProvider);

      expect(identical(first, second), isFalse);
      expect(first.closed, isTrue);
      expect(second.trustSelfSignedCertificates, isTrue);
    });
  });
}
