// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Lyrics _$LyricsFromJson(Map<String, dynamic> json) => _Lyrics(
  id: (json['id'] as num).toInt(),
  mediaId: (json['media_id'] as num).toInt(),
  source: json['source'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  lyricsText: json['lyrics_text'] as String? ?? '',
  translation: json['translation'] as String? ?? '',
  syncData: json['sync_data'] as String? ?? '',
);

Map<String, dynamic> _$LyricsToJson(_Lyrics instance) => <String, dynamic>{
  'id': instance.id,
  'media_id': instance.mediaId,
  'source': instance.source,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'lyrics_text': instance.lyricsText,
  'translation': instance.translation,
  'sync_data': instance.syncData,
};
