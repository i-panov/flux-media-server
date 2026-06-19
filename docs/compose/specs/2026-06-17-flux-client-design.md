# Flux Media Player — Flutter Client Design

## [S1] Обзор проекта

**Flux Media Player** — клиент для Flux Media Server, медиа-сервера для просмотра видео (кино, сериалы).

**Стек клиента:**
- Язык: Dart
- UI: Flutter
- State management: Riverpod + Riverpod Generator
- Навигация: AutoRoute
- API: Chopper
- Модели: Freezed + fast_immutable_collections
- Видеоплеер: MediaKit

**Платформы:**
- Фаза 1: Web, Linux
- Фаза 2: Android

**Принципы:**
- Clean Architecture (domain/data/presentation)
- Feature-first структура
- Immutable модели через Freezed
- Unit-тесты для domain слоя

## [S2] Архитектура

```
frontend/lib/
├── core/
│   ├── error/
│   │   ├── failures.dart
│   │   └── exceptions.dart
│   ├── network/
│   │   ├── api_client.dart
│   │   ├── interceptors/
│   │   │   └── auth_interceptor.dart
│   │   └── network_info.dart
│   ├── router/
│   │   └── app_router.dart
│   ├── theme/
│   │   └── app_theme.dart
│   ├── usecases/
│   │   └── usecase.dart
│   └── utils/
│       └── extensions.dart
├── features/
│   ├── auth/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── user.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       ├── request_code.dart
│   │   │       ├── verify_code.dart
│   │   │       └── get_current_user.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── user_dto.dart
│   │   │   ├── datasources/
│   │   │   │   └── auth_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── auth_repository_impl.dart
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── auth_provider.dart
│   │       ├── screens/
│   │       │   ├── login_screen.dart
│   │       │   └── code_screen.dart
│   │       └── widgets/
│   │           └── email_input.dart
│   ├── media/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── media.dart
│   │   │   ├── repositories/
│   │   │   │   └── media_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_media_list.dart
│   │   │       ├── get_media_detail.dart
│   │   │       ├── create_media.dart
│   │   │       ├── update_media.dart
│   │   │       └── delete_media.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── media_dto.dart
│   │   │   ├── datasources/
│   │   │   │   └── media_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── media_repository_impl.dart
│   │   └── presentation/
│   │       ├── providers/
│   │       │   ├── media_list_provider.dart
│   │       │   └── media_detail_provider.dart
│   │       ├── screens/
│   │       │   ├── media_list_screen.dart
│   │       │   └── media_detail_screen.dart
│   │       └── widgets/
│   │           ├── media_card.dart
│   │           └── media_grid.dart
│   ├── player/
│   │   ├── domain/
│   │   │   └── entities/
│   │   │       └── player_state.dart
│   │   ├── data/
│   │   │   └── datasources/
│   │   │       └── video_player_datasource.dart
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── player_provider.dart
│   │       └── screens/
│   │           └── player_screen.dart
│   ├── library/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── library.dart
│   │   │   ├── repositories/
│   │   │   │   └── library_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_libraries.dart
│   │   │       ├── create_library.dart
│   │   │       ├── update_library.dart
│   │   │       ├── delete_library.dart
│   │   │       └── scan_library.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── library_dto.dart
│   │   │   ├── datasources/
│   │   │   │   └── library_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── library_repository_impl.dart
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── library_provider.dart
│   │       └── screens/
│   │           └── library_screen.dart
│   ├── progress/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── progress.dart
│   │   │   ├── repositories/
│   │   │   │   └── progress_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_progress.dart
│   │   │       ├── update_progress.dart
│   │   │       └── delete_progress.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── progress_dto.dart
│   │   │   ├── datasources/
│   │   │   │   └── progress_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── progress_repository_impl.dart
│   │   └── presentation/
│   │       └── providers/
│   │           └── progress_provider.dart
│   └── settings/
│       ├── domain/
│       │   └── entities/
│       │       └── app_settings.dart
│       ├── data/
│       │   ├── datasources/
│       │   │   └── settings_local_datasource.dart
│       │   └── repositories/
│       │       └── settings_repository_impl.dart
│       └── presentation/
│           ├── providers/
│           │   └── settings_provider.dart
│           └── screens/
│               └── settings_screen.dart
├── shared/
│   ├── models/
│   │   ├── media.dart
│   │   ├── user.dart
│   │   ├── library.dart
│   │   ├── progress.dart
│   │   └── metadata.dart
│   └── extensions/
│       └── date_extensions.dart
└── main.dart
```

### Уровни архитектуры

