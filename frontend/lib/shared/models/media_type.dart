import 'package:freezed_annotation/freezed_annotation.dart';

/// Media type as serialized in the backend API.
enum MediaType {
  video('video'),
  audio('audio'),
  unknown('');

  const MediaType(this.value);
  final String value;
}

/// Custom converter for [MediaType] to/from JSON.
///
/// Uses [Object?] so a missing or null `type` key is tolerated and
/// mapped to [MediaType.unknown] instead of throwing a TypeError.
class MediaTypeConverter implements JsonConverter<MediaType, Object?> {
  const MediaTypeConverter();

  @override
  MediaType fromJson(Object? json) => _mediaTypeFromValue(json);

  @override
  Object? toJson(MediaType object) => object.value;
}

MediaType _mediaTypeFromValue(Object? value) {
  if (value is! String) return MediaType.unknown;
  switch (value.trim().toLowerCase()) {
    case 'video':
      return MediaType.video;
    case 'audio':
      return MediaType.audio;
    default:
      // Не маскируем нераспознанные значения под video.
      return MediaType.unknown;
  }
}
