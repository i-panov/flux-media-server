import 'package:freezed_annotation/freezed_annotation.dart';

import 'metadata.dart';

part 'media.freezed.dart';
part 'media.g.dart';

@freezed
class Media with _$Media {
  const factory Media({
    required int id,
    required String title,
    required int year,
    required String type,
    required String filePath,
    required int fileSize,
    String? description,
    int? duration,
    String? thumbnailUrl,
    Metadata? metadata,
    @Default('') String fileHash,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
}
