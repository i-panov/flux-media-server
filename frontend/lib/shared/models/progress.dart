import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress.freezed.dart';
part 'progress.g.dart';

@freezed
class WatchProgress with _$WatchProgress {
  const factory WatchProgress({
    required int id,
    required int userId,
    required int mediaId,
    required int position,
    required int duration,
    required bool completed,
  }) = _WatchProgress;

  factory WatchProgress.fromJson(Map<String, dynamic> json) => _$WatchProgressFromJson(json);
}
