import 'package:flutter/material.dart';
import 'package:flux_media_server/core/widgets/skeleton_widget.dart';

/// Сетка «плашек» на время загрузки списка медиа.
///
/// Раньше идентичный `GridView.builder` на 27 строк жил в
/// `video_screen` и `collection_detail_screen` — правка одного параметра
/// требовала синхронизации двух копий.
class SkeletonMediaGrid extends StatelessWidget {
  const new({
    required this.itemCount,
    required this.gridDelegate,
    super.key,
    this.padding = const EdgeInsets.all(8),
  });

  final int itemCount;
  final SliverGridDelegate gridDelegate;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: gridDelegate,
      itemCount: itemCount,
      itemBuilder: (context, index) => const Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SkeletonWidget(
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonWidget(height: 14, width: double.infinity),
                  SizedBox(height: 6),
                  SkeletonWidget(height: 10, width: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
