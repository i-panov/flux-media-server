import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorite_toggle_provider.dart';
import 'package:flux_media_server/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:flux_media_server/shared/models/favorite.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_repositories.dart';

/// Auth в начальном состоянии без поднятия цепочки API-клиентов.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.initial();
}

void main() {
  late ProviderContainer container;
  late FakeFavoritesRepository favoritesRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    favoritesRepo = FakeFavoritesRepository();
    container = ProviderContainer(
      // Как в main.dart: Riverpod 3 ретраит упавшие build-и, и цепочка
      // favorites→ids висела бы в loading-with-error весь тест вместо
      // быстрого провала в error-ветки.
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(_FakeAuthNotifier.new),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
      ],
    );
    // favoriteToggleProvider — autoDispose: без подписки состояние
    // уйдёт между await и тесты станут flaky. Подписка — только ПОСЛЕ
    // конфигурации репозитория в каждом тесте: listen сразу строит
    // цепочку, и ранний билд с onGetFavorites == null уронил бы её
    // в ошибку навсегда (favoritesProvider — keepAlive).
    addTearDown(container.dispose);
  });

  void keepAlive() {
    final sub = container.listen(favoriteToggleProvider(2), (_, _) {});
    addTearDown(sub.close);
  }

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  AsyncValue<bool> readToggle() => container.read(favoriteToggleProvider(2));

  test('пока ids грузятся — loading, а не data(false)', () async {
    final gate = Completer<Either<Failure, List<Favorite>>>();
    favoritesRepo.onGetFavorites = () => gate.future;
    keepAlive();

    // Читаем до завершения загрузки ids.
    final first = container.read(favoriteToggleProvider(2));
    expect(first, isA<AsyncLoading<bool>>());

    gate.complete(const Right([]));
    await flush();

    expect(readToggle(), const AsyncData(false));
  });

  test('toggle добавляет в избранное и отражает в состоянии', () async {
    favoritesRepo.onGetFavorites = () async => Right([favorite(mediaId: 1)]);
    // ignore: cascade_invocations — каскад здесь нельзя: '..' после '=>' распарсится внутрь тела лямбды (грамматика Dart), сломав присваивание (проверено падением компиляции).
    favoritesRepo.onAddFavorite = (mediaId) async =>
        Right(favorite(id: 9, mediaId: mediaId));
    keepAlive();
    await flush();
    expect(readToggle(), const AsyncData(false));

    await container.read(favoriteToggleProvider(2).notifier).toggle();
    await flush();

    expect(favoritesRepo.addFavoriteCalls, [2]);
    expect(readToggle(), const AsyncData(true));
  });

  test('toggle снимает избранное и отражает в состоянии', () async {
    favoritesRepo.onGetFavorites = () async => Right([favorite(mediaId: 2)]);
    // ignore: cascade_invocations — каскад здесь нельзя, см. комментарий выше.
    favoritesRepo.onRemoveFavorite =
        (_) async => const Right<Failure, void>(null);
    keepAlive();
    await flush();
    expect(readToggle(), const AsyncData(true));

    await container.read(favoriteToggleProvider(2).notifier).toggle();
    await flush();

    expect(favoritesRepo.removeFavoriteCalls, [2]);
    expect(readToggle(), const AsyncData(false));
  });

  test('ошибка репозитория оставляет предыдущее состояние', () async {
    favoritesRepo.onGetFavorites = () async => const Right([]);
    // ignore: cascade_invocations — каскад здесь нельзя, см. комментарий выше.
    favoritesRepo.onAddFavorite =
        (_) async => const Left(ServerFailure(message: 'boom'));
    keepAlive();
    await flush();
    expect(readToggle(), const AsyncData(false));

    await container.read(favoriteToggleProvider(2).notifier).toggle();
    await flush();

    expect(readToggle(), const AsyncData(false));
  });

  test('первичная ошибка загрузки — осознанный фолбэк в data(false)', () async {
    // Зафиксировано намеренно: строки остаются интерактивными, toggle
    // перечитывает источник истины. См. комментарий у error-ветки build.
    favoritesRepo.onGetFavorites = () async =>
        const Left(ServerFailure(message: 'offline'));
    keepAlive();
    await flush();

    final state = readToggle();
    expect(state, const AsyncData(false));
    expect(state, isNot(isA<AsyncLoading<bool>>()));
  });
}
