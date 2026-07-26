# Phase 3: Navigation + Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 3-tab navigation (Media/Libraries/Settings) with 2-tab (Video/Audio) + Settings as a route, and add EN/RU localization with flutter_localizations.

**Architecture:** Add `flutter_localizations` + `intl` dependencies. Create ARB files for EN/RU. Update `AppSettings` with locale field. Update `SettingsLocalDataSource` and `SettingsRepository` for locale persistence. Redesign `MainScreen` with 2 tabs + AppBar actions (settings gear, upload). Create placeholder `VideoScreen` and `AudioScreen` that reuse existing media list with type filter. Run build_runner + gen-l10n.

**Tech Stack:** Flutter, flutter_localizations, intl, auto_route, flutter_riverpod

---

## Task 1: Add Localization Dependencies + Config

**Files:**
- Modify: `frontend/pubspec.yaml`
- Create: `frontend/l10n.yaml`

- [ ] **Step 1: Add dependencies**

In `frontend/pubspec.yaml`, add to `dependencies`:

```yaml
  flutter_localizations:
    sdk: flutter
  intl: ^0.18.1
```

And add to `flutter:` section:

```yaml
  generate: true
```

- [ ] **Step 2: Create l10n config**

Create `frontend/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

- [ ] **Step 3: Run pub get**

Run: `cd frontend && flutter pub get`

---

## Task 2: Create ARB Files

**Files:**
- Create: `frontend/lib/l10n/app_en.arb`
- Create: `frontend/lib/l10n/app_ru.arb`

- [ ] **Step 1: Create English ARB**

Create `frontend/lib/l10n/app_en.arb`:

```json
{
  "@@locale": "en",
  "appTitle": "Flux Media Server",
  "@appTitle": {},
  "videoTab": "Video",
  "@videoTab": {},
  "audioTab": "Audio",
  "@audioTab": {},
  "settings": "Settings",
  "@settings": {},
  "upload": "Upload",
  "@upload": {},
  "search": "Search",
  "@search": {},
  "searchMedia": "Search media...",
  "@searchMedia": {},
  "noMediaFound": "No media found",
  "@noMediaFound": {},
  "noResultsFound": "No results found",
  "@noResultsFound": {},
  "retry": "Retry",
  "@retry": {},
  "server": "Server",
  "@server": {},
  "serverUrl": "Server URL",
  "@serverUrl": {},
  "save": "Save",
  "@save": {},
  "serverUrlSaved": "Server URL saved",
  "@serverUrlSaved": {},
  "account": "Account",
  "@account": {},
  "logout": "Logout",
  "@logout": {},
  "loggedOut": "Logged out",
  "@loggedOut": {},
  "language": "Language",
  "@language": {},
  "downloads": "Downloads",
  "@downloads": {},
  "clearCache": "Clear cache",
  "@clearCache": {},
  "about": "About",
  "@about": {},
  "version": "Version",
  "@version": {},
  "play": "Play",
  "@play": {},
  "duration": "Duration",
  "@duration": {},
  "mediaDetail": "Media Detail",
  "@mediaDetail": {},
  "continueWatching": "Continue Watching",
  "@continueWatching": {},
  "recentlyAdded": "Recently Added",
  "@recentlyAdded": {},
  "favorites": "Favorites",
  "@favorites": {},
  "myCollections": "My Collections",
  "@myCollections": {},
  "allMovies": "All Movies",
  "@allMovies": {},
  "likedTracks": "Liked Tracks",
  "@likedTracks": {},
  "artists": "Artists",
  "@artists": {},
  "libraries": "Libraries",
  "@libraries": {},
  "noLibrariesYet": "No libraries yet",
  "@noLibrariesYet": {},
  "createLibrary": "Create Library",
  "@createLibrary": {},
  "newLibrary": "New Library",
  "@newLibrary": {},
  "name": "Name",
  "@name": {},
  "type": "Type",
  "@type": {},
  "cancel": "Cancel",
  "@cancel": {},
  "create": "Create",
  "@create": {},
  "delete": "Delete",
  "@delete": {},
  "deleteLibrary": "Delete Library",
  "@deleteLibrary": {},
  "scanning": "Scanning...",
  "@scanning": {},
  "scanLibrary": "Scan library",
  "@scanLibrary": {},
  "deleteLibraryConfirm": "Delete \"{name}\"? Files on disk will not be removed.",
  "@deleteLibraryConfirm": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "scanCompleted": "Scan completed",
  "@scanCompleted": {},
  "playbackCompleted": "Playback completed",
  "@playbackCompleted": {},
  "replay": "Replay",
  "@replay": {}
}
```

- [ ] **Step 2: Create Russian ARB**

Create `frontend/lib/l10n/app_ru.arb`:

```json
{
  "@@locale": "ru",
  "appTitle": "Flux Media Server",
  "videoTab": "Видео",
  "audioTab": "Аудио",
  "settings": "Настройки",
  "upload": "Загрузка",
  "search": "Поиск",
  "searchMedia": "Поиск медиа...",
  "noMediaFound": "Медиа не найдено",
  "noResultsFound": "Ничего не найдено",
  "retry": "Повторить",
  "server": "Сервер",
  "serverUrl": "URL сервера",
  "save": "Сохранить",
  "serverUrlSaved": "URL сервера сохранён",
  "account": "Аккаунт",
  "logout": "Выйти",
  "loggedOut": "Вы вышли из системы",
  "language": "Язык",
  "downloads": "Загрузки",
  "clearCache": "Очистить кэш",
  "about": "О приложении",
  "version": "Версия",
  "play": "Воспроизвести",
  "duration": "Длительность",
  "mediaDetail": "Детали медиа",
  "continueWatching": "Продолжить просмотр",
  "recentlyAdded": "Недавно добавлено",
  "favorites": "Избранное",
  "myCollections": "Мои коллекции",
  "allMovies": "Все фильмы",
  "likedTracks": "Любимые треки",
  "artists": "Артисты",
  "libraries": "Библиотеки",
  "noLibrariesYet": "Библиотек пока нет",
  "createLibrary": "Создать библиотеку",
  "newLibrary": "Новая библиотека",
  "name": "Название",
  "type": "Тип",
  "cancel": "Отмена",
  "create": "Создать",
  "delete": "Удалить",
  "deleteLibrary": "Удалить библиотеку",
  "scanning": "Сканирование...",
  "scanLibrary": "Сканировать библиотеку",
  "deleteLibraryConfirm": "Удалить \"{name}\"? Файлы на диске не будут удалены.",
  "@deleteLibraryConfirm": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "scanCompleted": "Сканирование завершено",
  "playbackCompleted": "Воспроизведение завершено",
  "replay": "Повторить"
}
```

---

## Task 3: Update AppSettings + Settings Layer for Locale

**Files:**
- Modify: `frontend/lib/features/settings/domain/entities/app_settings.dart`
- Modify: `frontend/lib/features/settings/data/datasources/settings_local_datasource.dart`
- Modify: `frontend/lib/features/settings/domain/repositories/settings_repository.dart`
- Modify: `frontend/lib/features/settings/data/repositories/settings_repository_impl.dart`
- Modify: `frontend/lib/features/settings/presentation/providers/settings_provider.dart`

- [ ] **Step 1: Add locale to AppSettings**

In `app_settings.dart`, add `locale` field:

```dart
@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    String? serverUrl,
    String? authToken,
    @Default('en') String locale,
  }) = _AppSettings;
}
```

- [ ] **Step 2: Add locale to SettingsLocalDataSource**

In `settings_local_datasource.dart`, add:

```dart
static const _keyLocale = 'locale';

