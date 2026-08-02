import 'package:flux_media_server/shared/models/metadata.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'media.freezed.dart';
part 'media.g.dart';

@freezed
class Media with _$Media {
  const factory Media({
    required int id,
    required String title,
    @JsonKey(name: 'filename') @Default('') String filename,
    int? year,
    required String type,
    @JsonKey(name: 'file_path') @Default('') String filePath,
    @JsonKey(name: 'file_size') required int fileSize,
    String? description,
    int? duration,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'cover_url') String? coverUrl,
    String? artist,
    String? album,
    String? genre,
    Metadata? metadata,
    @JsonKey(name: 'file_hash') @Default('') String fileHash,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
}
