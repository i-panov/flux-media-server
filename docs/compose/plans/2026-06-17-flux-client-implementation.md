# Flux Media Player — Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter client for Flux Media Server with full Clean Architecture, Riverpod state management, and video playback.

**Architecture:** Feature-first Clean Architecture with domain/data/presentation layers. Each feature is self-contained with its own models, repositories, use cases, and UI.

**Tech Stack:** Flutter, Riverpod, AutoRoute, Chopper, Freezed, MediaKit, fast_immutable_collections

---

## Task 1: Project Setup & Core Infrastructure

**Files:**
- Create: `frontend/pubspec.yaml`
- Create: `frontend/lib/core/error/failures.dart`
- Create: `frontend/lib/core/error/exceptions.dart`
- Create: `frontend/lib/core/network/network_info.dart`
- Create: `frontend/lib/core/usecases/usecase.dart`
- Create: `frontend/lib/core/utils/extensions.dart`
- Create: `frontend/lib/main.dart`

- [ ] **Step 1: Create pubspec.yaml**

```yaml
name: flux_media_player
description: Flux Media Player Client
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  flutter_riverpod: latest
  riverpod_annotation: latest
  auto_route: latest
  chopper: latest
  dio: latest
  freezed_annotation: latest
  json_annotation: latest
  fast_immutable_collections: latest
  media_kit: latest
  media_kit_video: latest
  shared_preferences: latest
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

- [ ] **Step 2: Create failures.dart**

```dart
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

- [ ] **Step 3: Create exceptions.dart**

```dart
class ServerException implements Exception {
  final String message;
  const ServerException({required this.message});
}

class CacheException implements Exception {
  final String message;
  const CacheException({required this.message});
}

class NetworkException implements Exception {
  final String message;
  const NetworkException({required this.message});
}
```

- [ ] **Step 4: Create network_info.dart**

```dart
abstract class NetworkInfo {
  Future<bool> get isConnected;
}

class NetworkInfoImpl implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}
```

- [ ] **Step 5: Create usecase.dart**

```dart
abstract class UseCase<Type, Params> {
  Future<Type> call(Params params);
}

class NoParams {}
```

- [ ] **Step 6: Create extensions.dart**

```dart
extension StringExtensions on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

extension DurationExtensions on Duration {
  String get formatted {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 7: Create main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    const ProviderScope(
      child: FluxMediaPlayerApp(),
    ),
  );
}

class FluxMediaPlayerApp extends StatelessWidget {
  const FluxMediaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flux Media Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Flux Media Player'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Install dependencies and run**

Run: `cd frontend && flutter pub get`

- [ ] **Step 9: Commit**

```bash
cd frontend
git add .
git commit -m "feat: initial project setup with core infrastructure"
```

---

## Task 2: Shared Models (Freezed)

**Files:**
- Create: `frontend/lib/shared/models/media.dart`
- Create: `frontend/lib/shared/models/user.dart`
- Create: `frontend/lib/shared/models/library.dart`
- Create: `frontend/lib/shared/models/progress.dart`
- Create: `frontend/lib/shared/models/metadata.dart`

- [ ] **Step 1: Create media.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'metadata.dart';

part 'media.freezed.dart';

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
```

- [ ] **Step 2: Create user.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

@freezed
class User with _$User {
  const factory User({
    required int id,
    required String email,
  }) = _User;
}
```

- [ ] **Step 3: Create library.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'library.freezed.dart';

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
```

- [ ] **Step 4: Create progress.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress.freezed.dart';

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
```

- [ ] **Step 5: Create metadata.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'metadata.freezed.dart';

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

- [ ] **Step 6: Generate freezed code**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 7: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add shared freezed models"
```

---

## Task 3: API Client (Chopper)

**Files:**
- Create: `frontend/lib/core/network/api_client.dart`
- Create: `frontend/lib/core/network/interceptors/auth_interceptor.dart`
- Create: `frontend/lib/core/network/api_client.chopper.dart` (generated)

- [ ] **Step 1: Create api_client.dart**

