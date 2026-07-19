// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scan_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ScanStatus _$ScanStatusFromJson(Map<String, dynamic> json) {
  return _ScanStatus.fromJson(json);
}

/// @nodoc
mixin _$ScanStatus {
  @JsonKey(name: 'library_id')
  int get libraryId => throw _privateConstructorUsedError;
  bool get running => throw _privateConstructorUsedError;
  @JsonKey(name: 'started_at')
  String? get startedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_error')
  String? get lastError => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ScanStatusCopyWith<ScanStatus> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ScanStatusCopyWith<$Res> {
  factory $ScanStatusCopyWith(
          ScanStatus value, $Res Function(ScanStatus) then) =
      _$ScanStatusCopyWithImpl<$Res, ScanStatus>;
  @useResult
  $Res call(
      {@JsonKey(name: 'library_id') int libraryId,
      bool running,
      @JsonKey(name: 'started_at') String? startedAt,
      @JsonKey(name: 'last_error') String? lastError});
}

/// @nodoc
class _$ScanStatusCopyWithImpl<$Res, $Val extends ScanStatus>
    implements $ScanStatusCopyWith<$Res> {
  _$ScanStatusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? libraryId = null,
    Object? running = null,
    Object? startedAt = freezed,
    Object? lastError = freezed,
  }) {
    return _then(_value.copyWith(
      libraryId: null == libraryId
          ? _value.libraryId
          : libraryId // ignore: cast_nullable_to_non_nullable
              as int,
      running: null == running
          ? _value.running
          : running // ignore: cast_nullable_to_non_nullable
              as bool,
      startedAt: freezed == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as String?,
      lastError: freezed == lastError
          ? _value.lastError
          : lastError // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ScanStatusImplCopyWith<$Res>
    implements $ScanStatusCopyWith<$Res> {
  factory _$$ScanStatusImplCopyWith(
          _$ScanStatusImpl value, $Res Function(_$ScanStatusImpl) then) =
      __$$ScanStatusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'library_id') int libraryId,
      bool running,
      @JsonKey(name: 'started_at') String? startedAt,
      @JsonKey(name: 'last_error') String? lastError});
}

/// @nodoc
class __$$ScanStatusImplCopyWithImpl<$Res>
    extends _$ScanStatusCopyWithImpl<$Res, _$ScanStatusImpl>
    implements _$$ScanStatusImplCopyWith<$Res> {
  __$$ScanStatusImplCopyWithImpl(
      _$ScanStatusImpl _value, $Res Function(_$ScanStatusImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? libraryId = null,
    Object? running = null,
    Object? startedAt = freezed,
    Object? lastError = freezed,
  }) {
    return _then(_$ScanStatusImpl(
      libraryId: null == libraryId
          ? _value.libraryId
          : libraryId // ignore: cast_nullable_to_non_nullable
              as int,
      running: null == running
          ? _value.running
          : running // ignore: cast_nullable_to_non_nullable
              as bool,
      startedAt: freezed == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as String?,
      lastError: freezed == lastError
          ? _value.lastError
          : lastError // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ScanStatusImpl implements _ScanStatus {
  const _$ScanStatusImpl(
      {@JsonKey(name: 'library_id') required this.libraryId,
      required this.running,
      @JsonKey(name: 'started_at') this.startedAt,
      @JsonKey(name: 'last_error') this.lastError});

  factory _$ScanStatusImpl.fromJson(Map<String, dynamic> json) =>
      _$$ScanStatusImplFromJson(json);

  @override
  @JsonKey(name: 'library_id')
  final int libraryId;
  @override
  final bool running;
  @override
  @JsonKey(name: 'started_at')
  final String? startedAt;
  @override
  @JsonKey(name: 'last_error')
  final String? lastError;

  @override
  String toString() {
    return 'ScanStatus(libraryId: $libraryId, running: $running, startedAt: $startedAt, lastError: $lastError)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ScanStatusImpl &&
            (identical(other.libraryId, libraryId) ||
                other.libraryId == libraryId) &&
            (identical(other.running, running) || other.running == running) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.lastError, lastError) ||
                other.lastError == lastError));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, libraryId, running, startedAt, lastError);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ScanStatusImplCopyWith<_$ScanStatusImpl> get copyWith =>
      __$$ScanStatusImplCopyWithImpl<_$ScanStatusImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ScanStatusImplToJson(
      this,
    );
  }
}

abstract class _ScanStatus implements ScanStatus {
  const factory _ScanStatus(
      {@JsonKey(name: 'library_id') required final int libraryId,
      required final bool running,
      @JsonKey(name: 'started_at') final String? startedAt,
      @JsonKey(name: 'last_error') final String? lastError}) = _$ScanStatusImpl;

  factory _ScanStatus.fromJson(Map<String, dynamic> json) =
      _$ScanStatusImpl.fromJson;

  @override
  @JsonKey(name: 'library_id')
  int get libraryId;
  @override
  bool get running;
  @override
  @JsonKey(name: 'started_at')
  String? get startedAt;
  @override
  @JsonKey(name: 'last_error')
  String? get lastError;
  @override
  @JsonKey(ignore: true)
  _$$ScanStatusImplCopyWith<_$ScanStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
