import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
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

    // SystemNavigator.pop работает только на мобильных (Android/iOS):
    // на web/desktop он no-op, а блокировка back съедала бы навигацию.
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return PopScope(
      canPop: !isMobile,
      onPopInvokedWithResult: isMobile
          ? (didPop, _) {
              if (!didPop) {
                // Exit the app instead of navigating back to ServerSetup.
                SystemNavigator.pop();
              }
            }
          : null,
      child: _buildScaffold(l, isWide: isWide),
    );
  }

  /// Общий каркас вкладок: навигация и контент раскладываются в
  /// зависимости от ширины. На широких экранах навигация — слева
  /// ([NavigationRail]), мини-плеер — под контентом; на узких —
  /// навигация и плеер снизу ([NavigationBar]).
  Widget _buildScaffold(AppLocalizations l, {required bool isWide}) {
    final destinations = _destinations(l);
    return AutoTabsRouter(
      routes: tabs,
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        return Scaffold(
          body: isWide
              ? Row(
                  children: [
                    _buildNavigationRail(context, tabsRouter, destinations),
                    const VerticalDivider(thickness: 1, width: 1),
                    Expanded(
                      child: _buildContent(context, child, isWide: true),
                    ),
                  ],
                )
              : _buildContent(context, child, isWide: false),
          bottomNavigationBar: isWide
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    miniPlayer,
                    _buildNavigationBar(tabsRouter, destinations),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    Widget child, {
    required bool isWide,
  }) {
    return Column(
      children: [
        if (isOffline) _OfflineBanner(onRetry: onRetry),
        Expanded(child: child),
        if (isWide) miniPlayer,
      ],
    );
  }

  Widget _buildNavigationRail(
    BuildContext context,
    TabsRouter tabsRouter,
    List<({IconData icon, IconData selectedIcon, String label})> destinations,
  ) {
    final l = AppLocalizations.of(context)!;
    return NavigationRail(
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
                tooltip: l.settings,
                onPressed: () => AutoRouter.of(context).push(settingsRoute),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationBar(
    TabsRouter tabsRouter,
    List<({IconData icon, IconData selectedIcon, String label})> destinations,
  ) {
    return NavigationBar(
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
