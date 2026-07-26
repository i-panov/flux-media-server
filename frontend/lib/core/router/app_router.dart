import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:flux_media_server/features/auth/presentation/screens/code_screen.dart';
import 'package:flux_media_server/features/auth/presentation/screens/login_screen.dart';
import 'package:flux_media_server/features/audio/presentation/screens/audio_screen.dart';
import 'package:flux_media_server/features/audio/presentation/screens/artist_page.dart';
import 'package:flux_media_server/features/video/presentation/screens/video_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/media_detail_screen.dart';
import 'package:flux_media_server/features/media/presentation/screens/upload_screen.dart';
import 'package:flux_media_server/features/player/presentation/screens/player_screen.dart';
import 'package:flux_media_server/features/player/presentation/screens/audio_player_screen.dart';
import 'package:flux_media_server/features/player/presentation/widgets/audio_mini_player.dart';
import 'package:flux_media_server/features/collections/presentation/screens/collection_detail_screen.dart';
import 'package:flux_media_server/features/settings/presentation/screens/server_setup_screen.dart';
import 'package:flux_media_server/features/settings/presentation/screens/settings_screen.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';
import 'package:flux_media_server/shared/models/media.dart';
import 'package:flux_media_server/shared/models/collection.dart';

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
        AutoRoute(page: AudioPlayerRoute.page),
        AutoRoute(page: UploadRoute.page),
        AutoRoute(page: SettingsRoute.page),
        AutoRoute(page: ArtistRoute.page),
        AutoRoute(page: CollectionDetailRoute.page),
      ];
}

@RoutePage()
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    // Build localized destinations.
    final destinations = [
      (icon: Icons.movie_outlined, selectedIcon: Icons.movie, label: l.videoTab),
      (icon: Icons.music_note_outlined, selectedIcon: Icons.music_note, label: l.audioTab),
    ];

    if (isWide) {
      return _WideLayout(destinations: destinations, settingsLabel: l.settings);
    }
    return _NarrowLayout(destinations: destinations);
  }
}

/// Desktop/tablet layout with NavigationRail on the left.
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.destinations, required this.settingsLabel});

  final List<({IconData icon, IconData selectedIcon, String label})> destinations;
  final String settingsLabel;

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      routes: const [
        VideoRoute(),
        AudioRoute(),
      ],
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: tabsRouter.activeIndex,
                onDestinationSelected: tabsRouter.setActiveIndex,
                extended: MediaQuery.of(context).size.width >= 1200,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
                trailing: Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: settingsLabel,
                          onPressed: () => AutoRouter.of(context).push(const SettingsRoute()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: child),
                    const AudioMiniPlayer(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mobile layout with bottom NavigationBar.
class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.destinations});

  final List<({IconData icon, IconData selectedIcon, String label})> destinations;

  @override
  Widget build(BuildContext context) {
    return AutoTabsScaffold(
      routes: const [
        VideoRoute(),
        AudioRoute(),
      ],
      bottomNavigationBuilder: (context, tabsRouter) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AudioMiniPlayer(),
            NavigationBar(
              selectedIndex: tabsRouter.activeIndex,
              onDestinationSelected: tabsRouter.setActiveIndex,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

