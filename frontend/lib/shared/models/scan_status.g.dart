// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ScanStatusImpl _$$ScanStatusImplFromJson(Map<String, dynamic> json) =>
    _$ScanStatusImpl(
      libraryId: (json['library_id'] as num).toInt(),
      running: json['running'] as bool,
      startedAt: json['started_at'] as String?,
      lastError: json['last_error'] as String?,
    );

Map<String, dynamic> _$$ScanStatusImplToJson(_$ScanStatusImpl instance) =>
    <String, dynamic>{
      'library_id': instance.libraryId,
      'running': instance.running,
      'started_at': instance.startedAt,
      'last_error': instance.lastError,
    };
