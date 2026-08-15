// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaImpl _$$MediaImplFromJson(Map<String, dynamic> json) => _$MediaImpl(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      type: const MediaTypeConverter().fromJson(json['type']),
      fileSize: (json['file_size'] as num).toInt(),
      filename: json['filename'] as String? ?? '',
      year: (json['year'] as num?)?.toInt(),
      description: json['description'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnail_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      artists: (json['artists'] as List<dynamic>?)
              ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Artist>[],
      album: json['album'] as String?,
      genre: json['genre'] as String?,
      metadata: json['metadata'] == null
          ? null
          : Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      fileHash: json['file_hash'] as String? ?? '',
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$$MediaImplToJson(_$MediaImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'type': const MediaTypeConverter().toJson(instance.type),
      'file_size': instance.fileSize,
      'filename': instance.filename,
      'year': instance.year,
      'description': instance.description,
      'duration': instance.duration,
      'thumbnail_url': instance.thumbnailUrl,
      'cover_url': instance.coverUrl,
      'artists': instance.artists.map((e) => e.toJson()).toList(),
      'album': instance.album,
      'genre': instance.genre,
      'metadata': instance.metadata?.toJson(),
      'file_hash': instance.fileHash,
      'updated_at': instance.updatedAt?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
    };
