import 'package:freezed_annotation/freezed_annotation.dart';

part 'metadata.freezed.dart';
part 'metadata.g.dart';

@freezed
class Metadata with _$Metadata {
  const factory Metadata({
    required int id,
    String? externalId,
    String? source,
    String? title,
    int? year,
    String? description,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    List<String>? genres,
    List<String>? cast,
  }) = _Metadata;

  factory Metadata.fromJson(Map<String, dynamic> json) => _$MetadataFromJson(json);
}
