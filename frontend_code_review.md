# Code Review: Flux Media Server Frontend

**Project:** Flutter client (Dart SDK ≥3.2.0)  
**Stack:** Flutter + Riverpod + Auto Route + Chopper + Freezed + media_kit + fpdart  
**Files reviewed:** 50 Dart source files (excluding generated `*.freezed.dart`, `*.g.dart`, `*.chopper.dart`, `*.gr.dart`)  
**Linting:** `very_good_analysis` included, several rules disabled (`avoid_print`, `public_member_api_docs`, etc.)

---

## 1. Executive Summary

Проект следует **Clean Architecture** с разделением на `core`, `features` и `shared`. Внутри feature используется классическое трёхслойное разделение: `data → domain → presentation`. State management — **Riverpod** с `StateNotifier` (legacy-style) + `freezed` для sealed-типов. Навигация — **Auto Route**. HTTP — **Chopper**. Видео — **media_kit**.

**Общая оценка:** код аккуратный, структурированный, но содержит **критические runtime-риски**, **утечки памяти**, **неконсистентность архитектуры** между фичами и **отсутствующую логику аутентификации** (токен не попадает в interceptor). Также UI-экраны содержат side-effects внутри `build`, и кнопка Play не работает (TODO).

---

## 2. Архитектура & Clean Architecture

### ✅ Что хорошо
- Чёткое разделение на слои: `data` (datasources, repositories), `domain` (entities, usecases, repositories), `presentation` (providers, screens).
- `core/` содержит переиспользуемые абстракции: `Failure`, `UseCase`, `ApiClient`, `AppRouter`.
- `shared/models/` — централизованные data-классы для всех фич.
- Используется `fpdart` для Railway-oriented programming (`Either<Failure, T>`).

### ❌ Проблемы

#### 2.1 Нарушение чистой архитектуры: `shared/models` в data-слое
`shared/models` содержит JSON-зависимые модели (`@freezed` + `@JsonSerializable`). По чистой архитектуре domain-слой должен содержать **entities** (чистые классы, не зависящие от JSON), а data-слой — **models** (с сериализацией). Сейчас repositories напрямую возвращают `Media`/`MediaLibrary` из `shared/models`, что создаёт зависимость domain → data.

**Рекомендация:**
```
shared/
  domain/entities/    # pure classes (MediaEntity, LibraryEntity)
  data/models/        # json models (MediaModel, LibraryModel) with fromJson/toJson
  data/mappers/       # MediaModel → MediaEntity
```

#### 2.2 Неконсистентность UseCase-ов
- `GetCurrentUser` extends `UseCase` — правильно.
- `GetMediaList`, `GetMediaDetail` — **не** extend `UseCase`.
- `GetLibraries` — не extend `UseCase`, **не** возвращает `Either<Failure, T>`, а бросает `Exception`. Это нарушает единообразие обработки ошибок.

**Рекомендация:** либо убрать абстрактный `UseCase` (если он не нужен), либо применить ко всем use cases. Все use cases должны возвращать `Either<Failure, T>`.

#### 2.3 Отсутствует `SettingsRepository` interface
`SettingsRepositoryImpl` — конкретный класс, не реализует абстрактный интерфейс. Нарушает DIP (Dependency Inversion Principle).

---

## 3. State Management (Riverpod)

### ✅ Что хорошо
- Используется `StateNotifier` + `freezed` для sealed states (`AuthState`, `LibraryState`, `MediaListState`).
- Провайдеры декомпозированы: datasource → repository → usecase → notifier.
- `autoDispose` на `mediaDetailProvider` — правильно для деталей.
- `ref.onDispose` в `videoPlayerDatasourceProvider` — хорошая практика.

### ❌ Проблемы

#### 3.1 Legacy `StateNotifier` вместо `AsyncNotifier` / `Notifier`
В Riverpod 2.x `StateNotifier` — legacy API. Для async-операций предпочтительнее `AsyncNotifier`/`AsyncValue`, который автоматически управляет `loading`/`error`/`data` и обрабатывает `ref.onDispose`/`ref.invalidate`.

**Пример:** `LibraryNotifier` с `Future.microtask(() => ref.read(...).load())` в `initState` экрана — это **pull-модель** с side-effect в UI. `AsyncNotifier` использует **push-модель**: данные загружаются в `build()`.