```dart
import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/media.dart';
import '../../shared/models/user.dart';
import '../../shared/models/library.dart';
import '../../shared/models/progress.dart';
import 'interceptors/auth_interceptor.dart';

part 'api_client.chopper.dart';

@ChopperApi()
abstract class ApiClient extends ChopperService {
  static ApiClient create(String baseUrl) {
    final client = ChopperClient(
      baseUrl: Uri.parse(baseUrl),
      services: [_$ApiClient()],
      converter: JsonConverter(),
      interceptors: [AuthInterceptor()],
    );
    return _$ApiClient(client);
  }

  @Post(path: '/auth/request-code')
  Future<Response<void>> requestCode(@Body() Map<String, dynamic> request);

  @Post(path: '/auth/verify-code')
  Future<Response<Map<String, dynamic>>> verifyCode(@Body() Map<String, dynamic> request);

  @Get(path: '/auth/me')
  Future<Response<Map<String, dynamic>>> getMe();

  @Get(path: '/media')
  Future<Response<Map<String, dynamic>>> getMediaList({
    @Query('type') String? type,
    @Query('year') int? year,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @Get(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> getMedia(@Path('id') int id);

  @Post(path: '/media')
  Future<Response<Map<String, dynamic>>> createMedia(@Body() Map<String, dynamic> request);

  @Put(path: '/media/{id}')
  Future<Response<Map<String, dynamic>>> updateMedia(@Path('id') int id, @Body() Map<String, dynamic> request);

  @Delete(path: '/media/{id}')
  Future<Response<void>> deleteMedia(@Path('id') int id);

  @Get(path: '/media/{id}/thumb')
  @DioResponseType(ResponseType.bytes)
  Future<Response<List<int>>> getThumbnail(@Path('id') int id);

  @Get(path: '/libraries')
  Future<Response<List<Map<String, dynamic>>>> getLibraries();

  @Post(path: '/libraries')
  Future<Response<Map<String, dynamic>>> createLibrary(@Body() Map<String, dynamic> request);

  @Put(path: '/libraries/{id}')
  Future<Response<Map<String, dynamic>>> updateLibrary(@Path('id') int id, @Body() Map<String, dynamic> request);

  @Delete(path: '/libraries/{id}')
  Future<Response<void>> deleteLibrary(@Path('id') int id);

  @Post(path: '/libraries/{id}/scan')
  Future<Response<void>> scanLibrary(@Path('id') int id);

  @Get(path: '/progress')
  Future<Response<List<Map<String, dynamic>>>> getProgress();

  @Put(path: '/progress/{mediaId}')
  Future<Response<Map<String, dynamic>>> updateProgress(@Path('mediaId') int mediaId, @Body() Map<String, dynamic> request);

  @Delete(path: '/progress/{mediaId}')
  Future<Response<void>> deleteProgress(@Path('mediaId') int mediaId);

  @Get(path: '/metadata/search')
  Future<Response<Map<String, dynamic>>> searchMetadata(@Query('q') String query);

  @Post(path: '/metadata/{mediaId}/refresh')
  Future<Response<Map<String, dynamic>>> refreshMetadata(@Path('mediaId') int mediaId);
}
```

- [ ] **Step 2: Create auth_interceptor.dart**

```dart
import 'package:chopper/chopper.dart';

class AuthInterceptor implements Interceptor {
  String? _token;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  @override
  Future<Response< dynamic >> intercept(Request< dynamic > request) async {
    if (_token != null) {
      request = request.copyWith(
        headers: {...request.headers, 'Authorization': 'Bearer $_token'},
      );
    }
    return request;
  }
}
```

