import 'package:freezed_annotation/freezed_annotation.dart';

// ignore_for_file: invalid_annotation_target

part 'library.freezed.dart';
part 'library.g.dart';

@freezed
class MediaLibrary with _$MediaLibrary {
  const factory MediaLibrary({
    required int id,
    required String name,
    @Default('') String path,
    required String type,
    required bool enabled,
    @JsonKey(name: 'scan_interval') int? scanInterval,
  }) = _MediaLibrary;

  factory MediaLibrary.fromJson(Map<String, dynamic> json) => _$MediaLibraryFromJson(json);
}
