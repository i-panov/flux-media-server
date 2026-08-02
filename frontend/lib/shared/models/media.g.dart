// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaImpl _$$MediaImplFromJson(Map<String, dynamic> json) => _$MediaImpl(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      filename: json['filename'] as String? ?? '',
      year: (json['year'] as num?)?.toInt(),
      type: json['type'] as String,
      filePath: json['file_path'] as String? ?? '',
      fileSize: (json['file_size'] as num).toInt(),
      description: json['description'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnail_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      genre: json['genre'] as String?,
      metadata: json['metadata'] == null
          ? null
          : Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      fileHash: json['file_hash'] as String? ?? '',
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$MediaImplToJson(_$MediaImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'filename': instance.filename,
      'year': instance.year,
      'type': instance.type,
      'file_path': instance.filePath,
      'file_size': instance.fileSize,
      'description': instance.description,
      'duration': instance.duration,
      'thumbnail_url': instance.thumbnailUrl,
      'cover_url': instance.coverUrl,
      'artist': instance.artist,
      'album': instance.album,
      'genre': instance.genre,
      'metadata': instance.metadata,
      'file_hash': instance.fileHash,
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
