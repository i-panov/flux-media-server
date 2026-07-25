// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CollectionImpl _$$CollectionImplFromJson(Map<String, dynamic> json) =>
    _$CollectionImpl(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      name: json['name'] as String,
      type: json['type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$CollectionImplToJson(_$CollectionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'name': instance.name,
      'type': instance.type,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_$CollectionItemImpl _$$CollectionItemImplFromJson(Map<String, dynamic> json) =>
    _$CollectionItemImpl(
      id: (json['id'] as num).toInt(),
      collectionId: (json['collection_id'] as num).toInt(),
      mediaId: (json['media_id'] as num).toInt(),
      addedAt: DateTime.parse(json['added_at'] as String),
    );

Map<String, dynamic> _$$CollectionItemImplToJson(
        _$CollectionItemImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'collection_id': instance.collectionId,
      'media_id': instance.mediaId,
      'added_at': instance.addedAt.toIso8601String(),
    };
