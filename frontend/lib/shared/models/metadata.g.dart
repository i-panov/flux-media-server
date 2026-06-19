// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MetadataImpl _$$MetadataImplFromJson(Map<String, dynamic> json) =>
    _$MetadataImpl(
      id: (json['id'] as num).toInt(),
      externalId: json['externalId'] as String?,
      source: json['source'] as String?,
      title: json['title'] as String?,
      year: (json['year'] as num?)?.toInt(),
      description: json['description'] as String?,
      posterUrl: json['posterUrl'] as String?,
      backdropUrl: json['backdropUrl'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      genres:
          (json['genres'] as List<dynamic>?)?.map((e) => e as String).toList(),
      cast: (json['cast'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$$MetadataImplToJson(_$MetadataImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'externalId': instance.externalId,
      'source': instance.source,
      'title': instance.title,
      'year': instance.year,
      'description': instance.description,
      'posterUrl': instance.posterUrl,
      'backdropUrl': instance.backdropUrl,
      'rating': instance.rating,
      'genres': instance.genres,
      'cast': instance.cast,
    };
