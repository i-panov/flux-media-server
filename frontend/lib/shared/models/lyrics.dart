import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'lyrics.freezed.dart';
part 'lyrics.g.dart';

@freezed
class Lyrics with _$Lyrics {
  const factory Lyrics({
    required int id,
    @JsonKey(name: 'media_id') required int mediaId,
    @JsonKey(name: 'lyrics_text') @Default('') String lyricsText,
    @JsonKey(name: 'translation') @Default('') String translation,
    @JsonKey(name: 'sync_data') @Default('') String syncData,
    required String source,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Lyrics;

  factory Lyrics.fromJson(Map<String, dynamic> json) =>
      _$LyricsFromJson(json);
}