- [ ] **Step 3: Generate chopper code**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add Chopper API client with auth interceptor"
```

---

## Task 4: Auth Feature

**Files:**
- Create: `frontend/lib/features/auth/domain/entities/user.dart` (alias)
- Create: `frontend/lib/features/auth/domain/repositories/auth_repository.dart`
- Create: `frontend/lib/features/auth/domain/usecases/request_code.dart`
- Create: `frontend/lib/features/auth/domain/usecases/verify_code.dart`
- Create: `frontend/lib/features/auth/domain/usecases/get_current_user.dart`
- Create: `frontend/lib/features/auth/data/datasources/auth_remote_datasource.dart`
- Create: `frontend/lib/features/auth/data/repositories/auth_repository_impl.dart`
- Create: `frontend/lib/features/auth/presentation/providers/auth_provider.dart`
- Create: `frontend/lib/features/auth/presentation/screens/login_screen.dart`
- Create: `frontend/lib/features/auth/presentation/screens/code_screen.dart`

- [ ] **Step 1: Create auth_repository.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../shared/models/user.dart';

abstract class AuthRepository {
  Future<Either<Failure, void>> requestCode(String email);
  Future<Either<Failure, ({String token, User user})>> verifyCode(String email, String code);
  Future<Either<Failure, User>> getCurrentUser();
}
```

- [ ] **Step 2: Create request_code.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

class RequestCode extends UseCase<void, String> {
  final AuthRepository repository;

  RequestCode(this.repository);

  @override
  Future<Either<Failure, void>> call(String email) {
    return repository.requestCode(email);
  }
}
```

- [ ] **Step 3: Create verify_code.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../shared/models/user.dart';
import '../repositories/auth_repository.dart';

class VerifyCodeParams {
  final String email;
  final String code;

  VerifyCodeParams({required this.email, required this.code});
}

class VerifyCode extends UseCase<({String token, User user}), VerifyCodeParams> {
  final AuthRepository repository;

  VerifyCode(this.repository);

  @override
  Future<Either<Failure, ({String token, User user})>> call(VerifyCodeParams params) {
    return repository.verifyCode(params.email, params.code);
  }
}
```

- [ ] **Step 4: Create auth_remote_datasource.dart**

```dart
import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';

class AuthRemoteDataSource {
  final ApiClient apiClient;

  AuthRemoteDataSource({required this.apiClient});

  Future<void> requestCode(String email) async {
    final response = await apiClient.requestCode({'email': email});
    if (response.error) {
      throw ServerException(message: response.error.toString());
    }
  }

  Future<({String token, Map<String, dynamic> user})> verifyCode(String email, String code) async {
    final response = await apiClient.verifyCode({'email': email, 'code': code});
    if (response.error) {
      throw ServerException(message: response.error.toString());
    }
    final body = response.body!;
    return (token: body['token'] as String, user: body['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await apiClient.getMe();
    if (response.error) {
      throw ServerException(message: response.error.toString());
    }
    return response.body!;
  }
}
```

- [ ] **Step 5: Create auth_repository_impl.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../shared/models/user.dart';
import '../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, void>> requestCode(String email) async {
    try {
      await remoteDataSource.requestCode(email);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, ({String token, User user})>> verifyCode(String email, String code) async {
    try {
      final result = await remoteDataSource.verifyCode(email, code);
      final user = User(id: result.user['id'], email: result.user['email']);
      return Right((token: result.token, user: user));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, User>> getCurrentUser() async {
    try {
      final userData = await remoteDataSource.getMe();
      return Right(User(id: userData['id'], email: userData['email']));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }
}
```

- [ ] **Step 6: Create auth_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../shared/models/user.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/usecases/request_code.dart';
import '../../domain/usecases/verify_code.dart';

part 'auth_provider.freezed.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(apiClient: ref.watch(apiClientProvider));
});

final authRepositoryProvider = Provider<AuthRepositoryImpl>((ref) {
  return AuthRepositoryImpl(remoteDataSource: ref.watch(authRemoteDataSourceProvider));
});

final requestCodeProvider = Provider<RequestCode>((ref) {
  return RequestCode(ref.watch(authRepositoryProvider));
});

final verifyCodeProvider = Provider<VerifyCode>((ref) {
  return VerifyCode(ref.watch(authRepositoryProvider));
});

@riverpod
class Auth extends _$Auth {
  @override
  AuthState build() => const AuthState.initial();

  Future<void> requestCode(String email) async {
    state = const AuthState.loading();
    final result = await ref.read(requestCodeProvider)(email);
    result.fold(
      (failure) => state = AuthState.error(message: failure.message),
      (_) => state = AuthState.codeSent(email: email),
    );
  }

  Future<void> verifyCode(String email, String code) async {
    state = const AuthState.loading();
    final result = await ref.read(verifyCodeProvider)(VerifyCodeParams(email: email, code: code));
    result.fold(
      (failure) => state = AuthState.error(message: failure.message),
      (data) => state = AuthState.authenticated(user: data.user),
    );
  }

  void logout() {
    state = const AuthState.initial();
  }
}

@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthInitial;
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.codeSent({required String email}) = AuthCodeSent;
  const factory AuthState.authenticated({required User user}) = AuthAuthenticated;
  const factory AuthState.error({required String message}) = AuthError;
}
```

- [ ] **Step 7: Create login_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Flux Media Player',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (authState is AuthError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        authState.message,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: authState is AuthLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                ref.read(authProvider.notifier).requestCode(
                                      _emailController.text,
                                    );
                              }
                            },
                      child: authState is AuthLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Get Code'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Create code_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final email = authState is AuthCodeSent ? authState.email : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Code'),
      ),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Code sent to $email',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (authState is AuthError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        authState.message,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: authState is AuthLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                ref.read(authProvider.notifier).verifyCode(
                                      email,
                                      _codeController.text,
                                    );
                              }
                            },
                      child: authState is AuthLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Generate code and test**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 10: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add auth feature with login and code screens"
