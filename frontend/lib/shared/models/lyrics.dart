import 'package:freezed_annotation/freezed_annotation.dart';

part 'lyrics.freezed.dart';
part 'lyrics.g.dart';

@freezed
sealed class Lyrics with _$Lyrics {
  const factory({
    required int id,
    @JsonKey(name: 'media_id') required int mediaId,
    required String source,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'lyrics_text') @Default('') String lyricsText,
    @JsonKey(name: 'translation') @Default('') String translation,
    @JsonKey(name: 'sync_data') @Default('') String syncData,
  }) = _Lyrics;

  factory fromJson(Map<String, dynamic> json) => _$LyricsFromJson(json);
}