String getLocale() => _prefs.getString(_keyLocale) ?? 'en';
Future<void> setLocale(String locale) => _prefs.setString(_keyLocale, locale);
```

- [ ] **Step 3: Add locale to SettingsRepository interface**

In `settings_repository.dart`, add:

```dart
String getLocale();
Future<void> setLocale(String locale);
```

- [ ] **Step 4: Add locale to SettingsRepositoryImpl**

In `settings_repository_impl.dart`, update `getSettings()` and add `setLocale`:

```dart
@override
Future<AppSettings> getSettings() async {
  final token = await _localDataSource.getAuthToken();
  return AppSettings(
    serverUrl: _localDataSource.getServerUrl(),
    authToken: token,
    locale: _localDataSource.getLocale(),
  );
}

@override
String getLocale() => _localDataSource.getLocale();

@override
Future<void> setLocale(String locale) => _localDataSource.setLocale(locale);
```

- [ ] **Step 5: Add locale to SettingsNotifier**

In `settings_provider.dart`, add:

```dart
Future<void> setLocale(String locale) async {
  await _repository.setLocale(locale);
  final settings = await _repository.getSettings();
  state = SettingsState(settings: settings);
}
```

Also update `init()` to include locale (already handled by `getSettings()` returning locale).

- [ ] **Step 6: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

---

## Task 4: Create Video + Audio Placeholder Screens

**Files:**
- Create: `frontend/lib/features/video/presentation/screens/video_screen.dart`
- Create: `frontend/lib/features/audio/presentation/screens/audio_screen.dart`

- [ ] **Step 1: Create VideoScreen**

Create `frontend/lib/features/video/presentation/screens/video_screen.dart`:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

@RoutePage()
class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({super.key});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.videoTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.upload,
            onPressed: () => context.router.push(const UploadRoute()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () => context.router.push(const SettingsRoute()),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (result) {
          if (result.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l.noMediaFound, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
                ],
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = (constraints.maxWidth / 180).floor().clamp(2, 6);
              return GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: result.items.length,
                itemBuilder: (context, index) {
                  final media = result.items[index];
                  return MediaCard(
                    media: media,
                    onTap: () => context.router.push(MediaDetailRoute(mediaId: media.id)),
                  );
                },
              );
            },
          );
        },
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(mediaListProvider),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create AudioScreen**

Create `frontend/lib/features/audio/presentation/screens/audio_screen.dart`:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/features/media/domain/usecases/get_media_list.dart';
import 'package:flux_media_server/features/media/presentation/widgets/media_card.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

@RoutePage()
class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(mediaListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.audioTab),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.upload,
            onPressed: () => context.router.push(const UploadRoute()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () => context.router.push(const SettingsRoute()),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (result) {
          if (result.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_music_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l.noMediaFound, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: result.items.length,
            itemBuilder: (context, index) {
              final media = result.items[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.music_note, size: 40),
                  title: Text(media.title),
                  subtitle: Text(media.artist ?? ''),
                  onTap: () => context.router.push(MediaDetailRoute(mediaId: media.id)),
                ),
              );
            },
          );
        },
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(mediaListProvider),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## Task 5: Update Router + MainScreen

**Files:**
- Modify: `frontend/lib/core/router/app_router.dart`

- [ ] **Step 1: Update routes and MainScreen**

Replace the entire `app_router.dart` with:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:flux_media_server/features/auth/presentation/screens/code_screen.dart';
import 'package:flux_media_server/features/auth/presentation/screens/login_screen.dart';
import 'package:flux_media_server/features/audio/presentation/screens/audio_screen.dart';
import 'package:flux_media_server/features/video/presentation/screens/video_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/media_detail_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/upload_screen.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_screen.dart';
import 'package:flux_media_server/features/settings/presentation/screens/server_setup_screen.dart';
import 'package:flux_media_server/features/settings/presentation/screens/settings_screen.dart';
import 'package:flux_media_server/shared/models/media.dart';

part 'app_router.gr.dart';

@AutoRouterConfig()
class AppRouter extends _$AppRouter {
  AppRouter({required this.authGuard});

  final AutoRouteGuard authGuard;

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: ServerSetupRoute.page, initial: true),
        AutoRoute(page: LoginRoute.page),
        AutoRoute(page: CodeRoute.page),
        AutoRoute(
          page: MainRoute.page,
          guards: [authGuard],
          children: [
            AutoRoute(page: VideoRoute.page, initial: true),
            AutoRoute(page: AudioRoute.page),
          ],
        ),
        AutoRoute(page: MediaDetailRoute.page),
        AutoRoute(page: PlayerRoute.page),
        AutoRoute(page: UploadRoute.page),
        AutoRoute(page: SettingsRoute.page),
      ];
}

@RoutePage()
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoTabsScaffold(
      routes: const [
        VideoRoute(),
        AudioRoute(),
      ],
      bottomNavigationBuilder: (context, tabsRouter) {
        return NavigationBar(
          selectedIndex: tabsRouter.activeIndex,
          onDestinationSelected: tabsRouter.setActiveIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie),
              label: 'Video',
            ),
            NavigationDestination(
              icon: Icon(Icons.music_note_outlined),
              selectedIcon: Icon(Icons.music_note),
              label: 'Audio',
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

---

## Task 6: Update main.dart with Localization

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Add localization delegates and locale support**

In `main.dart`, update `FluxApp` to be a `ConsumerWidget` that reads locale from settings:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'core/router/app_router.dart';
import 'core/router/auth_guard.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final serverUrl = prefs.getString('server_url');

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  if (serverUrl != null) {
    await container.read(settingsProvider.notifier).init();
    final settings = container.read(settingsProvider).settings;
    if (settings.authToken != null) {
      await container.read(authProvider.notifier).checkAuthStatus();
    }
  }

  final router = AppRouter(authGuard: AuthGuard(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: FluxApp(router: router, hasServerUrl: serverUrl != null),
    ),
  );
}

class FluxApp extends ConsumerWidget {
  const FluxApp({required this.router, required this.hasServerUrl, super.key});

  final AppRouter router;
  final bool hasServerUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).settings;

    return MaterialApp.router(
      title: 'Flux Media Server',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      locale: Locale(settings.locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router.config(),
    );
  }
}
```

