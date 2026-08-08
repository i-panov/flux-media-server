import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'favorite.freezed.dart';
part 'favorite.g.dart';

@freezed
class Favorite with _$Favorite {
  const factory Favorite({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    @JsonKey(name: 'media_id') int? mediaId,
    @JsonKey(name: 'artist_name') String? artistName,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Favorite;

  factory Favorite.fromJson(Map<String, dynamic> json) =>
      _$FavoriteFromJson(json);
}
