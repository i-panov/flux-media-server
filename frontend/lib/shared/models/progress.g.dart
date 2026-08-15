// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WatchProgressImpl _$$WatchProgressImplFromJson(Map<String, dynamic> json) =>
    _$WatchProgressImpl(
      userId: (json['user_id'] as num).toInt(),
      mediaId: (json['media_id'] as num).toInt(),
      position: (json['position'] as num).toInt(),
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      completed: json['completed'] as bool? ?? false,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      id: (json['id'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$WatchProgressImplToJson(_$WatchProgressImpl instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'media_id': instance.mediaId,
      'position': instance.position,
      'duration': instance.duration,
      'completed': instance.completed,
      'updated_at': instance.updatedAt?.toIso8601String(),
      'id': instance.id,
    };