#### 3.2 Side-effects в `build` методах экранов
**`LoginScreen`** (строки 37-44):
```dart
if (authState is AuthCodeSent) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    context.router.push(CodeRoute(...));
  });
}
```
Навигация внутри `build` — антипаттерн. При rebuild (например, при смене темы) это может сработать повторно.

**Рекомендация:**
```dart
ref.listen(authProvider, (prev, next) {
  if (next is AuthCodeSent) {
    context.router.push(CodeRoute(...));
  }
});
```
Или использовать `AutoRoute` guards + `ref.listen` в `ConsumerStatefulWidget`.

#### 3.3 `initState` + `ref.read` для загрузки данных
`LibraryScreen`, `MediaDetailScreen`, `PlayerScreen` — все вызывают `load()` в `initState`. Это переносит логику жизненного цикла из провайдера в UI.

**Рекомендация:**
```dart
// С AsyncNotifier
final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<MediaLibrary>>(() => LibraryNotifier());

class LibraryNotifier extends AsyncNotifier<List<MediaLibrary>> {
  @override
  Future<List<MediaLibrary>> build() async {
    final repo = ref.watch(libraryRepositoryProvider);
    final result = await repo.getLibraries();
    return result.getOrElse(() => throw Exception('Failed'));
  }
}
```

---

## 4. Networking (Chopper + Dio)

### ✅ Что хорошо
- `Chopper` + code generation для типобезопасных REST-вызовов.
- `CurlInterceptor` для отладки.
- `JsonConverter` для автоматической JSON-десериализации.

### ❌ Проблемы

#### 4.1 `AuthInterceptor` — mutable singleton с `// ignore: must_be_immutable`
```dart
class AuthInterceptor implements RequestInterceptor {
  String? _token; // mutable state
}
```
Это архитектурный антипаттерн: interceptor — mutable singleton, нет связи с `SettingsLocalDataSource`. Токен нигде не устанавливается после `verifyCode`.

**Рекомендация:**
```dart
class AuthInterceptor implements RequestInterceptor {
  final Ref ref;
  AuthInterceptor(this.ref);

  @override
  FutureOr<Request> onRequest(Request request) {
    final token = ref.read(settingsProvider).settings.authToken;
    if (token != null) {
      return request.copyWith(headers: {...request.headers, 'Authorization': 'Bearer $token'});
    }
    return request;
  }
}
```

#### 4.2 Токен никогда не сохраняется после логина
`VerifyCode` возвращает `token` и `user`, но:
1. Нет вызова `AuthInterceptor.setToken(token)`.
2. Нет сохранения `authToken` в `SharedPreferences`.
3. После перезапуска приложения пользователь будет разлогинен.

**Баг:** `SettingsLocalDataSource` имеет `setAuthToken`/`getAuthToken`, но `AuthNotifier.verifyCode` никогда не вызывает его.

#### 4.3 `CurlInterceptor` логирует токен в plaintext
`CurlInterceptor` печатает полный HTTP-запрос, включая `Authorization: Bearer <token>` в логи. Это **утечка credentials**.

**Рекомендация:** написать кастомный `SafeLoggingInterceptor`, который маскирует `Authorization` заголовок.

#### 4.4 Runtime cast errors в `List<dynamic>` endpoints
```dart
// api_client.dart
@Get(path: '/libraries')
Future<Response<List<dynamic>>> getLibraries();
```
```dart
// library_remote_datasource.dart
return response.body!.cast<Map<String, dynamic>>().toList();
```
Если сервер вернёт `null` или элемент, не являющийся `Map`, приложение упадёт с `TypeError`.

**Рекомендация:** использовать typed response + `JsonConverter` с custom `ErrorConverter` для обработки ошибок сериализации.

#### 4.5 Нет обработки 401 (Unauthorized)
Если токен протухает, Chopper вернёт 401, но нет:
- Автоматического редиректа на Login.
- Логарифма токена.
- Refresh-токена (если API поддерживает).

---

## 5. Аутентификация & Security

### ❌ Критические проблемы

#### 5.1 `authToken` в `SharedPreferences` (нешифрованное хранилище)
```dart
_prefs.setString(_keyAuthToken, token);
```
На Android `SharedPreferences` хранятся в plain XML. Root-доступ = полный доступ к токену.

