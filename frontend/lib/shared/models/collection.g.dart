// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Collection _$CollectionFromJson(Map<String, dynamic> json) => _Collection(
  id: (json['id'] as num).toInt(),
  userId: (json['user_id'] as num).toInt(),
  name: json['name'] as String,
  type: const MediaTypeConverter().fromJson(json['type']),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$CollectionToJson(_Collection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'name': instance.name,
      'type': const MediaTypeConverter().toJson(instance.type),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_CollectionItem _$CollectionItemFromJson(Map<String, dynamic> json) =>
    _CollectionItem(
      id: (json['id'] as num).toInt(),
      collectionId: (json['collection_id'] as num?)?.toInt(),
      mediaId: (json['media_id'] as num?)?.toInt(),
      addedAt: json['added_at'] == null
          ? null
          : DateTime.parse(json['added_at'] as String),
      position: (json['position'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CollectionItemToJson(_CollectionItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'collection_id': instance.collectionId,
      'media_id': instance.mediaId,
      'added_at': instance.addedAt?.toIso8601String(),
      'position': instance.position,
    };
