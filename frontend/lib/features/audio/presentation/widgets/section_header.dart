import 'package:flutter/material.dart';

/// Заголовок секции: иконка + название + опциональное действие (trailing).
/// Единая замена 6 дублирующих копий на экранах audio/video.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.icon,
    required this.title,
    super.key,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// [SectionHeader] для sliver-списков (обёртка в [SliverToBoxAdapter]).
class SliverSectionHeader extends StatelessWidget {
  const SliverSectionHeader({
    required this.icon,
    required this.title,
    super.key,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SectionHeader(icon: icon, title: title, trailing: trailing),
    );
  }
}
