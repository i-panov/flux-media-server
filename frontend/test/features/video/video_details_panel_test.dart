import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/features/offline/presentation/providers/download_state_provider.dart';
import 'package:flux_media_server/features/player/data/providers/playback_coordinator.dart';
import 'package:flux_media_server/features/video/presentation/widgets/video_details_panel.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

Media _video() => const Media(
  id: 7,
  title: 'Clip',
  type: MediaType.video,
  fileSize: 1024,
  duration: 100,
  year: 2024,
);

class _FakeMediaRepository implements MediaRepository {
  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({
    String? type,
    int? year,
    String? q,
    int? limit,
    int? offset,
  }) async => const Right((items: [], total: 0));

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

/// Координатор без плеера: панель слушает downloadState, а настоящий build
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    favoritesRepo = FakeFavoritesRepository()
      ..onGetFavorites = () async => const Right([]);
  });

  ProviderContainer makeContainer({DownloadState? downloadState}) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        baseUrlProvider.overrideWithValue('http://test/api'),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        mediaRepositoryProvider.overrideWithValue(_FakeMediaRepository()),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        offlineCacheServiceProvider.overrideWith(
          (_) => _FakeCache(prefs: prefs),
        ),
        playbackCoordinatorProvider.overrideWith(_IdleCoordinator.new),
        if (downloadState != null)
          downloadStateProvider(7).overrideWithValue(downloadState),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    Future<void> Function()? onExtractAudio,
    Future<void> Function()? onCancelExtract,
    Future<void> Function()? onOpenExtractedAudio,
    Future<void> Function()? onDownload,
    Future<void> Function()? onSaveToFiles,
    bool isExtracting = false,
    bool linkLoading = false,
    DownloadState? downloadState,
  }) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: makeContainer(downloadState: downloadState),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoDetailsPanel(
                media: _video(),
                onExtractAudio: onExtractAudio,
                onCancelExtract: onCancelExtract,
                onOpenExtractedAudio: onOpenExtractedAudio,
                onDownload: onDownload,
                onSaveToFiles: onSaveToFiles,
                isExtracting: isExtracting,
                linkLoading: linkLoading,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Активна ли строка действия: у `_ActionRow` InkWell, а не кнопка с
  /// onPressed, поэтому активность проверяется по InkWell.
  bool rowEnabled(WidgetTester tester, String label) {
    final ink = tester.widget<InkWell>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      ),
    );
    return ink.onTap != null;
  }

  group('VideoDetailsPanel audio extraction', () {
    testWidgets('кнопка извлечения зовёт колбэк', (tester) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onExtractAudio: () async => calls++,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsOneWidget);
      expect(find.text('Open audio track'), findsNothing);

      await tester.tap(find.text('Extract audio'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('готовый трек: кнопка открытия вместо извлечения', (
      tester,
    ) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onExtractAudio: () async {},
        onOpenExtractedAudio: () async => calls++,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Open audio track'), findsOneWidget);
      expect(find.text('Extract audio'), findsNothing);

      await tester.tap(find.text('Open audio track'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('во время извлечения — кнопка отмены', (tester) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onExtractAudio: () async {},
        onCancelExtract: () async => calls++,
        isExtracting: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Строка извлечения на время джоба заблокирована...
      expect(rowEnabled(tester, 'Extracting audio…'), isFalse);
      // ...и её иконка — «в работе», а НЕ крестик: крестик читался бы
      // как отмена, а отмена живёт отдельной строкой ниже.
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      // Отмена — отдельной строкой.
      expect(find.text('Cancel extraction'), findsOneWidget);

      await tester.tap(find.text('Cancel extraction'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('пока связка грузится — извлечение заблокировано', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        onExtractAudio: () async {},
        linkLoading: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsOneWidget);
      expect(rowEnabled(tester, 'Extract audio'), isFalse);
    });

    testWidgets('без колбэков кнопок извлечения нет', (tester) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsNothing);
      expect(find.text('Open audio track'), findsNothing);
    });

    testWidgets('действия — вертикальным списком с иконкой и текстом', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Раньше часть действий была текстовыми кнопками, часть — голыми
      // иконками без подписей. Теперь у каждого есть и то, и другое.
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.playlist_add), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('My Collections'), findsOneWidget);
    });

    testWidgets('список идёт сверху вниз в порядке действий', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final favoritesY = tester.getCenter(find.text('Favorites')).dy;
      final collectionsY = tester.getCenter(find.text('My Collections')).dy;
      final offlineY = tester.getCenter(find.text('Save offline')).dy;

      expect(favoritesY, lessThan(collectionsY));
      expect(collectionsY, lessThan(offlineY));
    });

    testWidgets('без избранного действие задизейблено и приглушено', (
      tester,
    ) async {
      // favoriteToggle в loading (ids ещё летят): isFavorite == null —
      // действие заблокировано, иконка приглушена, а не «не избранное».
      final gate = Completer<void>();
      favoritesRepo.onGetFavorites = () async {
        await gate.future;
        return const Right([]);
      };
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(rowEnabled(tester, 'Favorites'), isFalse);
      final icon = tester.widget<Icon>(find.byIcon(Icons.favorite_border));
      expect(icon.color, Colors.white38);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('год в подзаголовке, типа нет', (tester) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Год — единственное в подзаголовке; «video» убрано как шум.
      expect(find.text('2024'), findsOneWidget);
      expect(find.textContaining('video'), findsNothing);
    });

    testWidgets('подписи действий различимы и не роняются в тултипы', (
      tester,
    ) async {
      var saves = 0;
      await pumpPanel(tester, onSaveToFiles: () async => saves++);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('My Collections'), findsOneWidget);
      // Кеш — «В офлайн», файлы — «Скачать»: разные действия,
      // разные подписи. Раньше различались только тултипы.
      expect(find.text('Save offline'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(saves, 1);
    });

    testWidgets('загрузка: спиннер у действия, тап — отмена', (
      tester,
    ) async {
      var calls = 0;
      await pumpPanel(
        tester,
        onDownload: () async => calls++,
        downloadState: const DownloadDownloading(progress: 0.5),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Во время загрузки действие называет отмену, а не «в офлайн».
      expect(find.text('Cancel'), findsOneWidget);
      // И иконка соответствует действию: тап отменяет загрузку —
      // значит, и значок должен быть отменой, а не «облаком».
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('ошибка загрузки видна иконкой и подписью', (tester) async {
      await pumpPanel(
        tester,
        downloadState: const DownloadError('boom'),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('скачанное — белый чек, не primary', (tester) async {
      await pumpPanel(
        tester,
        onDownload: () async {},
        downloadState: const DownloadDownloaded(),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.color, Colors.white);
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('строки действий объявлены кнопками для скринридера', (
      tester,
    ) async {
      // Без Semantics(button: true) строка читается как обычный текст,
      // и действие «В офлайн» звучит строкой, а не кнопкой.
      //
      // Проверяем на активной строке: у «Favorites» состояние избранного
      // ещё грузится (isFavorite == null), и действие заблокировано —
      // у заблокированной строки нет флага isEnabled.
      await pumpPanel(
        tester,
        onDownload: () async {},
        downloadState: const DownloadDownloaded(),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.getSemantics(find.text('Offline')),
        matchesSemantics(
          label: 'Offline',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
    });

    testWidgets('кнопки play в панели нет: она живёт поверх превью', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Запуск — круглая кнопка на самом превью в VideoPlayerPanel.
      // В панели действий отдельной строки «Play» быть не должно.
      expect(find.text('Play'), findsNothing);
    });
  });
}