```

---

## Task 5: Media Feature

**Files:**
- Create: `frontend/lib/features/media/domain/repositories/media_repository.dart`
- Create: `frontend/lib/features/media/domain/usecases/get_media_list.dart`
- Create: `frontend/lib/features/media/domain/usecases/get_media_detail.dart`
- Create: `frontend/lib/features/media/data/datasources/media_remote_datasource.dart`
- Create: `frontend/lib/features/media/data/repositories/media_repository_impl.dart`
- Create: `frontend/lib/features/media/presentation/providers/media_list_provider.dart`
- Create: `frontend/lib/features/media/presentation/providers/media_detail_provider.dart`
- Create: `frontend/lib/features/media/presentation/screens/media_list_screen.dart`
- Create: `frontend/lib/features/media/presentation/screens/media_detail_screen.dart`
- Create: `frontend/lib/features/media/presentation/widgets/media_card.dart`

- [ ] **Step 1: Create media_repository.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../shared/models/media.dart';

abstract class MediaRepository {
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({String? type, int? year, int? limit, int? offset});
  Future<Either<Failure, Media>> getMediaDetail(int id);
}
```

- [ ] **Step 2: Create get_media_list.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../shared/models/media.dart';
import '../repositories/media_repository.dart';

class GetMediaListParams {
  final String? type;
  final int? year;
  final int? limit;
  final int? offset;

  GetMediaListParams({this.type, this.year, this.limit, this.offset});
}

class GetMediaList extends UseCase<({List<Media> items, int total}), GetMediaListParams> {
  final MediaRepository repository;

  GetMediaList(this.repository);

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> call(GetMediaListParams params) {
    return repository.getMediaList(
      type: params.type,
      year: params.year,
      limit: params.limit,
      offset: params.offset,
    );
  }
}
```

- [ ] **Step 3: Create media_remote_datasource.dart**

```dart
import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';

class MediaRemoteDataSource {
  final ApiClient apiClient;

  MediaRemoteDataSource({required this.apiClient});

  Future<({List<Map<String, dynamic>> items, int total})> getMediaList({String? type, int? year, int? limit, int? offset}) async {
    final response = await apiClient.getMediaList(type: type, year: year, limit: limit, offset: offset);
    if (response.error) {
      throw ServerException(message: response.error.toString());
    }
    final body = response.body!;
    return (
      items: (body['items'] as List).cast<Map<String, dynamic>>(),
      total: body['total'] as int,
    );
  }

