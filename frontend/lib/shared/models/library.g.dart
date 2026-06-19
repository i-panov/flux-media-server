// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MediaLibraryImpl _$$MediaLibraryImplFromJson(Map<String, dynamic> json) =>
    _$MediaLibraryImpl(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      enabled: json['enabled'] as bool,
      scanInterval: (json['scanInterval'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$MediaLibraryImplToJson(_$MediaLibraryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'path': instance.path,
      'type': instance.type,
      'enabled': instance.enabled,
      'scanInterval': instance.scanInterval,
    };
