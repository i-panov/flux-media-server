import 'package:flux_media_server/shared/models/media_type.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'collection.freezed.dart';
part 'collection.g.dart';

@freezed
sealed class Collection with _$Collection {
  const factory({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    required String name,
    @MediaTypeConverter() required MediaType type,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Collection;

  factory fromJson(Map<String, dynamic> json) => _$CollectionFromJson(json);
}

@freezed
sealed class CollectionItem with _$CollectionItem {
  const factory({
    required int id,
    @JsonKey(name: 'collection_id') int? collectionId,
    @JsonKey(name: 'media_id') int? mediaId,
    @JsonKey(name: 'added_at') DateTime? addedAt,
    @JsonKey(name: 'position') int? position,
  }) = _CollectionItem;

  factory fromJson(Map<String, dynamic> json) => _$CollectionItemFromJson(json);
}
