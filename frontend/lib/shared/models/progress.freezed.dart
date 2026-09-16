// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WatchProgress {

@JsonKey(name: 'user_id') int get userId;@JsonKey(name: 'media_id') int get mediaId; int get position; int get duration; bool get completed;@JsonKey(name: 'updated_at') DateTime? get updatedAt; int? get id;
/// Create a copy of WatchProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WatchProgressCopyWith<WatchProgress> get copyWith => _$WatchProgressCopyWithImpl<WatchProgress>(this as WatchProgress, _$identity);

  /// Serializes this WatchProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as WatchProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WatchProgress&&(identical(other.userId, _this.userId) || other.userId == _this.userId)&&(identical(other.mediaId, _this.mediaId) || other.mediaId == _this.mediaId)&&(identical(other.position, _this.position) || other.position == _this.position)&&(identical(other.duration, _this.duration) || other.duration == _this.duration)&&(identical(other.completed, _this.completed) || other.completed == _this.completed)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.id, _this.id) || other.id == _this.id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as WatchProgress;
  return Object.hash(runtimeType,_this.userId,_this.mediaId,_this.position,_this.duration,_this.completed,_this.updatedAt,_this.id);
}

@override
String toString() {
  final _this = this as WatchProgress;
  return 'WatchProgress(userId: ${_this.userId}, mediaId: ${_this.mediaId}, position: ${_this.position}, duration: ${_this.duration}, completed: ${_this.completed}, updatedAt: ${_this.updatedAt}, id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $WatchProgressCopyWith<$Res>  {
  factory $WatchProgressCopyWith(WatchProgress value, $Res Function(WatchProgress) _then) = _$WatchProgressCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'user_id') int userId,@JsonKey(name: 'media_id') int mediaId, int position, int duration, bool completed,@JsonKey(name: 'updated_at') DateTime? updatedAt, int? id
});




}
/// @nodoc
class _$WatchProgressCopyWithImpl<$Res>
    implements $WatchProgressCopyWith<$Res> {
  _$WatchProgressCopyWithImpl(this._self, this._then);

  final WatchProgress _self;
  final $Res Function(WatchProgress) _then;

/// Create a copy of WatchProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? mediaId = null,Object? position = null,Object? duration = null,Object? completed = null,Object? updatedAt = freezed,Object? id = freezed,}) {
  return _then(WatchProgress(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,mediaId: null == mediaId ? _self.mediaId : mediaId // ignore: cast_nullable_to_non_nullable
as int,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as bool,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [WatchProgress].
extension WatchProgressPatterns on WatchProgress {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WatchProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WatchProgress() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WatchProgress value)  $default,){
final _that = this;
switch (_that) {
case _WatchProgress():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WatchProgress value)?  $default,){
final _that = this;
switch (_that) {
case _WatchProgress() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'user_id')  int userId, @JsonKey(name: 'media_id')  int mediaId,  int position,  int duration,  bool completed, @JsonKey(name: 'updated_at')  DateTime? updatedAt,  int? id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WatchProgress() when $default != null:
return $default(_that.userId,_that.mediaId,_that.position,_that.duration,_that.completed,_that.updatedAt,_that.id);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'user_id')  int userId, @JsonKey(name: 'media_id')  int mediaId,  int position,  int duration,  bool completed, @JsonKey(name: 'updated_at')  DateTime? updatedAt,  int? id)  $default,) {final _that = this;
switch (_that) {
case _WatchProgress():
return $default(_that.userId,_that.mediaId,_that.position,_that.duration,_that.completed,_that.updatedAt,_that.id);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'user_id')  int userId, @JsonKey(name: 'media_id')  int mediaId,  int position,  int duration,  bool completed, @JsonKey(name: 'updated_at')  DateTime? updatedAt,  int? id)?  $default,) {final _that = this;
switch (_that) {
case _WatchProgress() when $default != null:
return $default(_that.userId,_that.mediaId,_that.position,_that.duration,_that.completed,_that.updatedAt,_that.id);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WatchProgress implements WatchProgress {
  const _WatchProgress({@JsonKey(name: 'user_id') required this.userId, @JsonKey(name: 'media_id') required this.mediaId, required this.position, this.duration = 0, this.completed = false, @JsonKey(name: 'updated_at') this.updatedAt, this.id});
  factory _WatchProgress.fromJson(Map<String, dynamic> json) => _$WatchProgressFromJson(json);

@override@JsonKey(name: 'user_id') final  int userId;
@override@JsonKey(name: 'media_id') final  int mediaId;
@override final  int position;
@override@JsonKey() final  int duration;
@override@JsonKey() final  bool completed;
@override@JsonKey(name: 'updated_at') final  DateTime? updatedAt;
@override final  int? id;

/// Create a copy of WatchProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WatchProgressCopyWith<_WatchProgress> get copyWith => __$WatchProgressCopyWithImpl<_WatchProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WatchProgressToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WatchProgress&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.mediaId, mediaId) || other.mediaId == mediaId)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.completed, completed) || other.completed == completed)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.id, id) || other.id == id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,userId,mediaId,position,duration,completed,updatedAt,id);
}

@override
String toString() {
    return 'WatchProgress(userId: $userId, mediaId: $mediaId, position: $position, duration: $duration, completed: $completed, updatedAt: $updatedAt, id: $id)';
}


}

/// @nodoc
abstract mixin class _$WatchProgressCopyWith<$Res> implements $WatchProgressCopyWith<$Res> {
  factory _$WatchProgressCopyWith(_WatchProgress value, $Res Function(_WatchProgress) _then) = __$WatchProgressCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'user_id') int userId,@JsonKey(name: 'media_id') int mediaId, int position, int duration, bool completed,@JsonKey(name: 'updated_at') DateTime? updatedAt, int? id
});




}
/// @nodoc
class __$WatchProgressCopyWithImpl<$Res>
    implements _$WatchProgressCopyWith<$Res> {
  __$WatchProgressCopyWithImpl(this._self, this._then);

  final _WatchProgress _self;
  final $Res Function(_WatchProgress) _then;

/// Create a copy of WatchProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? mediaId = null,Object? position = null,Object? duration = null,Object? completed = null,Object? updatedAt = freezed,Object? id = freezed,}) {
  return _then(_WatchProgress(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,mediaId: null == mediaId ? _self.mediaId : mediaId // ignore: cast_nullable_to_non_nullable
as int,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as bool,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
