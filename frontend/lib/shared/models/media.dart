import 'package:flux_media_server/shared/models/artist.dart';
import 'package:flux_media_server/shared/models/media_type.dart';
import 'package:flux_media_server/shared/models/metadata.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

export 'media_type.dart';

part 'media.freezed.dart';
part 'media.g.dart';

@freezed
class Media with _$Media {
  const factory Media({
    required int id,
    required String title,
    @MediaTypeConverter() required MediaType type,
    @JsonKey(name: 'file_size') required int fileSize,
    @JsonKey(name: 'filename') @Default('') String filename,
    int? year,
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
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
}
