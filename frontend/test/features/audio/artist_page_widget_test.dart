import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/audio/presentation/screens/artist_page.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

Media _track(int id, String title) => Media(
  id: id,
  title: title,
  type: MediaType.audio,
  fileSize: 1,
  artists: const [Artist(id: 1, name: 'Artist One')],
);

class _FakeMediaRepository implements MediaRepository {
  List<Media> items = [_track(1, 'First'), _track(2, 'Second')];
  int total = 2;

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async => Right((items: items, total: total));

  @override
  Future<Either<Failure, List<Artist>>> getArtists() async => const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache extends OfflineCacheService {
  new({required super.prefs}) : super('');

  @override
  Future<bool> isCached(int mediaId) async => false;

  @override
  Future<List<int>> getCachedIds() async => [];

  @override
  Future<List<Media>> getCachedMedia() async => [];
}

/// Координатор без плеера: ряды слушают его состояние, а настоящий build
/// тянет audioHandlerProvider, которого в виджет-тестах нет.
class _IdleCoordinator extends PlaybackCoordinator {
  @override
  PlaybackState build() => const PlaybackState.initial();
}

/// Auth в начальном состоянии без поднятия цепочки API-клиентов.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.initial();
}

void main() {
  late SharedPreferences prefs;
  late FakeFavoritesRepository favoritesRepo;
  late _FakeMediaRepository mediaRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    favoritesRepo = FakeFavoritesRepository()
      ..onGetFavorites = () async => const Right([]);
    mediaRepo = _FakeMediaRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
        playbackCoordinatorProvider.overrideWith(_IdleCoordinator.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpPage(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ArtistPage(artistId: 1, artistName: 'Artist One'),
        ),
      ),
    );
  }

  group('ArtistPage', () {
    testWidgets('показывает треки артиста', (tester) async {
      final container = makeContainer();
      await pumpPage(tester, container);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('без треков показывает заглушку', (tester) async {
      mediaRepo
        ..items = []
        ..total = 0;
      await pumpPage(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('First'), findsNothing);
      expect(find.byIcon(Icons.person_off), findsOneWidget);
    });

    testWidgets('кнопка догрузки видна при неполном списке', (tester) async {
      mediaRepo.total = 5;
      await pumpPage(tester, makeContainer());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Load more'), findsOneWidget);
    });
  });
}
