import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/widgets/main_screen.dart';
import 'package:flux_media_server/features/audio/presentation/screens/artist_page.dart';
import 'package:flux_media_server/features/audio/presentation/screens/audio_screen.dart';
import 'package:flux_media_server/features/auth/presentation/providers/auth_provider.dart';
import 'package:flux_media_server/features/auth/presentation/providers/is_offline_provider.dart';
import 'package:flux_media_server/features/auth/presentation/screens/code_screen.dart';
import 'package:flux_media_server/features/auth/presentation/screens/login_screen.dart';
import 'package:flux_media_server/features/collections/presentation/screens/collection_detail_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/media_detail_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/upload_screen.dart';
import 'package:flux_media_server/features/player/presentation/screens/audio_player_screen.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_screen.dart';
import 'package:flux_media_server/features/player/presentation/widgets/audio_mini_player.dart';
import 'package:flux_media_server/features/settings/presentation/screens/server_setup_screen.dart';
import 'package:flux_media_server/features/settings/presentation/screens/settings_screen.dart';
import 'package:flux_media_server/features/video/presentation/screens/video_screen.dart';
import 'package:flux_media_server/shared/models/collection.dart';
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
            AutoRoute(page: VideoRoute.page, initial: true, keepHistory: false),
            AutoRoute(page: AudioRoute.page, keepHistory: false),
          ],
        ),
        AutoRoute(page: MediaDetailRoute.page, guards: [authGuard]),
        AutoRoute(page: PlayerRoute.page, guards: [authGuard]),
        AutoRoute(page: AudioPlayerRoute.page, guards: [authGuard]),
        AutoRoute(page: UploadRoute.page, guards: [authGuard]),
        AutoRoute(page: SettingsRoute.page, guards: [authGuard]),
        AutoRoute(page: ArtistRoute.page, guards: [authGuard]),
        AutoRoute(page: CollectionDetailRoute.page, guards: [authGuard]),
      ];
}

/// Тонкая обёртка над [MainScreen] из core/widgets: поставляет ему
/// провайдеры и маршруты фич, чтобы core/widgets не импортировал features.
@RoutePage(name: 'MainRoute')
class MainRoutePage extends ConsumerWidget {
  const MainRoutePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    return MainScreen(
      tabs: const [VideoRoute(), AudioRoute()],
      settingsRoute: const SettingsRoute(),
      miniPlayer: const AudioMiniPlayer(),
      isOffline: isOffline,
      onRetry: () => ref.invalidate(authProvider),
    );
  }
}