**Рекомендация:** использовать `flutter_secure_storage` для токенов.

#### 5.2 Нет logout при 401
`AuthInterceptor` не проверяет ответы. Если `getMe()` возвращает 401, `AuthNotifier.checkAuthStatus()` сбрасывает `AuthState.initial()`, но:
- Токен остаётся в `SharedPreferences`.
- `AuthInterceptor` продолжает отправлять старый токен.
- Нет редиректа на `LoginRoute`.

#### 5.3 Нет защиты маршрутов
`MainRoute` (с tabs) доступен без проверки аутентификации. Нет `AutoRouteGuard`.

**Рекомендация:**
```dart
class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final isAuthenticated = /* check auth state */;
    if (!isAuthenticated) router.replace(const LoginRoute());
    else resolver.next();
  }
}
```

#### 5.4 Hardcoded `http://localhost:8080`
```dart
baseUrl: Uri.parse(baseUrl ?? 'http://localhost:8080/api'),
```
Это допустимо для development, но для production нужно `Flavor`-конфигурирование или `dart-define`.

---

## 6. Видеоплеер (media_kit)

### ❌ Критические баги

#### 6.1 Утечка подписок (StreamSubscription) в `PlayerNotifier`
```dart
// player_provider.dart, строки 42-60
_datasource.positionStream.listen((position) { ... });
_datasource.durationStream.listen((duration) { ... });
_datasource.completedStream.listen((completed) { ... });
```
Каждый вызов `play()` создаёт **новые** подписки, а старые **не отменяются**. При повторном воспроизведении:
- Накапливаются listeners.
- State обновляется многократно из разных подписок.
- Потенциальная утечка памяти.

**Рекомендация:**
```dart
final List<StreamSubscription> _subscriptions = [];

Future<void> play(Media media) async {
  await _cancelSubscriptions();
  _subscriptions.add(_datasource.positionStream.listen(...));
  _subscriptions.add(_datasource.durationStream.listen(...));
}

Future<void> _cancelSubscriptions() async {
  for (final sub in _subscriptions) await sub.cancel();
  _subscriptions.clear();
}
```

#### 6.2 `MediaKit.ensureInitialized()` в `initState` экрана
```dart
// player_screen.dart, строка 30
mk.MediaKit.ensureInitialized();
```
Глобальная инициализация внутри виджета — неправильно. Если экран откроется повторно, `ensureInitialized()` no-op, но это side-effect в UI.

**Рекомендация:** перенести в `main.dart` после `WidgetsFlutterBinding.ensureInitialized()`.

#### 6.3 Нет `SystemChrome` immersive mode
Видеоплеер без полноэкранного режима, скрытия системных панелей и блокировки ориентации. Пользователь видит status bar и navigation bar поверх видео.

**Рекомендация:**
```dart
SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, ...]);
```

#### 6.4 Нет `WillPopScope` / `PopScope`
При нажатии системной кнопки "Назад" экран закрывается, но плеер может продолжать работать в фоне (если `dispose` не сработал).

#### 6.5 `Slider` seek — jittery UX
```dart
Slider(
  value: position.inSeconds.toDouble().clamp(...),
  onChanged: (value) {
    ref.read(playerProvider.notifier).seek(Duration(seconds: value.toInt()));
  },
)
```
`onChanged` вызывается на каждый пиксель движения. Каждый раз происходит `seek` в плеер, что создаёт лаги.

**Рекомендация:**
```dart
Slider(
  onChangeStart: (_) => _isDragging = true,
  onChanged: (value) => setState(() => _dragPosition = value),
  onChangeEnd: (value) {
    _isDragging = false;
    ref.read(playerProvider.notifier).seek(Duration(seconds: value.toInt()));
  },
)
```

#### 6.6 `videoControllerProvider` — потенциальная утечка
```dart
final videoControllerProvider = Provider<VideoController>((ref) {
  final datasource = ref.watch(videoPlayerDatasourceProvider);
  return VideoController(datasource.player);
});
```
`VideoController` создаётся, но никогда не `dispose`. Если `videoPlayerDatasourceProvider` обновится (например, при смене baseUrl), старый `VideoController` останется висеть.

---

## 7. UI/UX & Accessibility

### ❌ Проблемы

