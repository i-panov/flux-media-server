import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'metadata.freezed.dart';
part 'metadata.g.dart';

List<String>? _stringListFromJson(Object? json) {
  if (json == null) return null;
  try {
    if (json is List) return List<String>.from(json);
    if (json is String && json.isNotEmpty) {
      final decoded = jsonDecode(json);
      if (decoded is List) return List<String>.from(decoded);
    }
  } catch (_) {
    // Кривой элемент не должен ронять парсинг всего списка медиа.
    return const <String>[];
  }
  return null;
}

String? _stringListToJson(List<String>? value) =>
    value == null ? null : jsonEncode(value);

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
    @JsonKey(
      name: 'genres',
      fromJson: _stringListFromJson,
      toJson: _stringListToJson,
    )
    List<String>? genres,
    @JsonKey(
      name: 'cast',
      fromJson: _stringListFromJson,
      toJson: _stringListToJson,
    )
    List<String>? cast,
  }) = _Metadata;

  factory Metadata.fromJson(Map<String, dynamic> json) =>
      _$MetadataFromJson(json);
}
