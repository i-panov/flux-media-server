// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaImpl _$$MediaImplFromJson(Map<String, dynamic> json) => _$MediaImpl(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      year: (json['year'] as num).toInt(),
      type: json['type'] as String,
      filePath: json['filePath'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      description: json['description'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      metadata: json['metadata'] == null
          ? null
          : Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      fileHash: json['fileHash'] as String? ?? '',
    );

Map<String, dynamic> _$$MediaImplToJson(_$MediaImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'year': instance.year,
      'type': instance.type,
      'filePath': instance.filePath,
      'fileSize': instance.fileSize,
      'description': instance.description,
      'duration': instance.duration,
      'thumbnailUrl': instance.thumbnailUrl,
      'metadata': instance.metadata,
      'fileHash': instance.fileHash,
    };
