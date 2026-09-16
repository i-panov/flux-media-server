import 'package:freezed_annotation/freezed_annotation.dart';

part 'artist.freezed.dart';
part 'artist.g.dart';

@freezed
sealed class Artist with _$Artist {
  const factory({
    required int id,
    required String name,
    @Default(0) int position,
    @JsonKey(name: 'has_cover') @Default(false) bool hasCover,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Artist;

  factory fromJson(Map<String, dynamic> json) => _$ArtistFromJson(json);
}
