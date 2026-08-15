import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/video/presentation/widgets/horizontal_video_row.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media _fakeMedia(int id, {int? duration}) => Media(
      id: id,
      title: 'Video $id',
      year: 2024,
      type: MediaType.video,
      fileSize: 1024,
      duration: duration,
    );

WatchProgress _progress({
  required int mediaId,
  required int position,
  required int duration,
  bool completed = false,
}) =>
    WatchProgress(
      id: mediaId,
      userId: 0,
      mediaId: mediaId,
      position: position,
      duration: duration,
      completed: completed,
    );

void main() {
  late SharedPreferences prefs;

  Widget buildRow({
    required List<Media> items,
    Map<int, WatchProgress> progress = const {},
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: HorizontalVideoRow(
              title: 'Continue Watching',
              icon: Icons.history,
              items: items,
              progressById: progress,
              onItemTapped: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('прогресс >= 90% — бейдж «готово», позиция < 90% — остаток',
      (tester) async {
    await tester.pumpWidget(
      buildRow(
        items: [_fakeMedia(1), _fakeMedia(2)],
        progress: {
          1: _progress(mediaId: 1, position: 900, duration: 1000),
          2: _progress(mediaId: 2, position: 300, duration: 1000),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 90%+ → бейдж «Готово».
    expect(find.text('Готово'), findsOneWidget);
    // 30% → бейдж с остатком (-11:40).
    expect(find.text('-11:40'), findsOneWidget);
  });

  testWidgets('порог ровно 0.9 — завершён (без плавающей погрешности)',
      (tester) async {
    await tester.pumpWidget(
      buildRow(
        items: [_fakeMedia(1)],
        progress: {1: _progress(mediaId: 1, position: 900, duration: 1000)},
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Готово'), findsOneWidget);
    expect(find.textContaining('-'), findsNothing);
  });

  testWidgets('менее 90% — бейджа «готово» нет', (tester) async {
    await tester.pumpWidget(
      buildRow(
        items: [_fakeMedia(1)],
        progress: {1: _progress(mediaId: 1, position: 899, duration: 1000)},
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Готово'), findsNothing);
    expect(find.text('-01:41'), findsOneWidget);
  });

  testWidgets('без прогресса — карточка без оверлеев', (tester) async {
    await tester.pumpWidget(
      buildRow(items: [_fakeMedia(1)]),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Готово'), findsNothing);
    expect(find.textContaining('-'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
