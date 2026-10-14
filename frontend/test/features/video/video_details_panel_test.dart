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

      expect(find.text('Extracting audio…'), findsOneWidget);
      await tester.tap(find.text('Extracting audio…'));
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
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Extract audio'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('без колбэков кнопок извлечения нет', (tester) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Extract audio'), findsNothing);
      expect(find.text('Open audio track'), findsNothing);
    });

    testWidgets('ряд действий — иконки без текстов', (tester) async {
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Тексты не влезали в ширину смартфона — только иконки с тултипами.
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.add_to_queue), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download), findsOneWidget);
      expect(find.text('Favorites'), findsNothing);
      expect(find.text('My Collections'), findsNothing);
    });

    testWidgets('без избранного кнопка задизейблена серым', (tester) async {
      // favoriteToggle в loading (ids ещё летят): isFavorite == null —
      // кнопка disabled, иконка приглушена, а не «не избранное».
      final gate = Completer<void>();
      favoritesRepo.onGetFavorites = () async {
        await gate.future;
        return const Right([]);
      };
      await pumpPanel(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.favorite_border),
      );
      expect(button.onPressed, isNull);
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

    testWidgets('тултипы называют действие', (tester) async {
      var saves = 0;
      await pumpPanel(tester, onSaveToFiles: () async => saves++);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byTooltip('Favorites'), findsOneWidget);
      expect(find.byTooltip('My Collections'), findsOneWidget);
      // Кеш — «В офлайн», файлы — «Скачать»: разные действия,
      // разные тултипы.
      expect(find.byTooltip('Save offline'), findsOneWidget);
      expect(find.byTooltip('Download'), findsOneWidget);

      await tester.tap(find.byTooltip('Download'));
      await tester.pump();
      expect(saves, 1);
    });

    testWidgets('загрузка: спиннер без семантики, тап — отмена', (
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
      // Спиннер исключён из семантики — скринридер его не анонсирует.
      expect(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Cancel'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('ошибка загрузки видна иконкой и тултипом', (tester) async {
      await pumpPanel(
        tester,
        downloadState: const DownloadError('boom'),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byTooltip('Error'), findsOneWidget);
    });

    testWidgets('скачанное — белый чек, не primary', (tester) async {
      await pumpPanel(
        tester,
        downloadState: const DownloadDownloaded(),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.color, Colors.white);
      expect(find.byTooltip('Offline'), findsOneWidget);
    });
  });
}