  Future<Map<String, dynamic>> getMedia(int id) async {
    final response = await apiClient.getMedia(id);
    if (response.error) {
      throw ServerException(message: response.error.toString());
    }
    return response.body!;
  }
}
```

- [ ] **Step 4: Create media_repository_impl.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../shared/models/media.dart';
import '../domain/repositories/media_repository.dart';
import '../datasources/media_remote_datasource.dart';

class MediaRepositoryImpl implements MediaRepository {
  final MediaRemoteDataSource remoteDataSource;

  MediaRepositoryImpl({required this.remoteDataSource});

  Media _mapToMedia(Map<String, dynamic> json) {
    return Media(
      id: json['id'] as int,
      title: json['title'] as String,
      year: json['year'] as int,
      type: json['type'] as String,
      filePath: json['file_path'] as String,
      fileSize: json['file_size'] as int,
      description: json['description'] as String?,
      duration: json['duration'] as int?,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }

  @override
  Future<Either<Failure, ({List<Media> items, int total})>> getMediaList({String? type, int? year, int? limit, int? offset}) async {
    try {
      final result = await remoteDataSource.getMediaList(type: type, year: year, limit: limit, offset: offset);
      final items = result.items.map(_mapToMedia).toList();
      return Right((items: items, total: result.total));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, Media>> getMediaDetail(int id) async {
    try {
      final json = await remoteDataSource.getMedia(id);
      return Right(_mapToMedia(json));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }
}
```

- [ ] **Step 5: Create media_list_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../shared/models/media.dart';
import '../../data/datasources/media_remote_datasource.dart';
import '../../data/repositories/media_repository_impl.dart';
import '../../domain/usecases/get_media_list.dart';

part 'media_list_provider.freezed.dart';

final mediaRemoteDataSourceProvider = Provider<MediaRemoteDataSource>((ref) {
  return MediaRemoteDataSource(apiClient: ref.watch(apiClientProvider));
});

final mediaRepositoryProvider = Provider<MediaRepositoryImpl>((ref) {
  return MediaRepositoryImpl(remoteDataSource: ref.watch(mediaRemoteDataSourceProvider));
});

final getMediaListProvider = Provider<GetMediaList>((ref) {
  return GetMediaList(ref.watch(mediaRepositoryProvider));
});

@riverpod
class MediaList extends _$MediaList {
  @override
  MediaListState build({String? type, int? year}) => const MediaListState.loading();

  Future<void> load() async {
    state = const MediaListState.loading();
    final result = await ref.read(getMediaListProvider)(
      GetMediaListParams(type: type, year: year),
    );
    result.fold(
      (failure) => state = MediaListState.error(message: failure.message),
      (data) => state = MediaListState.loaded(items: data.items, total: data.total),
    );
  }

  Future<void> loadMore() async {
    final currentState = state;
    if (currentState is! MediaListLoaded) return;
    if (currentState.items.length >= currentState.total) return;

    final result = await ref.read(getMediaListProvider)(
      GetMediaListParams(
        type: type,
        year: year,
        limit: 20,
        offset: currentState.items.length,
      ),
    );
    result.fold(
      (failure) => state = MediaListState.error(message: failure.message),
      (data) => state = MediaListState.loaded(
        items: [...currentState.items, ...data.items],
        total: data.total,
      ),
    );
  }
}

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

- [ ] **Step 6: Create media_card.dart**

```dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../shared/models/media.dart';

class MediaCard extends StatelessWidget {
  final Media media;
  final VoidCallback? onTap;

  const MediaCard({super.key, required this.media, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: media.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: media.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.error),
                      ),
                    )
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.movie, size: 48),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${media.year}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Create media_list_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/media_list_provider.dart';
import '../widgets/media_card.dart';

class MediaListScreen extends ConsumerStatefulWidget {
  const MediaListScreen({super.key});

  @override
  ConsumerState<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends ConsumerState<MediaListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ref.read(mediaListProvider().notifier).load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(mediaListProvider().notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaState = ref.watch(mediaListProvider());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Library'),
      ),
      body: mediaState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (items, total) => GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final media = items[index];
            return MediaCard(
              media: media,
              onTap: () {
                // TODO: Navigate to detail
              },
            );
          },
        ),
        error: (message) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(message),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(mediaListProvider().notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Generate code and test**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 9: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add media feature with list and card widgets"
```

---

## Task 6: Library Feature