#### 7.1 Кнопка Play не работает
```dart
// media_detail_screen.dart, строки 86-91
FilledButton.icon(
  onPressed: () {
    // TODO: implement playback
  },
  ...
)
```
**Это баг.** Пользователь не может воспроизвести медиа из деталей.

#### 7.2 `GridView` с `crossAxisCount: 2` — не адаптивен
```dart
// media_list_screen.dart, строки 52-57
crossAxisCount: 2,
childAspectRatio: 0.7,
```
На планшете/десктопе карточки будут огромными. Лучше:
```dart
LayoutBuilder(
  builder: (context, constraints) {
    final crossAxisCount = (constraints.maxWidth / 180).floor().clamp(2, 6);
    return GridView.builder(...crossAxisCount: crossAxisCount...);
  },
)
```

#### 7.3 `Switch` в LibraryScreen всегда disabled
```dart
Switch(value: library.enabled, onChanged: null)
```
Без комментария это выглядит как баг.

#### 7.4 Нет тёмной темы
```dart
theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
```
Нет `darkTheme` и `themeMode`. Для медиа-приложения тёмная тема — must-have.

#### 7.5 Нет локализации
Все строки hardcoded на английском. `MediaKit`/`Flutter` поддерживают `flutter_localizations` + `intl`.

#### 7.6 `CodeScreen` — `TextInputType.number` без `inputFormatters`
Пользователь может ввести буквы на некоторых раскладках (например, в веб-версии или с Bluetooth-клавиатурой). Нужно:
```dart
inputFormatters: [FilteringTextInputFormatter.digitsOnly],
```

#### 7.7 Нет `Hero` анимации между списком и деталями
Для медиа-приложения переход с thumbnail на деталь с `Hero` — стандарт.

#### 7.8 `MediaDetailScreen` — AppBar title generic
```dart
AppBar(title: const Text('Media Detail'))
```
Лучше: `AppBar(title: Text(media.title))`.

---

## 8. Модели & Сериализация

### ✅ Что хорошо
- `freezed` + `json_serializable` для иммутабельных моделей.
- `fromJson`/`toJson` автоматически сгенерированы.
- `DurationExtensions` — удобное форматирование.

### ❌ Проблемы

#### 8.1 `Media.thumbnailUrl` нигде не используется
```dart
// media.dart
String? thumbnailUrl,
```
`MediaCard` и `MediaDetailScreen` всегда строят URL из `baseUrl/media/{id}/thumb`. Поле `thumbnailUrl` бесполезно.

#### 8.2 `Metadata.genres`/`cast` — `List<String>?` — потенциальный runtime error
Если JSON содержит `List<dynamic>` с `null` элементами, `json_serializable` может упасть.

**Рекомендация:**
```dart
@JsonKey(fromJson: _stringListFromJson)
List<String>? genres;

static List<String>? _stringListFromJson(dynamic json) {
  if (json == null) return null;
  return (json as List).whereType<String>().toList();
}
```

#### 8.3 `String.capitalize` — не Unicode-safe
```dart
extension StringExtensions on String {
  String get capitalize {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
```
`this[0]` — первый code unit, не grapheme cluster. Emoji (🇷🇺, 👍) или флаги будут обрезаны.

**Рекомендация:** использовать `characters` package.

#### 8.4 `DurationExtensions.formatted` — не используется
`PlayerScreen` имеет собственный `_formatDuration()`, хотя `DurationExtensions` уже определён в `core/utils/extensions.dart`. Дублирование кода.

---

## 9. Баги & Runtime Issues

### 🔴 Критические
| Баг | Файл | Описание |
|-----|------|----------|
| **Токен не сохраняется** | `auth_provider.dart` | После `verifyCode` токен не пишется в `SharedPreferences` и не устанавливается в `AuthInterceptor`. |
| **Утечка подписок плеера** | `player_provider.dart` | StreamSubscription накапливаются при каждом `play()`. |
| **TODO: Play** | `media_detail_screen.dart` | Кнопка Play не делает ничего. |
| **Cast error** | `library_remote_datasource.dart` | `.cast<Map<String, dynamic>>()` может упасть в runtime. |
| **Side-effect в build** | `login_screen.dart` | `addPostFrameCallback` с навигацией внутри `build`. |

