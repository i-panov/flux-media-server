import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/settings_local_datasource.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository_impl.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/offline/data/offline_cache_service.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/user.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _keyPrefix = kDebugMode ? 'debug_' : 'release_';

Media _media(int id) => Media(
      id: id,
      title: 'Media $id',
      year: 2024,
      type: MediaType.video,
      fileSize: 1024,
    );

Lyrics _lyrics(int mediaId) => Lyrics(
      id: 1,
      mediaId: mediaId,
      source: 'test',
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
      lyricsText: 'Text',
    );


/// Фейковый auth-нотифаер: «залогинен» как пользователь 7, либо
/// в начальном состоянии (после рестарта), если user == null.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({User? user}) : _user = user;

  final User? _user;

  @override
  AuthState build() {
    // НЕ вызываем super.build(): он поднимает цепочку API-клиентов,
    // которая в этом тесте ломается (фейковый HTTP без connectionTimeout).
    return _user != null
        ? AuthState.authenticated(user: _user)
        : const AuthState.initial();
  }
}

final _refProvider = Provider<Ref>((ref) => ref);

/// Фейковый стек HTTP поверх [HttpOverrides]: перехватывает создаваемые
/// внутри [OfflineCacheService] клиенты http.Client() без сети.
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(method, url, _handler);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._method, this._url, this._handler);

  final String _method;
  final Uri _url;
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;
  final List<int> _bodyBytes = [];

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bodyBytes.addAll(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final request = http.Request(_method, _url)
      ..bodyBytes = _bodyBytes;
    headers.forEach((name, values) {
      request.headers[name] = values.join(',');
    });
    final streamed = await _handler(request);
    return _FakeHttpClientResponse(streamed);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse implements HttpClientResponse {
  _FakeHttpClientResponse(this._streamed);

  final http.StreamedResponse _streamed;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  int get statusCode => _streamed.statusCode;

  @override
  int get contentLength => _streamed.contentLength ?? -1;

  @override
  bool get isRedirect => _streamed.isRedirect;

  @override
  bool get persistentConnection => _streamed.persistentConnection;

  @override
  String get reasonPhrase => _streamed.reasonPhrase ?? '';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _streamed.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Stream<List<int>> handleError(
    Function onError, {
    bool Function(dynamic error)? test,
  }) {
    return _streamed.stream.handleError(onError, test: test);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  late ProviderContainer container;
  late SharedPreferences prefs;
  late OfflineCacheService service;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flux_cache_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel,
            (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(
          () => _FakeAuthNotifier(
            user: const User(id: 7, email: 'u@example.com'),
          ),
        ),
      ],
    );
    final ref = container.read(_refProvider);
    service = OfflineCacheService(ref, 'http://localhost:8080/api');
  });

  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await tempDir.delete(recursive: true);
  });

  group('per-user prefix', () {
    test('saveMetadata stores metadata under the user-scoped key', () async {
      await service.saveMetadata(_media(5));

      final raw = prefs.getString('${_keyPrefix}user_7_flux_meta_5');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['id'], 5);
      expect(decoded['title'], 'Media 5');
    });

    test('getCachedIds lists only files of the current user', () async {
      File('${tempDir.path}/${_keyPrefix}user_7_flux_media_3')
          .writeAsStringSync('a');
      File('${tempDir.path}/${_keyPrefix}user_7_flux_media_4.part')
          .writeAsStringSync('b');
      File('${tempDir.path}/${_keyPrefix}user_9_flux_media_5')
          .writeAsStringSync('c');
      // Легаси-файл без user-неймспейса мигрирует к текущему пользователю.
      File('${tempDir.path}/${_keyPrefix}flux_media_1').writeAsStringSync('d');

      final ids = await service.getCachedIds();

      // Файл другого пользователя (5) и .part (4) не попадают в список.
      expect(ids, [3, 1]);
    });

    test('getCachedMedia reads metadata from user-scoped keys', () async {
      File('${tempDir.path}/${_keyPrefix}user_7_flux_media_6')
          .writeAsStringSync('a');
      await service.saveMetadata(_media(6));
      await prefs.setString(
        '${_keyPrefix}user_7_flux_meta_6',
        jsonEncode(_media(6).toJson()),
      );

      final mediaList = await service.getCachedMedia();

      expect(mediaList.map((m) => m.id), [6]);
      expect(mediaList.first.title, 'Media 6');
    });
  });

  group('lyrics cache', () {
    test('saveLyrics and getCachedLyrics roundtrip', () async {
      await service.saveLyrics(5, _lyrics(5));

      final cached = await service.getCachedLyrics(5);

      expect(cached, isNotNull);
      expect(cached!.lyricsText, 'Text');
      expect(prefs.containsKey('${_keyPrefix}user_7_flux_lyrics_5'), isTrue);
    });

    test('getCachedLyrics returns null when not cached', () async {
      expect(await service.getCachedLyrics(42), isNull);
    });
  });

  group('clearUserCache', () {
    test('removes files, metadata and lyrics of the current user', () async {
      final file =
          File('${tempDir.path}/${_keyPrefix}user_7_flux_media_5')
            ..writeAsStringSync('x');
      await service.saveMetadata(_media(5));
      await service.saveLyrics(5, _lyrics(5));

      await service.clearUserCache();

      expect(file.existsSync(), isFalse);
      expect(
        prefs.containsKey('${_keyPrefix}user_7_flux_meta_5'),
        isFalse,
      );
      expect(
        prefs.containsKey('${_keyPrefix}user_7_flux_lyrics_5'),
        isFalse,
      );
      expect(
        prefs.containsKey('${_keyPrefix}flux_current_user_id'),
        isFalse,
      );
    });

    test('removes files after restart without prior initialization',
        () async {
      // Рестарт: auth ещё не подтверждён, id пользователя только в prefs,
      // _userId в сервисе == null (ни одна операция не инициализировала его).
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(_FakeAuthNotifier.new),
        ],
      );
      addTearDown(container2.dispose);
      final svc = OfflineCacheService(
        container2.read(_refProvider),
        'http://localhost:8080/api',
      );
      final file = File('${tempDir.path}/${_keyPrefix}user_7_flux_media_5')
        ..writeAsStringSync('x');
      await prefs.setInt('${_keyPrefix}flux_current_user_id', 7);

      await svc.clearUserCache();

      expect(file.existsSync(), isFalse);
      expect(
        prefs.containsKey('${_keyPrefix}flux_current_user_id'),
        isFalse,
      );
    });

    test('leaves files and metadata of other users intact', () async {
      final otherFile =
          File('${tempDir.path}/${_keyPrefix}user_9_flux_media_5')
            ..writeAsStringSync('x');
      await service.saveMetadata(_media(5));
      await prefs.setString(
        '${_keyPrefix}user_9_flux_meta_5',
        jsonEncode(_media(5).toJson()),
      );

      await service.clearUserCache();

      expect(otherFile.existsSync(), isTrue);
      expect(
        prefs.containsKey('${_keyPrefix}user_9_flux_meta_5'),
        isTrue,
      );
      expect(
        prefs.containsKey('${_keyPrefix}user_7_flux_meta_5'),
        isFalse,
      );
    });
  });

  group('migration of legacy files', () {
    test('moves files and metadata into the user-scoped namespace',
        () async {
      final legacy = File('${tempDir.path}/${_keyPrefix}flux_media_3')
        ..writeAsStringSync('legacy');
      await prefs.setString(
        '${_keyPrefix}flux_meta_3',
        jsonEncode(_media(3).toJson()),
      );
      await prefs.setString(
        '${_keyPrefix}flux_lyrics_3',
        jsonEncode(_lyrics(3).toJson()),
      );

      final path = await service.getLocalPath(3);

      expect(path, '${tempDir.path}/${_keyPrefix}user_7_flux_media_3');
      expect(legacy.existsSync(), isFalse);
      expect(
        prefs.getString('${_keyPrefix}user_7_flux_meta_3'),
        isNotNull,
      );
      expect(
        prefs.getString('${_keyPrefix}user_7_flux_lyrics_3'),
        isNotNull,
      );
      expect(prefs.getBool('${_keyPrefix}flux_migrated_user_7'), isTrue);
      expect(prefs.containsKey('${_keyPrefix}flux_meta_3'), isFalse);
      expect(prefs.containsKey('${_keyPrefix}flux_lyrics_3'), isFalse);
    });

    test('runs only once', () async {
      File('${tempDir.path}/${_keyPrefix}flux_media_3')
          .writeAsStringSync('legacy');

      await service.getLocalPath(3);
      // После первого прогона флаг взведён, легаси больше нет.
      File('${tempDir.path}/${_keyPrefix}flux_media_4')
          .writeAsStringSync('later');
      await service.getLocalPath(4);

      expect(
        File('${tempDir.path}/${_keyPrefix}flux_media_4').existsSync(),
        isTrue,
      );
    });
  });

  group('download', () {
    test('saves file and metadata on success', () async {
      Future<http.StreamedResponse> handler(http.BaseRequest request) async {
        expect(
          request.url.toString(),
          'http://localhost:8080/api/media/6/stream',
        );
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
          ]),
          200,
          contentLength: 3,
        );
      }

      final path = await HttpOverrides.runZoned(
        () => service.download(_media(6)),
        createHttpClient: (_) => _FakeHttpClient(handler),
      );

      expect(path, '${tempDir.path}/${_keyPrefix}user_7_flux_media_6');
      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_6').existsSync(),
        isTrue,
      );
      expect(
        prefs.containsKey('${_keyPrefix}user_7_flux_meta_6'),
        isTrue,
      );
    });

    test('cancelDownload aborts the active download and cleans up .part',
        () async {
      final requestStarted = Completer<void>();
      final proceed = Completer<void>();
      Future<http.StreamedResponse> handler(http.BaseRequest request) async {
        // Сигналим, что запрос уже ушёл (флаг отмены зафиксирован),
        // и ждём команду отдать тело ответа.
        requestStarted.complete();
        await proceed.future;
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          200,
          contentLength: 4,
        );
      }

      final future = HttpOverrides.runZoned(
        () => service.download(_media(5)),
        createHttpClient: (_) => _FakeHttpClient(handler),
      );

      await requestStarted.future;
      service.cancelDownload(5);
      proceed.complete();

      await expectLater(future, throwsA(isA<DownloadCancelledException>()));
      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_5.part')
            .existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_5').existsSync(),
        isFalse,
      );
    });
  });

  group('orphan .part cleanup', () {
    test('removes .part without final file on first operation', () async {
      File('${tempDir.path}/${_keyPrefix}user_7_flux_media_10.part')
          .writeAsStringSync('x');
      // .part с уже сохранённым финальным файлом — не сирота.
      File('${tempDir.path}/${_keyPrefix}user_7_flux_media_11.part')
          .writeAsStringSync('x');
      File('${tempDir.path}/${_keyPrefix}user_7_flux_media_11')
          .writeAsStringSync('full');
      // Файлы чужого пользователя не трогаем.
      File('${tempDir.path}/${_keyPrefix}user_9_flux_media_12.part')
          .writeAsStringSync('x');

      await service.getLocalPath(1);

      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_10.part')
            .existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_11.part')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${tempDir.path}/${_keyPrefix}user_9_flux_media_12.part')
            .existsSync(),
        isTrue,
      );
    });
  });

  group('download integrity', () {
    test('rejects truncated download and cleans up .part', () async {
      Future<http.StreamedResponse> handler(http.BaseRequest request) async {
        return http.StreamedResponse(
          // Объявлено 5 байт, пришло 3 — усечённый ответ.
          Stream.fromIterable([
            [1, 2, 3],
          ]),
          200,
          contentLength: 5,
        );
      }

      await expectLater(
        HttpOverrides.runZoned(
          () => service.download(_media(6)),
          createHttpClient: (_) => _FakeHttpClient(handler),
        ),
        throwsA(
          predicate((e) => e.toString().contains('Download incomplete')),
        ),
      );

      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_6').existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_6.part')
            .existsSync(),
        isFalse,
      );
    });
  });

  group('download 401 retry', () {
    test('retries with a fresh token after 401', () async {
      var refreshCalls = 0;
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(
            () => _FakeAuthNotifier(
              user: const User(id: 7, email: 'u@example.com'),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepositoryImpl(
              SettingsLocalDataSource(prefs, const FlutterSecureStorage()),
            ),
          ),
          authTokenRefresherProvider.overrideWith(
            (ref) => AuthTokenRefresher(
              performRefresh: (refreshToken) async {
                refreshCalls++;
                expect(refreshToken, 'refresh-1');
                await ref
                    .read(settingsProvider.notifier)
                    .setTokens('new-token', 'new-refresh');
                return (token: 'new-token', refreshToken: 'new-refresh');
              },
              onRefreshFailure: () async {},
            ),
          ),
        ],
      );
      addTearDown(container2.dispose);
      await container2.read(settingsProvider.notifier).init();
      await container2
          .read(settingsProvider.notifier)
          .setTokens('old-token', 'refresh-1');
      final svc = OfflineCacheService(
        container2.read(_refProvider),
        'http://localhost:8080/api',
      );

      Future<http.StreamedResponse> handler(http.BaseRequest request) async {
        if (request.headers['Authorization'] == 'Bearer old-token') {
          return http.StreamedResponse(
            const Stream.empty(),
            401,
            contentLength: 0,
          );
        }
        expect(request.headers['Authorization'], 'Bearer new-token');
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
          ]),
          200,
          contentLength: 3,
        );
      }

      final path = await HttpOverrides.runZoned(
        () => svc.download(_media(6)),
        createHttpClient: (_) => _FakeHttpClient(handler),
      );

      expect(path, '${tempDir.path}/${_keyPrefix}user_7_flux_media_6');
      expect(refreshCalls, 1);
    });

    test('parallel 401s share a single refresh instead of failing', () async {
      var refreshCalls = 0;
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(
            () => _FakeAuthNotifier(
              user: const User(id: 7, email: 'u@example.com'),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepositoryImpl(
              SettingsLocalDataSource(prefs, const FlutterSecureStorage()),
            ),
          ),
          authTokenRefresherProvider.overrideWith(
            (ref) => AuthTokenRefresher(
              performRefresh: (refreshToken) async {
                refreshCalls++;
                await ref
                    .read(settingsProvider.notifier)
                    .setTokens('new-token', 'new-refresh');
                return (token: 'new-token', refreshToken: 'new-refresh');
              },
              onRefreshFailure: () async {},
            ),
          ),
        ],
      );
      addTearDown(container2.dispose);
      await container2.read(settingsProvider.notifier).init();
      await container2
          .read(settingsProvider.notifier)
          .setTokens('old-token', 'refresh-1');
      final svc = OfflineCacheService(
        container2.read(_refProvider),
        'http://localhost:8080/api',
      );

      Future<http.StreamedResponse> handler(http.BaseRequest request) async {
        if (request.headers['Authorization'] == 'Bearer old-token') {
          return http.StreamedResponse(
            const Stream.empty(),
            401,
            contentLength: 0,
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
          ]),
          200,
          contentLength: 3,
        );
      }

      await Future.wait([
        HttpOverrides.runZoned(
          () => svc.download(_media(6)),
          createHttpClient: (_) => _FakeHttpClient(handler),
        ),
        HttpOverrides.runZoned(
          () => svc.download(_media(7)),
          createHttpClient: (_) => _FakeHttpClient(handler),
        ),
      ]);

      // Второй 401-поток ждал результат общего refresh, а не фейлил.
      expect(refreshCalls, 1);
    });
  });

  group('enforceCacheLimit', () {
    test('removes oldest downloads when the cache exceeds the limit',
        () async {
      final small =
          File('${tempDir.path}/${_keyPrefix}user_7_flux_media_1')
            ..writeAsStringSync('x' * 100);
      // Гарантируем разный mtime (секундная точность на части ФС):
      // вытеснение идёт от самого старого файла.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      // Разрежённый файл: 6 ГБ «на бумаге», но почти не занимает диск.
      final big = File('${tempDir.path}/${_keyPrefix}user_7_flux_media_2');
      big.openSync(mode: FileMode.write)
        ..truncateSync(6 * 1024 * 1024 * 1024)
        ..closeSync();

      // Лимит проверяется после успешной загрузки (remove() его не
      // вызывает): новая загрузка переполняет кеш и вытесняет старые.
      Future<http.StreamedResponse> handler(http.BaseRequest request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
          ]),
          200,
          contentLength: 3,
        );
      }

      await HttpOverrides.runZoned(
        () => service.download(_media(3)),
        createHttpClient: (_) => _FakeHttpClient(handler),
      );

      expect(small.existsSync(), isFalse);
      expect(big.existsSync(), isFalse);
      expect(
        File('${tempDir.path}/${_keyPrefix}user_7_flux_media_3')
            .existsSync(),
        isTrue,
      );
    });
  });
}