**Files:**
- Create: `frontend/lib/features/library/domain/repositories/library_repository.dart`
- Create: `frontend/lib/features/library/domain/usecases/get_libraries.dart`
- Create: `frontend/lib/features/library/data/datasources/library_remote_datasource.dart`
- Create: `frontend/lib/features/library/data/repositories/library_repository_impl.dart`
- Create: `frontend/lib/features/library/presentation/providers/library_provider.dart`
- Create: `frontend/lib/features/library/presentation/screens/library_screen.dart`

- [ ] **Step 1: Create library_repository.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../shared/models/library.dart';

abstract class LibraryRepository {
  Future<Either<Failure, List<MediaLibrary>>> getLibraries();
  Future<Either<Failure, void>> scanLibrary(int id);
}
```

- [ ] **Step 2: Create get_libraries.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../shared/models/library.dart';
import '../repositories/library_repository.dart';

class GetLibraries extends UseCase<List<MediaLibrary>, NoParams> {
  final LibraryRepository repository;

  GetLibraries(this.repository);

  @override
  Future<Either<Failure, List<MediaLibrary>>> call(NoParams params) {
    return repository.getLibraries();
  }
}
```

- [ ] **Step 3: Create library_repository_impl.dart**

```dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../shared/models/library.dart';
import '../domain/repositories/library_repository.dart';
import '../../data/datasources/library_remote_datasource.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  final LibraryRemoteDataSource remoteDataSource;

  LibraryRepositoryImpl({required this.remoteDataSource});

  MediaLibrary _mapToLibrary(Map<String, dynamic> json) {
    return MediaLibrary(
      id: json['id'] as int,
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      enabled: json['enabled'] as bool,
      scanInterval: json['scan_interval'] as int?,
    );
  }

  @override
  Future<Either<Failure, List<MediaLibrary>>> getLibraries() async {
    try {
      final response = await remoteDataSource.getLibraries();
      final libraries = response.map(_mapToLibrary).toList();
      return Right(libraries);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> scanLibrary(int id) async {
    try {
      await remoteDataSource.scanLibrary(id);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }
}
```

- [ ] **Step 4: Create library_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../shared/models/library.dart';
import '../../data/datasources/library_remote_datasource.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/usecases/get_libraries.dart';

part 'library_provider.freezed.dart';

final libraryRemoteDataSourceProvider = Provider<LibraryRemoteDataSource>((ref) {
  return LibraryRemoteDataSource(apiClient: ref.watch(apiClientProvider));
});

final libraryRepositoryProvider = Provider<LibraryRepositoryImpl>((ref) {
  return LibraryRepositoryImpl(remoteDataSource: ref.watch(libraryRemoteDataSourceProvider));
});

final getLibrariesProvider = Provider<GetLibraries>((ref) {
  return GetLibraries(ref.watch(libraryRepositoryProvider));
});

@riverpod
class Library extends _$Library {
  @override
  LibraryState build() => const LibraryState.loading();

  Future<void> load() async {
    state = const LibraryState.loading();
    final result = await ref.read(getLibrariesProvider)(NoParams());
    result.fold(
      (failure) => state = LibraryState.error(message: failure.message),
      (libraries) => state = LibraryState.loaded(libraries: libraries),
    );
  }

  Future<void> scan(int id) async {
    await ref.read(libraryRepositoryProvider).scanLibrary(id);
    await load();
  }
}

@freezed
class LibraryState with _$LibraryState {
  const factory LibraryState.loading() = LibraryLoading;
  const factory LibraryState.loaded({required List<MediaLibrary> libraries}) = LibraryLoaded;
  const factory LibraryState.error({required String message}) = LibraryError;
}
```

- [ ] **Step 5: Create library_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(libraryProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Libraries'),
      ),
      body: libraryState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (libraries) => ListView.builder(
          itemCount: libraries.length,
          itemBuilder: (context, index) {
            final library = libraries[index];
            return ListTile(
              title: Text(library.name),
              subtitle: Text(library.path),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: library.enabled,
                    onChanged: (value) {
                      // TODO: Update library
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      ref.read(libraryProvider.notifier).scan(library.id);
                    },
                  ),
                ],
              ),
            );
          },
        ),
        error: (message) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(message),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(libraryProvider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Generate code and test**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 7: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add library feature with list and scan"
```

