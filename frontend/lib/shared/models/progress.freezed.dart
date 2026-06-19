// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WatchProgress _$WatchProgressFromJson(Map<String, dynamic> json) {
  return _WatchProgress.fromJson(json);
}

/// @nodoc
mixin _$WatchProgress {
  int get id => throw _privateConstructorUsedError;
  int get userId => throw _privateConstructorUsedError;
  int get mediaId => throw _privateConstructorUsedError;
  int get position => throw _privateConstructorUsedError;
  int get duration => throw _privateConstructorUsedError;
  bool get completed => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WatchProgressCopyWith<WatchProgress> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WatchProgressCopyWith<$Res> {
  factory $WatchProgressCopyWith(
          WatchProgress value, $Res Function(WatchProgress) then) =
      _$WatchProgressCopyWithImpl<$Res, WatchProgress>;
  @useResult
  $Res call(
      {int id,
      int userId,
      int mediaId,
      int position,
      int duration,
      bool completed});
}

/// @nodoc
class _$WatchProgressCopyWithImpl<$Res, $Val extends WatchProgress>
    implements $WatchProgressCopyWith<$Res> {
  _$WatchProgressCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? mediaId = null,
    Object? position = null,
    Object? duration = null,
    Object? completed = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as int,
      mediaId: null == mediaId
          ? _value.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as int,
      position: null == position
          ? _value.position
          : position // ignore: cast_nullable_to_non_nullable
              as int,
      duration: null == duration
          ? _value.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as int,
      completed: null == completed
          ? _value.completed
          : completed // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WatchProgressImplCopyWith<$Res>
    implements $WatchProgressCopyWith<$Res> {
  factory _$$WatchProgressImplCopyWith(
          _$WatchProgressImpl value, $Res Function(_$WatchProgressImpl) then) =
      __$$WatchProgressImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int id,
      int userId,
      int mediaId,
      int position,
      int duration,
      bool completed});
}

/// @nodoc
class __$$WatchProgressImplCopyWithImpl<$Res>
    extends _$WatchProgressCopyWithImpl<$Res, _$WatchProgressImpl>
    implements _$$WatchProgressImplCopyWith<$Res> {
  __$$WatchProgressImplCopyWithImpl(
      _$WatchProgressImpl _value, $Res Function(_$WatchProgressImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? mediaId = null,
    Object? position = null,
    Object? duration = null,
    Object? completed = null,
  }) {
    return _then(_$WatchProgressImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as int,
      mediaId: null == mediaId
          ? _value.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as int,
      position: null == position
          ? _value.position
          : position // ignore: cast_nullable_to_non_nullable
              as int,
      duration: null == duration
          ? _value.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as int,
      completed: null == completed
          ? _value.completed
          : completed // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WatchProgressImpl implements _WatchProgress {
  const _$WatchProgressImpl(
      {required this.id,
      required this.userId,
      required this.mediaId,
      required this.position,
      required this.duration,
      required this.completed});

  factory _$WatchProgressImpl.fromJson(Map<String, dynamic> json) =>
      _$$WatchProgressImplFromJson(json);

  @override
  final int id;
  @override
  final int userId;
  @override
  final int mediaId;
  @override
  final int position;
  @override
  final int duration;
  @override
  final bool completed;

  @override
  String toString() {
    return 'WatchProgress(id: $id, userId: $userId, mediaId: $mediaId, position: $position, duration: $duration, completed: $completed)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WatchProgressImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.mediaId, mediaId) || other.mediaId == mediaId) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            (identical(other.completed, completed) ||
                other.completed == completed));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, userId, mediaId, position, duration, completed);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WatchProgressImplCopyWith<_$WatchProgressImpl> get copyWith =>
      __$$WatchProgressImplCopyWithImpl<_$WatchProgressImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WatchProgressImplToJson(
      this,
    );
  }
}

abstract class _WatchProgress implements WatchProgress {
  const factory _WatchProgress(
      {required final int id,
      required final int userId,
      required final int mediaId,
      required final int position,
      required final int duration,
      required final bool completed}) = _$WatchProgressImpl;

  factory _WatchProgress.fromJson(Map<String, dynamic> json) =
      _$WatchProgressImpl.fromJson;

  @override
  int get id;
  @override
  int get userId;
  @override
  int get mediaId;
  @override
  int get position;
  @override
  int get duration;
  @override
  bool get completed;
  @override
  @JsonKey(ignore: true)
  _$$WatchProgressImplCopyWith<_$WatchProgressImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
