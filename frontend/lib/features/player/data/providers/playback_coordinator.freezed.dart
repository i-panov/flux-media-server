// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playback_coordinator.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlaybackState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlaybackState()';
}


}

/// @nodoc
class $PlaybackStateCopyWith<$Res>  {
$PlaybackStateCopyWith(PlaybackState _, $Res Function(PlaybackState) __);
}


/// Adds pattern-matching-related methods to [PlaybackState].
extension PlaybackStatePatterns on PlaybackState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlaybackInitial value)?  initial,TResult Function( PlaybackPlaying value)?  playing,TResult Function( PlaybackCompleted value)?  completed,TResult Function( PlaybackLoading value)?  loading,TResult Function( PlaybackError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlaybackInitial() when initial != null:
return initial(_that);case PlaybackPlaying() when playing != null:
return playing(_that);case PlaybackCompleted() when completed != null:
return completed(_that);case PlaybackLoading() when loading != null:
return loading(_that);case PlaybackError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlaybackInitial value)  initial,required TResult Function( PlaybackPlaying value)  playing,required TResult Function( PlaybackCompleted value)  completed,required TResult Function( PlaybackLoading value)  loading,required TResult Function( PlaybackError value)  error,}){
final _that = this;
switch (_that) {
case PlaybackInitial():
return initial(_that);case PlaybackPlaying():
return playing(_that);case PlaybackCompleted():
return completed(_that);case PlaybackLoading():
return loading(_that);case PlaybackError():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlaybackInitial value)?  initial,TResult? Function( PlaybackPlaying value)?  playing,TResult? Function( PlaybackCompleted value)?  completed,TResult? Function( PlaybackLoading value)?  loading,TResult? Function( PlaybackError value)?  error,}){
final _that = this;
switch (_that) {
case PlaybackInitial() when initial != null:
return initial(_that);case PlaybackPlaying() when playing != null:
return playing(_that);case PlaybackCompleted() when completed != null:
return completed(_that);case PlaybackLoading() when loading != null:
return loading(_that);case PlaybackError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function( Media media,  MediaType type,  bool isPaused,  Duration position,  Duration? duration,  double speed,  Duration? savedPosition)?  playing,TResult Function()?  completed,TResult Function()?  loading,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlaybackInitial() when initial != null:
return initial();case PlaybackPlaying() when playing != null:
return playing(_that.media,_that.type,_that.isPaused,_that.position,_that.duration,_that.speed,_that.savedPosition);case PlaybackCompleted() when completed != null:
return completed();case PlaybackLoading() when loading != null:
return loading();case PlaybackError() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function( Media media,  MediaType type,  bool isPaused,  Duration position,  Duration? duration,  double speed,  Duration? savedPosition)  playing,required TResult Function()  completed,required TResult Function()  loading,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case PlaybackInitial():
return initial();case PlaybackPlaying():
return playing(_that.media,_that.type,_that.isPaused,_that.position,_that.duration,_that.speed,_that.savedPosition);case PlaybackCompleted():
return completed();case PlaybackLoading():
return loading();case PlaybackError():
return error(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function( Media media,  MediaType type,  bool isPaused,  Duration position,  Duration? duration,  double speed,  Duration? savedPosition)?  playing,TResult? Function()?  completed,TResult? Function()?  loading,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case PlaybackInitial() when initial != null:
return initial();case PlaybackPlaying() when playing != null:
return playing(_that.media,_that.type,_that.isPaused,_that.position,_that.duration,_that.speed,_that.savedPosition);case PlaybackCompleted() when completed != null:
return completed();case PlaybackLoading() when loading != null:
return loading();case PlaybackError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class PlaybackInitial implements PlaybackState {
  const PlaybackInitial();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackInitial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlaybackState.initial()';
}


}




/// @nodoc


class PlaybackPlaying implements PlaybackState {
  const PlaybackPlaying({required this.media, required this.type, this.isPaused = false, this.position = Duration.zero, this.duration, this.speed = 1.0, this.savedPosition});
  

 final  Media media;
 final  MediaType type;
@JsonKey() final  bool isPaused;
@JsonKey() final  Duration position;
 final  Duration? duration;
@JsonKey() final  double speed;
 final  Duration? savedPosition;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackPlayingCopyWith<PlaybackPlaying> get copyWith => _$PlaybackPlayingCopyWithImpl<PlaybackPlaying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackPlaying&&(identical(other.media, media) || other.media == media)&&(identical(other.type, type) || other.type == type)&&(identical(other.isPaused, isPaused) || other.isPaused == isPaused)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.speed, speed) || other.speed == speed)&&(identical(other.savedPosition, savedPosition) || other.savedPosition == savedPosition));
}


@override
int get hashCode {
    return Object.hash(runtimeType,media,type,isPaused,position,duration,speed,savedPosition);
}

@override
String toString() {
    return 'PlaybackState.playing(media: $media, type: $type, isPaused: $isPaused, position: $position, duration: $duration, speed: $speed, savedPosition: $savedPosition)';
}


}

/// @nodoc
abstract mixin class $PlaybackPlayingCopyWith<$Res> implements $PlaybackStateCopyWith<$Res> {
  factory $PlaybackPlayingCopyWith(PlaybackPlaying value, $Res Function(PlaybackPlaying) _then) = _$PlaybackPlayingCopyWithImpl;
@useResult
$Res call({
 Media media, MediaType type, bool isPaused, Duration position, Duration? duration, double speed, Duration? savedPosition
});


$MediaCopyWith<$Res> get media;

}
/// @nodoc
class _$PlaybackPlayingCopyWithImpl<$Res>
    implements $PlaybackPlayingCopyWith<$Res> {
  _$PlaybackPlayingCopyWithImpl(this._self, this._then);

  final PlaybackPlaying _self;
  final $Res Function(PlaybackPlaying) _then;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? media = null,Object? type = null,Object? isPaused = null,Object? position = null,Object? duration = freezed,Object? speed = null,Object? savedPosition = freezed,}) {
  return _then(PlaybackPlaying(
media: null == media ? _self.media : media // ignore: cast_nullable_to_non_nullable
as Media,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,isPaused: null == isPaused ? _self.isPaused : isPaused // ignore: cast_nullable_to_non_nullable
as bool,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,savedPosition: freezed == savedPosition ? _self.savedPosition : savedPosition // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MediaCopyWith<$Res> get media {
  
  return $MediaCopyWith<$Res>(_self.media, (value) {
    return _then(_self.copyWith(media: value));
  });
}
}

/// @nodoc


class PlaybackCompleted implements PlaybackState {
  const PlaybackCompleted();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackCompleted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlaybackState.completed()';
}


}




/// @nodoc


class PlaybackLoading implements PlaybackState {
  const PlaybackLoading();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlaybackState.loading()';
}


}




/// @nodoc


class PlaybackError implements PlaybackState {
  const PlaybackError({required this.message});
  

 final  String message;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackErrorCopyWith<PlaybackError> get copyWith => _$PlaybackErrorCopyWithImpl<PlaybackError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'PlaybackState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $PlaybackErrorCopyWith<$Res> implements $PlaybackStateCopyWith<$Res> {
  factory $PlaybackErrorCopyWith(PlaybackError value, $Res Function(PlaybackError) _then) = _$PlaybackErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$PlaybackErrorCopyWithImpl<$Res>
    implements $PlaybackErrorCopyWith<$Res> {
  _$PlaybackErrorCopyWithImpl(this._self, this._then);

  final PlaybackError _self;
  final $Res Function(PlaybackError) _then;

/// Create a copy of PlaybackState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(PlaybackError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
