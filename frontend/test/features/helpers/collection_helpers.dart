import 'package:flux_media_server/shared/models/collection.dart';
import 'package:flux_media_server/shared/models/media.dart';

/// Тестовая коллекция: иерархия строится только через [parentId].
Collection testCollection(
  int id,
  String name, {
  int? parentId,
  MediaType type = MediaType.video,
}) => Collection(
  id: id,
  userId: 1,
  name: name,
  type: type,
  createdAt: DateTime.utc(2024),
  updatedAt: DateTime.utc(2024),
  parentId: parentId,
);
