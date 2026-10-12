import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/player/data/playback_entry_factory.dart';
import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media.dart';

Media _media(int id) => Media(
  id: id,
  title: 'Track $id',
  type: MediaType.audio,
  fileSize: 1,
  duration: 180,
  coverUrl: 'cover',
  artists: const [Artist(id: 1, name: 'A One'), Artist(id: 2, name: 'A Two')],
);

PlaybackEntryFactory _factory({
  String baseUrl = 'https://host/api',
  String? token = 'tok',
  Map<int, String> local = const {},
  bool failCache = false,
}) => PlaybackEntryFactory(
  baseUrl: baseUrl,
  tokenReader: () => token,
  localPathFor: (id) async {
    if (failCache) throw Exception('cache broken');
    return local[id];
  },
);

void main() {
  group('PlaybackEntryFactory.buildEntry', () {
    test('скачанный трек: локальный путь, без заголовков и обложки', () async {
      final entry = await _factory(
        local: {7: '/data/track7.mp3'},
      ).buildEntry(_media(7), 'tok');

      expect(entry.url, '/data/track7.mp3');
      expect(entry.httpHeaders, isNull);
      expect(entry.artUri, isNull);
      expect(entry.title, 'Track 7');
      expect(entry.artist, 'A One, A Two');
      expect(entry.duration, const Duration(seconds: 180));
    });

    test('сетевой трек: stream-URL, Bearer и обложка', () async {
      final entry = await _factory().buildEntry(_media(7), 'tok');

      expect(entry.url, 'https://host/api/media/7/stream');
      expect(entry.httpHeaders, {'Authorization': 'Bearer tok'});
      expect(entry.artUri, contains('/media/7/cover'));
    });

    test('без токена заголовков нет, URL потоковый', () async {
      final entry = await _factory(token: null).buildEntry(_media(7), null);

      expect(entry.url, 'https://host/api/media/7/stream');
      expect(entry.httpHeaders, isNull);
    });

    test('упавший кеш — fallback на поток, а не проброс ошибки', () async {
      final entry = await _factory(failCache: true).buildEntry(_media(7), 't');

      expect(entry.url, 'https://host/api/media/7/stream');
    });

    test('токен читается лениво на каждую сборку', () async {
      var current = 'old';
      final factory = PlaybackEntryFactory(
        baseUrl: 'https://host/api',
        tokenReader: () => current,
        localPathFor: (_) async => null,
      );

      final first = await factory.buildEntry(_media(7), current);
      current = 'new';
      final second = await factory.buildEntry(_media(7), current);

      expect(first.httpHeaders, {'Authorization': 'Bearer old'});
      expect(second.httpHeaders, {'Authorization': 'Bearer new'});
    });
  });

  group('PlaybackEntryFactory.coverUrlFor', () {
    test('локальный трек — null', () {
      final factory = _factory();
      expect(factory.coverUrlFor(_media(7), isLocal: true), isNull);
    });

    test('приоритет cover над thumb', () {
      final factory = _factory();
      expect(
        factory.coverUrlFor(_media(7), isLocal: false),
        contains('/media/7/cover'),
      );
    });

    test('без картинок — null', () {
      final factory = _factory();
      const bare = Media(
        id: 1,
        title: 'T',
        type: MediaType.video,
        fileSize: 1,
      );
      expect(factory.coverUrlFor(bare, isLocal: false), isNull);
    });
  });
}
