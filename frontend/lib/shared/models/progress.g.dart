// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WatchProgressImpl _$$WatchProgressImplFromJson(Map<String, dynamic> json) =>
    _$WatchProgressImpl(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      mediaId: (json['mediaId'] as num).toInt(),
      position: (json['position'] as num).toInt(),
      duration: (json['duration'] as num).toInt(),
      completed: json['completed'] as bool,
    );

Map<String, dynamic> _$$WatchProgressImplToJson(_$WatchProgressImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'mediaId': instance.mediaId,
      'position': instance.position,
      'duration': instance.duration,
      'completed': instance.completed,
    };
