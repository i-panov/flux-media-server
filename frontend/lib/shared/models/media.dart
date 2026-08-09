import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/metadata.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'media.freezed.dart';
part 'media.g.dart';

/// Custom converter for MediaType enum to/from JSON string.
class MediaTypeConverter implements JsonConverter<MediaType, String> {
  const MediaTypeConverter();

  @override
  MediaType fromJson(String json) => _mediaTypeFromValue(json);

  @override
  String toJson(MediaType object) => object.value;
}

MediaType _mediaTypeFromValue(String value) {
  switch (value) {
    case 'video':
      return MediaType.video;
    case 'audio':
      return MediaType.audio;
    default:
      return MediaType.video;
  }
}

enum MediaType {
  video('video'),
  audio('audio');

  const MediaType(this.value);
  final String value;
}

@freezed
class Media with _$Media {
  const factory Media({
    required int id,
    required String title,
    @MediaTypeConverter() required MediaType type,
    @JsonKey(name: 'file_size') required int fileSize,
    @JsonKey(name: 'filename') @Default('') String filename,
    int? year,
    @JsonKey(name: 'file_path') @Default('') String filePath,
    String? description,
    int? duration,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @Default(<Artist>[]) List<Artist> artists,
    String? album,
    String? genre,
    Metadata? metadata,
    @JsonKey(name: 'file_hash') @Default('') String fileHash,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
}
