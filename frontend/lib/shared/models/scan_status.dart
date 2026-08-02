import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'scan_status.freezed.dart';
part 'scan_status.g.dart';

@freezed
class ScanStatus with _$ScanStatus {
  const factory ScanStatus({
    @JsonKey(name: 'library_id') required int libraryId,
    required bool running,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'last_error') String? lastError,
  }) = _ScanStatus;

  factory ScanStatus.fromJson(Map<String, dynamic> json) =>
      _$ScanStatusFromJson(json);
}
