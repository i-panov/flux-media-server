import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flux_media_server/l10n/app_localizations.dart';

/// Корневой экран с вкладками видео/аудио.
///
/// Широкая раскладка (>=900px) использует [NavigationRail], узкая —
/// [NavigationBar]. Все зависимости (вкладки, маршрут настроек,
/// мини-плеер, признак офлайна) передаются извне, чтобы core/widgets
/// не зависел от features.
class MainScreen extends StatelessWidget {
  const MainScreen({
    required this.tabs,
    required this.settingsRoute,
    required this.miniPlayer,
    required this.isOffline,
    required this.onRetry,
    super.key,
  });

  /// Вкладки, отображаемые через [AutoTabsRouter].
  final List<PageRouteInfo<dynamic>> tabs;

  /// Маршрут экрана настроек.
  final PageRouteInfo<dynamic> settingsRoute;

  /// Мини-плеер, закреплённый в нижней части экрана.
  final Widget miniPlayer;

  /// Признак офлайн-режима (показывается баннер).
  final bool isOffline;

  /// Повторная проверка доступности сервера (кнопка «Повторить»).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // Exit the app instead of navigating back to ServerSetup.
          SystemNavigator.pop();
        }
      },
      child: isWide ? _buildWide(l) : _buildNarrow(l),
    );
  }

  Widget _buildWide(AppLocalizations l) {
    return _WideLayout(
      tabs: tabs,
      destinations: _destinations(l),
      settingsLabel: l.settings,
      settingsRoute: settingsRoute,
      isOffline: isOffline,
      onRetry: onRetry,
      miniPlayer: miniPlayer,
    );
  }

  Widget _buildNarrow(AppLocalizations l) {
    return _NarrowLayout(
      tabs: tabs,
      destinations: _destinations(l),
      isOffline: isOffline,
      onRetry: onRetry,
      miniPlayer: miniPlayer,
    );
  }

  /// Локализованные пункты вкладок.
  List<({IconData icon, IconData selectedIcon, String label})> _destinations(
    AppLocalizations l,
  ) {
    return [
      (
        icon: Icons.movie_outlined,
        selectedIcon: Icons.movie,
        label: l.videoTab
      ),
      (
        icon: Icons.music_note_outlined,
        selectedIcon: Icons.music_note,
        label: l.audioTab
      ),
    ];
  }
}

/// Desktop/tablet layout with NavigationRail on the left.
class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.tabs,
    required this.destinations,
    required this.settingsLabel,
    required this.settingsRoute,
    required this.isOffline,
    required this.onRetry,
    required this.miniPlayer,
  });

  final List<PageRouteInfo<dynamic>> tabs;
  final List<({IconData icon, IconData selectedIcon, String label})>
      destinations;
  final String settingsLabel;
  final PageRouteInfo<dynamic> settingsRoute;
  final bool isOffline;
  final VoidCallback onRetry;
  final Widget miniPlayer;

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      routes: tabs,
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
                          onPressed: () =>
                              AutoRouter.of(context).push(settingsRoute),
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
                    if (isOffline) _OfflineBanner(onRetry: onRetry),
                    Expanded(child: child),
                    miniPlayer,
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

/// Offline mode banner that shows when the server is unreachable.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const Icon(Icons.cloud_off, color: Colors.white),
      backgroundColor: Colors.orange.shade800,
      content: Text(
        l.offlineMode,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: onRetry,
          child: Text(
            l.retry,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Mobile layout with bottom NavigationBar.
class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.tabs,
    required this.destinations,
    required this.isOffline,
    required this.onRetry,
    required this.miniPlayer,
  });

  final List<PageRouteInfo<dynamic>> tabs;
  final List<({IconData icon, IconData selectedIcon, String label})>
      destinations;
  final bool isOffline;
  final VoidCallback onRetry;
  final Widget miniPlayer;

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      routes: tabs,
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        return Scaffold(
          body: Column(
            children: [
              if (isOffline) _OfflineBanner(onRetry: onRetry),
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              miniPlayer,
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
          ),
        );
      },
    );
  }
}
