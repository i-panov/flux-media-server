// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MetadataImpl _$$MetadataImplFromJson(Map<String, dynamic> json) =>
    _$MetadataImpl(
      id: (json['id'] as num).toInt(),
      externalId: json['external_id'] as String?,
      source: json['source'] as String?,
      title: json['title'] as String?,
      year: (json['year'] as num?)?.toInt(),
      description: json['description'] as String?,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      genres: _stringListFromJson(json['genres']),
      cast: _stringListFromJson(json['cast']),
    );

Map<String, dynamic> _$$MetadataImplToJson(_$MetadataImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'external_id': instance.externalId,
      'source': instance.source,
      'title': instance.title,
      'year': instance.year,
      'description': instance.description,
      'poster_url': instance.posterUrl,
      'backdrop_url': instance.backdropUrl,
      'rating': instance.rating,
      'genres': _stringListToJson(instance.genres),
      'cast': _stringListToJson(instance.cast),
    };