Note: Remove the old `_FluxAppState` class entirely. The auto-login logic from `initState` needs to be handled differently — move it to a post-frame callback in the `FluxApp.build` or keep it as a `StatefulWidget`. Actually, let's keep FluxApp as ConsumerStatefulWidget to preserve the auth listening logic:

```dart
class FluxApp extends ConsumerStatefulWidget {
  const FluxApp({required this.router, required this.hasServerUrl, super.key});

  final AppRouter router;
  final bool hasServerUrl;

  @override
  ConsumerState<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends ConsumerState<FluxApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState is AuthAuthenticated) {
        widget.router.replace(const MainRoute());
      } else if (widget.hasServerUrl) {
        widget.router.replace(const LoginRoute());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).settings;

    ref.listen(authProvider, (previous, next) {
      if (previous is AuthAuthenticated && next is AuthInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.router.replace(const LoginRoute());
        });
      }
    });

    return MaterialApp.router(
      title: 'Flux Media Server',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      locale: Locale(settings.locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: widget.router.config(),
    );
  }
}
```

---

## Task 7: Update Settings Screen with Language Selector

**Files:**
- Modify: `frontend/lib/features/settings/presentation/screens/settings_screen.dart`

- [ ] **Step 1: Add language selector and localize strings**

Replace the settings screen with a version that:
- Uses `AppLocalizations` for all strings
- Shows current server URL (read-only) with "Edit" button
- Has language toggle (EN/RU) inline
- Shows account section with logout
- Shows app version

---

## Task 8: Build Verification

- [ ] **Step 1: Run build_runner**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: Run analyzer**

Run: `cd frontend && flutter analyze`
Expected: No errors (info-level warnings OK)

- [ ] **Step 3: Commit**

```bash
git add frontend/
git commit -m "feat: Phase 3 — navigation redesign (Video/Audio tabs) + EN/RU localization"
```
