import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';

/// Auth без поднятия цепочки API-клиентов, с ручной сменой состояния.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.initial();
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
    );
    addTearDown(container.dispose);
  });

  bool isOffline() => container.read(isOfflineProvider);

  void setNetworkStatus({required bool offline}) {
    container.read(networkStatusProvider.notifier).state = offline;
  }

  group('isOfflineProvider', () {
    test('initial без сетевых сбоев — онлайн', () {
      expect(isOffline(), isFalse);
    });

    test('сетевой сбой списка при initial — офлайн', () {
      setNetworkStatus(offline: true);

      expect(isOffline(), isTrue);
    });

    test('не-сетевая ошибка auth не прячет сетевой сбой', () {
      // Регрессия: ветка AuthError возвращала только authState.isOffline
      // и игнорировала networkStatus — баннер пропадал.
      container.read(authProvider.notifier).state = const AuthState.error(message: 'Session expired');
      setNetworkStatus(offline: true);

      expect(isOffline(), isTrue);
    });

    test('не-сетевая ошибка auth без сбоев — онлайн', () {
      container.read(authProvider.notifier).state = const AuthState.error(message: 'Session expired');

      expect(isOffline(), isFalse);
    });

    test('сетевая ошибка auth без сбоев списков — офлайн', () {
      container.read(authProvider.notifier).state = const AuthState.error(message: 'No connection', isOffline: true);

      expect(isOffline(), isTrue);
    });
  });
}
