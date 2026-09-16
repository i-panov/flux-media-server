import 'package:freezed_annotation/freezed_annotation.dart';

part 'favorite.freezed.dart';
part 'favorite.g.dart';

@freezed
sealed class Favorite with _$Favorite {
  const factory({
    required int id,
    @JsonKey(name: 'user_id') required int userId,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'media_id') int? mediaId,
    @JsonKey(name: 'artist_id') int? artistId,
  }) = _Favorite;

  factory fromJson(Map<String, dynamic> json) => _$FavoriteFromJson(json);
}
