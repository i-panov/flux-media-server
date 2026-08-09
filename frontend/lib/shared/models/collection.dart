import 'package:flux_media_server/shared/models/media.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'collection.freezed.dart';
part 'collection.g.dart';

@freezed
class Collection with _$Collection {
  const factory Collection({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    required String name,
    @MediaTypeConverter() required MediaType type,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Collection;

  factory Collection.fromJson(Map<String, dynamic> json) =>
      _$CollectionFromJson(json);
}

@freezed
class CollectionItem with _$CollectionItem {
  const factory CollectionItem({
    required int id,
    @JsonKey(name: 'collection_id') int? collectionId,
    @JsonKey(name: 'media_id') int? mediaId,
    @JsonKey(name: 'added_at') DateTime? addedAt,
    @JsonKey(name: 'position') int? position,
  }) = _CollectionItem;

  factory CollectionItem.fromJson(Map<String, dynamic> json) =>
      _$CollectionItemFromJson(json);
}
