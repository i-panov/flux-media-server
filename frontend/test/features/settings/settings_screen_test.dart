import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/settings/presentation/screens/settings_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCache extends OfflineCacheService {
  new({required super.prefs}) : super('');

  @override
  Future<int> getCacheSize() async => 0;
}

class _FakeAuthNotifier extends AuthNotifier {
  new([this._user]);

  final User? _user;

  @override
  AuthState build() =>
      _user != null ? AuthState.authenticated(user: _user) : const AuthState.initial();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({User? user}) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => _FakeAuthNotifier(user)),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpScreen(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
  }

  group('SettingsScreen account section', () {
    testWidgets('показывает email залогиненного', (tester) async {
      await pumpScreen(
        tester,
        makeContainer(
          user: const User(id: 7, email: 'u@example.com'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('u@example.com'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
    });

    testWidgets('без сессии email нет, только выход', (tester) async {
      await pumpScreen(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('u@example.com'), findsNothing);
      expect(find.text('Logout'), findsOneWidget);
    });
  });
}