| Уровень | Ответственность | Зависит от |
|---------|-----------------|------------|
| **domain** | Business entities, repository interfaces, use cases | Ничего (чистый Dart) |
| **data** | DTO models, remote/local datasources, repository implementations | domain |
| **presentation** | UI, providers, screens, widgets | domain |

## [S3] Модели (Freezed)

### Domain Entities

```dart
// shared/models/media.dart
@freezed
class Media with _$Media {
  const factory Media({
    required int id,
    required String title,
    required int year,
    required String type,
    required String filePath,
    required int fileSize,
    String? description,
    int? duration,
    String? thumbnailUrl,
    Metadata? metadata,
    @Default('') String fileHash,
  }) = _Media;
}

// shared/models/user.dart
@freezed
class User with _$User {
  const factory User({
    required int id,
    required String email,
  }) = _User;
}

// shared/models/library.dart
@freezed
class MediaLibrary with _$MediaLibrary {
  const factory MediaLibrary({
    required int id,
    required String name,
    required String path,
    required String type,
    required bool enabled,
    int? scanInterval,
  }) = _MediaLibrary;
}

// shared/models/progress.dart
@freezed
class WatchProgress with _$WatchProgress {
  const factory WatchProgress({
    required int id,
    required int userId,
    required int mediaId,
    required int position,
    required int duration,
    required bool completed,
  }) = _WatchProgress;
}

// shared/models/metadata.dart
@freezed
class Metadata with _$Metadata {
  const factory Metadata({
    required int id,
    String? externalId,
    String? source,
    String? title,
    int? year,
    String? description,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    List<String>? genres,
    List<String>? cast,
  }) = _Metadata;
}
```

### DTO Models (для API)

```dart
// features/media/data/models/media_dto.dart
@freezed
class MediaDto with _$MediaDto {
  const factory MediaDto({
    required int id,
    required String title,
    required int year,
    required String type,
    required String filePath,
    required int fileSize,
    String? description,
    int? duration,
    String? thumbnailUrl,
    MetadataDto? metadata,
    @Default('') String fileHash,
  }) = _MediaDto;

  factory MediaDto.fromJson(Map<String, dynamic> json) => _$MediaDtoFromJson(json);
}
```

### State Models

```dart
// features/auth/presentation/providers/auth_provider.dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthInitial;
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.codeSent({required String email}) = AuthCodeSent;
  const factory AuthState.authenticated({required User user}) = AuthAuthenticated;
  const factory AuthState.error({required String message}) = AuthError;
}

// features/media/presentation/providers/media_list_provider.dart
@freezed
class MediaListState with _$MediaListState {
  const factory MediaListState.loading() = MediaListLoading;
  const factory MediaListState.loaded({
    required List<Media> items,
    required int total,
  }) = MediaListLoaded;
  const factory MediaListState.error({required String message}) = MediaListError;
}
```

## [S4] API слой (Chopper)

```dart
// core/network/api_client.dart
@ChopperApi()
abstract class ApiClient extends ChopperService {
  static ApiClient create([String? baseUrl]) {
    final client = ChopperClient(
      baseUrl: Uri.parse(baseUrl ?? 'http://localhost:8080/api'),
      services: [_$ApiClient()],
      converter: JsonConverter(),
      interceptors: [AuthInterceptor()],
    );
    return _$ApiClient(client);
  }

  // Auth
  @Post(path: '/auth/request-code')
  Future<Response<void>> requestCode(@Body() RequestCodeRequest request);

  @Post(path: '/auth/verify-code')
  Future<Response<VerifyCodeResponse>> verifyCode(@Body() VerifyCodeRequest request);

  @Get(path: '/auth/me')
  Future<Response<UserDto>> getMe();

  // Media
  @Get(path: '/media')
  Future<Response<MediaListResponse>> getMediaList({
    @Query('type') String? type,
    @Query('year') int? year,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @Get(path: '/media/{id}')
  Future<Response<MediaDto>> getMedia(@Path('id') int id);

  @Post(path: '/media')
  Future<Response<MediaDto>> createMedia(@Body() CreateMediaRequest request);

  @Put(path: '/media/{id}')
  Future<Response<MediaDto>> updateMedia(@Path('id') int id, @Body() UpdateMediaRequest request);

  @Delete(path: '/media/{id}')
  Future<Response<void>> deleteMedia(@Path('id') int id);

  @Get(path: '/media/{id}/thumb')
  @DioResponseType(ResponseType.bytes)
  Future<Response<List<int>>> getThumbnail(@Path('id') int id);

  // Libraries
  @Get(path: '/libraries')
  Future<Response<List<MediaLibraryDto>>> getLibraries();

  @Post(path: '/libraries')
  Future<Response<MediaLibraryDto>> createLibrary(@Body() CreateLibraryRequest request);

  @Put(path: '/libraries/{id}')
  Future<Response<MediaLibraryDto>> updateLibrary(@Path('id') int id, @Body() UpdateLibraryRequest request);

  @Delete(path: '/libraries/{id}')
  Future<Response<void>> deleteLibrary(@Path('id') int id);

  @Post(path: '/libraries/{id}/scan')
  Future<Response<void>> scanLibrary(@Path('id') int id);

  // Progress
  @Get(path: '/progress')
  Future<Response<List<WatchProgressDto>>> getProgress();

  @Put(path: '/progress/{mediaId}')
  Future<Response<WatchProgressDto>> updateProgress(@Path('mediaId') int mediaId, @Body() UpdateProgressRequest request);

  @Delete(path: '/progress/{mediaId}')
  Future<Response<void>> deleteProgress(@Path('mediaId') int mediaId);

  // Metadata
  @Get(path: '/metadata/search')
  Future<Response<SearchResponse>> searchMetadata(@Query('q') String query);

  @Post(path: '/metadata/{mediaId}/refresh')
  Future<Response<MediaDto>> refreshMetadata(@Path('mediaId') int mediaId);
}
```