---

## Task 7: Settings Feature

**Files:**
- Create: `frontend/lib/features/settings/domain/entities/app_settings.dart`
- Create: `frontend/lib/features/settings/data/datasources/settings_local_datasource.dart`
- Create: `frontend/lib/features/settings/data/repositories/settings_repository_impl.dart`
- Create: `frontend/lib/features/settings/presentation/providers/settings_provider.dart`
- Create: `frontend/lib/features/settings/presentation/screens/settings_screen.dart`

- [ ] **Step 1: Create app_settings.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';

@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    String? serverUrl,
    String? authToken,
  }) = _AppSettings;
}
```

- [ ] **Step 2: Create settings_local_datasource.dart**

```dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  final SharedPreferences prefs;

  SettingsLocalDataSource({required this.prefs});

  String? getServerUrl() => prefs.getString('server_url');
  Future<void> setServerUrl(String url) => prefs.setString('server_url', url);

  String? getAuthToken() => prefs.getString('auth_token');
  Future<void> setAuthToken(String token) => prefs.setString('auth_token', token);

  Future<void> clearAuth() => prefs.remove('auth_token');
}
```

- [ ] **Step 3: Create settings_repository_impl.dart**

```dart
import '../domain/entities/app_settings.dart';
import '../data/datasources/settings_local_datasource.dart';

class SettingsRepositoryImpl {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl({required this.localDataSource});

  AppSettings getSettings() {
    return AppSettings(
      serverUrl: localDataSource.getServerUrl(),
      authToken: localDataSource.getAuthToken(),
    );
  }

  Future<void> setServerUrl(String url) => localDataSource.setServerUrl(url);

  Future<void> setAuthToken(String token) => localDataSource.setAuthToken(token);

  Future<void> clearAuth() => localDataSource.clearAuth();
}
```

- [ ] **Step 4: Create settings_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/entities/app_settings.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).value!;
  return SettingsLocalDataSource(prefs: prefs);
});

final settingsRepositoryProvider = Provider<SettingsRepositoryImpl>((ref) {
  return SettingsRepositoryImpl(localDataSource: ref.watch(settingsLocalDataSourceProvider));
});

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(settingsRepositoryProvider));
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepositoryImpl repository;

  SettingsNotifier(this.repository) : super(repository.getSettings());

  Future<void> setServerUrl(String url) async {
    await repository.setServerUrl(url);
    state = state.copyWith(serverUrl: url);
  }

  Future<void> logout() async {
    await repository.clearAuth();
    state = state.copyWith(authToken: null);
  }
}
```

