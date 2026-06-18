import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:flux_media_server/features/auth/presentation/screens/code_screen.dart';
import 'package:flux_media_server/features/auth/presentation/screens/login_screen.dart';
import 'package:flux_media_server/features/library/presentation/screens/library_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/media_detail_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/media_list_screen.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_screen.dart';
import 'package:flux_media_server/features/settings/presentation/screens/settings_screen.dart';
import 'package:flux_media_server/shared/models/media.dart';

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
      routes: [
        const MediaListRoute(),
        const LibraryRoute(),
        const SettingsRoute(),
      ],
      bottomNavigationBuilder: (context, tabsRouter) {
        return NavigationBar(
          selectedIndex: tabsRouter.activeIndex,
          onDestinationSelected: tabsRouter.setActiveIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie),
              label: 'Media',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music),
              label: 'Libraries',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        );
      },
    );
  }
}