### Auth Interceptor

```dart
class AuthInterceptor implements Interceptor {
  final Ref ref;

  AuthInterceptor(this.ref);

  @override
  Future<Request< dynamic >> intercept(Request< dynamic > request) async {
    final token = ref.read(authTokenProvider);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }
}
```

## [S5] Провайдеры (Riverpod)

### Auth Provider

```dart
@riverpod
class Auth extends _$Auth {
  @override
  AuthState build() => const AuthState.initial();

  Future<void> requestCode(String email) async {
    state = const AuthState.loading();
    try {
      await ref.read(apiClientProvider).requestCode(
        RequestCodeRequest(email: email),
      );
      state = AuthState.codeSent(email: email);
    } catch (e) {
      state = AuthState.error(message: e.toString());
    }
  }

  Future<void> verifyCode(String email, String code) async {
    state = const AuthState.loading();
    try {
      final response = await ref.read(apiClientProvider).verifyCode(
        VerifyCodeRequest(email: email, code: code),
      );
      await _saveToken(response.body!.token);
      state = AuthState.authenticated(user: response.body!.user);
    } catch (e) {
      state = AuthState.error(message: e.toString());
    }
  }

  Future<void> logout() async {
    await _clearToken();
    state = const AuthState.initial();
  }
}
```

### Media List Provider

```dart
@riverpod
class MediaList extends _$MediaList {
  @override
  MediaListState build({String? type, int? year}) => const MediaListState.loading();

  Future<void> load() async {
    state = const MediaListState.loading();
    try {
      final response = await ref.read(apiClientProvider).getMediaList(
        type: type,
        year: year,
      );
      state = MediaListState.loaded(
        items: response.body!.items,
        total: response.body!.total,
      );
    } catch (e) {
      state = MediaListState.error(message: e.toString());
    }
  }

  Future<void> loadMore() async {
    final currentState = state;
    if (currentState is! MediaListLoaded) return;
    if (currentState.items.length >= currentState.total) return;

    try {
      final response = await ref.read(apiClientProvider).getMediaList(
        type: type,
        year: year,
        limit: 20,
        offset: currentState.items.length,
      );
      state = MediaListState.loaded(
        items: [...currentState.items, ...response.body!.items],
        total: response.body!.total,
      );
    } catch (e) {
      state = MediaListState.error(message: e.toString());
    }
  }
}
```

### Player Provider

```dart
@riverpod
class Player extends _$Player {
  @override
  PlayerState build() => const PlayerState.initial();

  Future<void> play(Media media) async {
    state = PlayerState.playing(media: media);
  }

  void pause() => state = state.copyWith(isPaused: true);
  void resume() => state = state.copyWith(isPaused: false);
  void seek(Duration position) => state = state.copyWith(position: position);
  void complete() => state = const PlayerState.completed();
}
```

## [S6] Навигация (AutoRoute)

