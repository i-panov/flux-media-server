import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';
import 'package:flux_media_server/features/media/domain/repositories/media_repository.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/edit_metadata_dialog.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:fpdart/fpdart.dart';

Media _media({String? sourceUrl}) => Media(
  id: 7,
  title: 'Video',
  type: MediaType.video,
  fileSize: 1,
  sourceUrl: sourceUrl,
);

class _FakeMediaRepository implements MediaRepository {
  MetadataEdit? lastEdit;

  @override
  Future<Either<Failure, List<Artist>>> getArtists() async => const Right([]);

  @override
  Future<Either<Failure, Media>> updateMetadata(
    int mediaId,
    MetadataEdit edit,
  ) async {
    lastEdit = edit;
    return Right(_media(sourceUrl: edit.sourceUrl));
  }

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) async =>
      Right(_media());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DialogHost extends ConsumerWidget {
  const new({required this.media, required this.repository});

  final Media media;
  final _FakeMediaRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => showEditMetadataDialog(context, ref, media),
      child: const Text('open'),
    );
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  Media media,
  _FakeMediaRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mediaRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _DialogHost(media: media, repository: repository),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('edit metadata dialog source link', () {
    testWidgets('невалидная ссылка подсвечивает поле, диалог открыт', (
      tester,
    ) async {
      final repository = _FakeMediaRepository();
      await _pumpDialog(tester, _media(), repository);

      await tester.enterText(find.byType(TextFormField).last, 'bogus');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a valid http(s) link'), findsOneWidget);
      // Диалог не закрылся, запрос не ушёл.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repository.lastEdit, isNull);
    });

    testWidgets('без изменений ключ ссылки не отправляется', (tester) async {
      final repository = _FakeMediaRepository();
      await _pumpDialog(
        tester,
        _media(sourceUrl: 'https://youtu.be/abc123'),
        repository,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.lastEdit, isNotNull);
      expect(repository.lastEdit!.sourceUrl, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('очистка поля отправляет пустую строку', (tester) async {
      final repository = _FakeMediaRepository();
      await _pumpDialog(
        tester,
        _media(sourceUrl: 'https://youtu.be/abc123'),
        repository,
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.last, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.lastEdit!.sourceUrl, '');
    });
  });
}