### 🟡 Средние
| Баг | Файл | Описание |
|-----|------|----------|
| **Нет обработки 401** | Все datasource | При 401 приложение показывает generic error, не разлогинивает. |
| **Нет certificate pinning** | `api_client.dart` | Production API без SSL pinning. |
| **NetworkInfo mock** | `network_info.dart` | Всегда возвращает `true`. Нет offline detection. |
| **Library Switch disabled** | `library_screen.dart` | `onChanged: null` без объяснения. |
| **PlayerScreen без immersive** | `player_screen.dart` | Системные панели видны поверх видео. |

---

## 10. Performance

### ❌ Проблемы

#### 10.1 `PlayerNotifier` — частые rebuilds
`positionStream` обновляет state каждые ~100-500ms. Это перестраивает весь `PlayerScreen` (Stack + Video + Controls). Лучше разделить на подвиджеты:
- `VideoWidget` — только `Video(controller)`.
- `ControlsOverlay` — только slider + buttons, с `select` для подписки на позицию.

```dart
final positionProvider = Provider<Duration>((ref) {
  final state = ref.watch(playerProvider);
  return state is PlayerNotifierPlaying ? state.position : Duration.zero;
});
```

#### 10.2 `GridView` без `RepaintBoundary`
`MediaCard` с `CachedNetworkImage` — тяжёлый виджет. Без `RepaintBoundary` каждый rebuild родителя перерисовывает все карточки.

#### 10.3 `baseUrlProvider` — `ref.watch(settingsProvider)`
`baseUrlProvider` вызывает `ref.watch(settingsProvider)`, что rebuilds всё, что слушает `baseUrlProvider`, при любом изменении `SettingsState` (например, logout).

---

## 11. Testing & DevEx

### ❌ Проблемы
- `flutter_test` в `dev_dependencies`, но **нет тестовых файлов** в проекте.
- Нет mock-ов для `ApiClient`, `VideoPlayerDatasource`.
- `NetworkInfoImpl` — mock, не реализован.
- `very_good_analysis` подключён, но `public_member_api_docs: false`, `avoid_print: false` — ослаблены правила.

---

## 12. Priority Roadmap

### 🔴 P0 — Критические (блокируют релиз)
1. **Исправить сохранение токена** после `verifyCode` (`SharedPreferences` + `AuthInterceptor`).
2. **Реализовать кнопку Play** в `MediaDetailScreen` (навигация на `PlayerRoute`).
3. **Исправить утечку StreamSubscription** в `PlayerNotifier` (cancel + track).
4. **Добавить `AuthGuard`** для защиты `MainRoute`.
5. **Убрать side-effect из `build`** в `LoginScreen` → использовать `ref.listen`.

### 🟡 P1 — Важные (влияют на UX/стабильность)
6. **Заменить `SharedPreferences` на `flutter_secure_storage`** для токена.
7. **Добавить обработку 401** — auto-logout + редирект на Login.
8. **Перенести `MediaKit.ensureInitialized()`** в `main.dart`.
9. **Добавить `SystemChrome` immersive** для `PlayerScreen`.
10. **Исправить `Slider` seek** — `onChangeStart`/`onChangeEnd`.
11. **Сделать `GridView` адаптивным** через `LayoutBuilder`.

### 🟢 P2 — Архитектурные улучшения
12. **Мигрировать с `StateNotifier` на `AsyncNotifier`** для всех async-провайдеров.
13. **Вынести domain entities** из `shared/models` в `domain/entities`.
14. **Консистентность UseCase** — все extend `UseCase<Either<Failure, T>, Params>`.
15. **Добавить `SettingsRepository` interface**.
16. **Реализовать `NetworkInfo`** через `connectivity_plus`.
17. **Добавить `Hero` анимации** между списком и деталями.
18. **Добавить тёмную тему**.
19. **Локализация** через `flutter_localizations`.

### 🔵 P3 — Polish
20. **Убрать `CurlInterceptor`** или замаскировать токен.
21. **Добавить `RepaintBoundary`** для `MediaCard`.
22. **Исправить `String.capitalize`** через `characters`.
23. **Удалить `Media.thumbnailUrl`** или использовать его.
24. **Добавить `inputFormatters`** для code input.
25. **Добавить `Hero` + `PageTransition`** для красивых переходов.

---

*Review completed by code analysis. Все замечания основаны на статическом анализе исходного кода без запуска приложения.*