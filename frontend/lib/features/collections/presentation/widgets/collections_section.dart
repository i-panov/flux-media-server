import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/router/app_router.dart';
import 'package:flux_media_server/core/utils/extensions.dart';
import 'package:flux_media_server/core/utils/feedback.dart';
import 'package:flux_media_server/features/audio/presentation/widgets/section_header.dart';
import 'package:flux_media_server/features/collections/presentation/providers/collections_provider.dart';
import 'package:flux_media_server/features/collections/presentation/utils/collection_tree.dart';
import 'package:flux_media_server/features/collections/presentation/widgets/create_collection_dialog.dart';
import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Секция «Мои коллекции» на главном экране раздела.
///
/// Живёт в features/collections, а не в экране видео: секция нужна обоим
/// разделам, а тип коллекции — параметр. Раньше виджет был приватным в
/// video_screen, и в аудио-разделе коллекции не показывались вообще —
/// создать коллекцию для аудио было можно, а открыть её нельзя.
class CollectionsSection extends ConsumerWidget {
  const new({required this.mediaType, super.key});

  /// Тип коллекций, которые показываем: видео-раздел — video, аудио — audio.
  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Корневые — через buildCollectionTree, а не фильтром
    // `parentId == null`: сирота (родитель удалён или в корзине) тоже
    // корень, и простой фильтр спрятал бы такую коллекцию навсегда —
    // до неё не дошёл бы никто. Лес строится тем же хелпером, что и на
    // экране коллекции и в диалоге перемещения, поэтому «что считается
    // корнем» везде одинаково.
    final forest = buildCollectionTree(
      ref.watch(collectionsProvider).value ?? const <Collection>[],
    );
    final collections = [
      for (final node in forest)
        if (node.collection.type == mediaType) node.collection,
    ];

    return SliverToBoxAdapter(
      child: _CollectionsRow(
        collections: collections,
        mediaType: mediaType,
        onItemTapped: (id) {
          // firstWhere мог бросить StateError — идём циклом.
          for (final c in collections) {
            if (c.id == id) {
              unawaited(
                context.router.push(CollectionDetailRoute(collection: c)),
              );
              return;
            }
          }
        },
      ),
    );
  }
}

/// Ряд обложек коллекций.
class _CollectionsRow extends ConsumerWidget {
  const new({
    required this.collections,
    required this.mediaType,
    required this.onItemTapped,
  });

  final List<Collection> collections;
  final MediaType mediaType;
  final ValueChanged<int> onItemTapped;

  /// Создание коллекции прямо из секции.
  ///
  /// Отдельный вход нужен потому, что коллекции раньше создавались
  /// только как побочка «добавить файл» — а коллекцию без файла создать
  /// было нечем. Секция показывается и пустой: с пустой коллекцией
  /// строка исчезла бы вместе с кнопкой.
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showCreateCollectionDialog(
      context,
      type: mediaType,
    );
    if (created == null || !context.mounted) return;
    showSuccessSnackBar(
      context,
      context.l10n.createdCollection(created.name),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.folder,
          title: l.myCollections,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.newCollection,
            onPressed: () => _create(context, ref),
          ),
        ),
        if (collections.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: collections.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final collection = collections[index];
                return GestureDetector(
                  onTap: () => onItemTapped(collection.id),
                  child: Container(
                    width: 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          mediaType == MediaType.audio
                              ? Icons.album
                              : Icons.video_library,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          collection.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
