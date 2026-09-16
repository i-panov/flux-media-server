import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress.freezed.dart';
part 'progress.g.dart';

@freezed
sealed class WatchProgress with _$WatchProgress {
  const factory({
    @JsonKey(name: 'user_id') required int userId,
    @JsonKey(name: 'media_id') required int mediaId,
    required int position,
    @Default(0) int duration,
    @Default(false) bool completed,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    int? id,
  }) = _WatchProgress;

  factory fromJson(Map<String, dynamic> json) => _$WatchProgressFromJson(json);
}
