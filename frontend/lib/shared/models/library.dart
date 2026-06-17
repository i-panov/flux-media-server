import 'package:freezed_annotation/freezed_annotation.dart';

part 'library.freezed.dart';
part 'library.g.dart';

@freezed
class MediaLibrary with _$MediaLibrary {
  const factory MediaLibrary({
    required int id,
    required String name,
    required String path,
    required String type,
    required bool enabled,
    int? scanInterval,
  }) = _MediaLibrary;

  factory MediaLibrary.fromJson(Map<String, dynamic> json) => _$MediaLibraryFromJson(json);
}