```dart
@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  final Ref ref;

  AppRouter(this.ref);

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LoginRoute.page, initial: true),
    AutoRoute(page: CodeRoute.page),
    AutoRoute(
      page: MainRoute.page,
      children: [
        AutoRoute(page: MediaListRoute.page, initial: true),
        AutoRoute(page: LibraryRoute.page),
        AutoRoute(page: SettingsRoute.page),
      ],
    ),
    AutoRoute(page: MediaDetailRoute.page),
    AutoRoute(page: PlayerRoute.page),
  ];

  @override
  List<AutoRouteGuard> get guards => [
    AuthGuard(ref),
  ];
}

class AuthGuard extends AutoRouteGuard {
  final Ref ref;

  AuthGuard(this.ref);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final authState = ref.read(authProvider);
    if (authState is AuthAuthenticated) {
      resolver.next(true);
    } else {
      resolver.redirect(const LoginRoute());
    }
  }
}
```

## [S7] Экраны

### Auth Flow

1. **LoginScreen** — ввод email, кнопка "Получить код"
2. **CodeScreen** — ввод OTP кода, кнопка "Войти"

### Main Shell

3. **MainScreen** — BottomNavigationBar:
   - Media (список)
   - Libraries (библиотеки)
   - Settings (настройки)

### Media

4. **MediaListScreen** — GridView с карточками, pull-to-refresh, infinite scroll
5. **MediaDetailScreen** — Обложка, описание, кнопка "Смотреть", прогресс

### Player

6. **PlayerScreen** — MediaKit видеоплеер, контролы: play/pause, seek, fullscreen

### Library

7. **LibraryScreen** — Список библиотек, добавление/редактирование/удаление, запуск сканирования

### Settings

8. **SettingsScreen** — Ввод URL сервера, информация о пользователе, кнопка "Выйти"

## [S8] Зависимости

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: latest
  riverpod_annotation: latest

  # Navigation
  auto_route: latest

  # Networking
  chopper: latest
  dio: latest

  # Models
  freezed_annotation: latest
  json_annotation: latest
  fast_immutable_collections: latest

  # Video player
  media_kit: latest
  media_kit_video: latest

  # Storage
  shared_preferences: latest

  # UI
  cached_network_image: latest
  flutter_cache_manager: latest

dev_dependencies:
  flutter_test:
    sdk: flutter

  build_runner: latest
  freezed: latest
  json_serializable: latest
  chopper_generator: latest
  auto_route_generator: latest
  riverpod_generator: latest

  flutter_lints: latest
```

## [S9] Файловая структура API запросов

### Request/Response Models

```dart
// Auth
class RequestCodeRequest {
  final String email;
  RequestCodeRequest({required this.email});
}

class VerifyCodeRequest {
  final String email;
  final String code;
  VerifyCodeRequest({required this.email, required this.code});
}

class VerifyCodeResponse {
  final String token;
  final User user;
  VerifyCodeResponse({required this.token, required this.user});
}

// Media
class MediaListResponse {
  final List<Media> items;
  final int total;
  final int limit;
  final int offset;
}

class CreateMediaRequest {
  final String title;
  final int year;
  final String description;
  final String type;
  final String filePath;
}

// Library
class CreateLibraryRequest {
  final String name;
  final String path;
  final String type;
  final int scanInterval;
}

// Progress
class UpdateProgressRequest {
  final int position;
  final int duration;
  final bool completed;
}

// Metadata
class SearchResponse {
  final List<SearchResult> results;
}

class SearchResult {
  final String title;
  final int year;
}
```

## [S10] Обработка ошибок

```dart
// core/error/failures.dart
abstract class Failure {
  final String message;
  const Failure({required this.message});
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message});
}

class NetworkFailure extends Failure {
  const NetworkFailure({required super.message});
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message});
}

class AuthFailure extends Failure {
  const AuthFailure({required super.message});
}
```

### Either<Failure, T> для результатов

```dart
// В use cases
class GetMediaList {
  final MediaRepository repository;

  GetMediaList(this.repository);

  Future<Either<Failure, List<Media>>> call({String? type, int? year}) async {
    try {
      final media = await repository.getMediaList(type: type, year: year);
      return Right(media);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }
}
```

## [S11] Тестирование

- **Domain слой**: Unit-тесты для use cases и repository interfaces
- **Data слой**: Unit-тесты для DTO маппинга
- **Presentation слой**: Widget-тесты для экранов
- **Интеграционные тесты**: End-to-end тесты с моковым API

## [S12] Запуск и развертывание

```bash
# Установка зависимостей
cd frontend
flutter pub get

# Генерация кода
flutter pub run build_runner build --delete-conflicting-outputs

# Запуск (Web)
flutter run -d chrome

# Запуск (Linux)
flutter run -d linux

# Сборка APK (Phase 2)
flutter build apk --release
```