- [ ] **Step 5: Create settings_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _urlController.text = settings.serverUrl ?? '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Server URL', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'http://localhost:8080',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  ref.read(settingsProvider.notifier).setServerUrl(
                        _urlController.text,
                      );
                },
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Logout'),
            leading: const Icon(Icons.logout),
            onTap: () {
              ref.read(settingsProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Generate code and test**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 7: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add settings feature with server URL configuration"
```

---

## Task 8: Player Feature

**Files:**
- Create: `frontend/lib/features/player/domain/entities/player_state.dart`
- Create: `frontend/lib/features/player/data/datasources/video_player_datasource.dart`
- Create: `frontend/lib/features/player/presentation/providers/player_provider.dart`
- Create: `frontend/lib/features/player/presentation/screens/player_screen.dart`

- [ ] **Step 1: Create player_state.dart**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../shared/models/media.dart';

part 'player_state.freezed.dart';

@freezed
class PlayerState with _$PlayerState {
  const factory PlayerState.initial() = PlayerInitial;
  const factory PlayerState.playing({
    required Media media,
    @Default(false) bool isPaused,
    @Default(Duration.zero) Duration position,
    @Default(Duration.zero) Duration duration,
  }) = PlayerPlaying;
  const factory PlayerState.completed() = PlayerCompleted;
  const factory PlayerState.error({required String message}) = PlayerError;
}
```

- [ ] **Step 2: Create player_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../shared/models/media.dart';
import '../../domain/entities/player_state.dart';

part 'player_provider.freezed.dart';

@riverpod
class Player extends _$Player {
  @override
  PlayerState build() => const PlayerState.initial();

  Future<void> play(Media media) async {
    state = PlayerState.playing(media: media);
  }

  void pause() {
    final currentState = state;
    if (currentState is PlayerPlaying) {
      state = currentState.copyWith(isPaused: true);
    }
  }

  void resume() {
    final currentState = state;
    if (currentState is PlayerPlaying) {
      state = currentState.copyWith(isPaused: false);
    }
  }

  void seek(Duration position) {
    final currentState = state;
    if (currentState is PlayerPlaying) {
      state = currentState.copyWith(position: position);
    }
  }

  void updateDuration(Duration duration) {
    final currentState = state;
    if (currentState is PlayerPlaying) {
      state = currentState.copyWith(duration: duration);
    }
  }

  void complete() {
    state = const PlayerState.completed();
  }

  void reset() {
    state = const PlayerState.initial();
  }
}
```

- [ ] **Step 3: Create player_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../providers/player_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: playerState.when(
        initial: () => const Center(
          child: Text('No media selected', style: TextStyle(color: Colors.white)),
        ),
        playing: (media, isPaused, position, duration) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Video(controller: _controller),
              if (isPaused)
                const Icon(Icons.play_arrow, size: 64, color: Colors.white),
            ],
          );
        },
        completed: () => const Center(
          child: Text('Playback completed', style: TextStyle(color: Colors.white)),
        ),
        error: (message) => Center(
          child: Text(message, style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Generate code and test**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 5: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add player feature with MediaKit integration"
```

---

## Task 9: Navigation & Router

**Files:**
- Create: `frontend/lib/core/router/app_router.dart`
- Create: `frontend/lib/core/router/app_router.gr.dart` (generated)
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Create app_router.dart**

```dart
import 'package:auto_route/auto_route.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/code_screen.dart';
import '../../features/media/presentation/screens/media_list_screen.dart';
import '../../features/media/presentation/screens/media_detail_screen.dart';
import '../../features/library/presentation/screens/library_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/player/presentation/screens/player_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
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
}

@RoutePage()
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoTabsScaffold(
      routes: const [
        MediaListRoute(),
        LibraryRoute(),
        SettingsRoute(),
      ],
      bottomNavigationBuilder: (context, tabsRouter) {
        return NavigationBar(
          selectedIndex: tabsRouter.activeIndex,
          onDestinationSelected: (index) => tabsRouter.setActiveIndex(index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.movie),
              label: 'Media',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder),
              label: 'Libraries',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: Update main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: FluxMediaPlayerApp(),
    ),
  );
}

class FluxMediaPlayerApp extends ConsumerWidget {
  const FluxMediaPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = AppRouter();

    return MaterialApp.router(
      title: 'Flux Media Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router.config(),
    );
  }
}
```

- [ ] **Step 3: Generate router code**

Run: `cd frontend && flutter pub run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: Commit**

```bash
cd frontend
git add .
git commit -m "feat: add AutoRoute navigation with bottom navigation bar"
```

---

## Task 10: Integration & Final Testing

**Files:**
- Modify: All provider files to wire up dependencies
- Modify: All screens to use proper navigation

- [ ] **Step 1: Wire up API client provider**

Add to `main.dart` or create `core/providers/api_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  final baseUrl = settings.serverUrl ?? 'http://localhost:8080/api';
  return ApiClient.create(baseUrl);
});
```

- [ ] **Step 2: Test all screens**

Run: `cd frontend && flutter test`

- [ ] **Step 3: Test on web**

Run: `cd frontend && flutter run -d chrome`

- [ ] **Step 4: Final commit**

```bash
cd frontend
git add .
git commit -m "feat: integrate all features and fix navigation"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Project Setup | 7 |
| 2 | Shared Models | 5 |
| 3 | API Client | 3 |
| 4 | Auth Feature | 10 |
| 5 | Media Feature | 10 |
| 6 | Library Feature | 6 |
| 7 | Settings Feature | 5 |
| 8 | Player Feature | 4 |
| 9 | Navigation | 2 |
| 10 | Integration | - |

**Total:** ~52 files
