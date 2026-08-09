// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FavoriteImpl _$$FavoriteImplFromJson(Map<String, dynamic> json) =>
    _$FavoriteImpl(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      mediaId: (json['media_id'] as num?)?.toInt(),
      artistId: (json['artist_id'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$FavoriteImplToJson(_$FavoriteImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'created_at': instance.createdAt.toIso8601String(),
      'media_id': instance.mediaId,
      'artist_id': instance.artistId,
    };
