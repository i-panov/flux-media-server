import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'metadata.freezed.dart';
part 'metadata.g.dart';

List<String>? _stringListFromJson(Object? json) {
  if (json == null) return null;
  if (json is List) return json.cast<String>();
  if (json is String && json.isNotEmpty) {
    final decoded = jsonDecode(json);
    if (decoded is List) return decoded.cast<String>();
  }
  return null;
}

// ignore_for_file: invalid_annotation_target

@freezed
class Metadata with _$Metadata {
  const factory Metadata({
    required int id,
    @JsonKey(name: 'external_id') String? externalId,
    String? source,
    String? title,
    int? year,
    String? description,
    @JsonKey(name: 'poster_url') String? posterUrl,
    @JsonKey(name: 'backdrop_url') String? backdropUrl,
    double? rating,
    @JsonKey(name: 'genres', fromJson: _stringListFromJson) List<String>? genres,
    @JsonKey(name: 'cast', fromJson: _stringListFromJson) List<String>? cast,
  }) = _Metadata;

  factory Metadata.fromJson(Map<String, dynamic> json) => _$MetadataFromJson(json);
}
