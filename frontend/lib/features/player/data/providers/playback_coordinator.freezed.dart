// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playback_coordinator.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PlaybackState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)
        playing,
    required TResult Function() completed,
    required TResult Function() loading,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)?
        playing,
    TResult? Function()? completed,
    TResult? Function()? loading,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(Media media, String type, bool isPaused, Duration position,
            Duration? duration, double speed, Duration? savedPosition)?
        playing,
    TResult Function()? completed,
    TResult Function()? loading,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaybackInitial value) initial,
    required TResult Function(PlaybackPlaying value) playing,
    required TResult Function(PlaybackCompleted value) completed,
    required TResult Function(PlaybackLoading value) loading,
    required TResult Function(PlaybackError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaybackInitial value)? initial,
    TResult? Function(PlaybackPlaying value)? playing,
    TResult? Function(PlaybackCompleted value)? completed,
    TResult? Function(PlaybackLoading value)? loading,
    TResult? Function(PlaybackError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaybackInitial value)? initial,
    TResult Function(PlaybackPlaying value)? playing,
    TResult Function(PlaybackCompleted value)? completed,
    TResult Function(PlaybackLoading value)? loading,
    TResult Function(PlaybackError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlaybackStateCopyWith<$Res> {
  factory $PlaybackStateCopyWith(
          PlaybackState value, $Res Function(PlaybackState) then) =
      _$PlaybackStateCopyWithImpl<$Res, PlaybackState>;
}

/// @nodoc
class _$PlaybackStateCopyWithImpl<$Res, $Val extends PlaybackState>
    implements $PlaybackStateCopyWith<$Res> {
  _$PlaybackStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$PlaybackInitialImplCopyWith<$Res> {
  factory _$$PlaybackInitialImplCopyWith(_$PlaybackInitialImpl value,
          $Res Function(_$PlaybackInitialImpl) then) =
      __$$PlaybackInitialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlaybackInitialImplCopyWithImpl<$Res>
    extends _$PlaybackStateCopyWithImpl<$Res, _$PlaybackInitialImpl>
    implements _$$PlaybackInitialImplCopyWith<$Res> {
  __$$PlaybackInitialImplCopyWithImpl(
      _$PlaybackInitialImpl _value, $Res Function(_$PlaybackInitialImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlaybackInitialImpl implements PlaybackInitial {
  const _$PlaybackInitialImpl();

  @override
  String toString() {
    return 'PlaybackState.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$PlaybackInitialImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)
        playing,
    required TResult Function() completed,
    required TResult Function() loading,
    required TResult Function(String message) error,
  }) {
    return initial();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)?
        playing,
    TResult? Function()? completed,
    TResult? Function()? loading,
    TResult? Function(String message)? error,
  }) {
    return initial?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(Media media, String type, bool isPaused, Duration position,
            Duration? duration, double speed, Duration? savedPosition)?
        playing,
    TResult Function()? completed,
    TResult Function()? loading,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaybackInitial value) initial,
    required TResult Function(PlaybackPlaying value) playing,
    required TResult Function(PlaybackCompleted value) completed,
    required TResult Function(PlaybackLoading value) loading,
    required TResult Function(PlaybackError value) error,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaybackInitial value)? initial,
    TResult? Function(PlaybackPlaying value)? playing,
    TResult? Function(PlaybackCompleted value)? completed,
    TResult? Function(PlaybackLoading value)? loading,
    TResult? Function(PlaybackError value)? error,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaybackInitial value)? initial,
    TResult Function(PlaybackPlaying value)? playing,
    TResult Function(PlaybackCompleted value)? completed,
    TResult Function(PlaybackLoading value)? loading,
    TResult Function(PlaybackError value)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class PlaybackInitial implements PlaybackState {
  const factory PlaybackInitial() = _$PlaybackInitialImpl;
}

/// @nodoc
abstract class _$$PlaybackPlayingImplCopyWith<$Res> {
  factory _$$PlaybackPlayingImplCopyWith(_$PlaybackPlayingImpl value,
          $Res Function(_$PlaybackPlayingImpl) then) =
      __$$PlaybackPlayingImplCopyWithImpl<$Res>;
  @useResult
  $Res call(
      {Media media,
      String type,
      bool isPaused,
      Duration position,
      Duration? duration,
      double speed,
      Duration? savedPosition});

  $MediaCopyWith<$Res> get media;
}

/// @nodoc
class __$$PlaybackPlayingImplCopyWithImpl<$Res>
    extends _$PlaybackStateCopyWithImpl<$Res, _$PlaybackPlayingImpl>
    implements _$$PlaybackPlayingImplCopyWith<$Res> {
  __$$PlaybackPlayingImplCopyWithImpl(
      _$PlaybackPlayingImpl _value, $Res Function(_$PlaybackPlayingImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? media = null,
    Object? type = null,
    Object? isPaused = null,
    Object? position = null,
    Object? duration = freezed,
    Object? speed = null,
    Object? savedPosition = freezed,
  }) {
    return _then(_$PlaybackPlayingImpl(
      media: null == media
          ? _value.media
          : media // ignore: cast_nullable_to_non_nullable
              as Media,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      isPaused: null == isPaused
          ? _value.isPaused
          : isPaused // ignore: cast_nullable_to_non_nullable
              as bool,
      position: null == position
          ? _value.position
          : position // ignore: cast_nullable_to_non_nullable
              as Duration,
      duration: freezed == duration
          ? _value.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as Duration?,
      speed: null == speed
          ? _value.speed
          : speed // ignore: cast_nullable_to_non_nullable
              as double,
      savedPosition: freezed == savedPosition
          ? _value.savedPosition
          : savedPosition // ignore: cast_nullable_to_non_nullable
              as Duration?,
    ));
  }

  @override
  @pragma('vm:prefer-inline')
  $MediaCopyWith<$Res> get media {
    return $MediaCopyWith<$Res>(_value.media, (value) {
      return _then(_value.copyWith(media: value));
    });
  }
}

/// @nodoc

class _$PlaybackPlayingImpl implements PlaybackPlaying {
  const _$PlaybackPlayingImpl(
      {required this.media,
      required this.type,
      this.isPaused = false,
      this.position = Duration.zero,
      this.duration,
      this.speed = 1.0,
      this.savedPosition});

  @override
  final Media media;
  @override
  final String type;
// 'audio' or 'video'
  @override
  @JsonKey()
  final bool isPaused;
  @override
  @JsonKey()
  final Duration position;
  @override
  final Duration? duration;
  @override
  @JsonKey()
  final double speed;
  @override
  final Duration? savedPosition;

  @override
  String toString() {
    return 'PlaybackState.playing(media: $media, type: $type, isPaused: $isPaused, position: $position, duration: $duration, speed: $speed, savedPosition: $savedPosition)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaybackPlayingImpl &&
            (identical(other.media, media) || other.media == media) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.isPaused, isPaused) ||
                other.isPaused == isPaused) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            (identical(other.speed, speed) || other.speed == speed) &&
            (identical(other.savedPosition, savedPosition) ||
                other.savedPosition == savedPosition));
  }

  @override
  int get hashCode => Object.hash(runtimeType, media, type, isPaused, position,
      duration, speed, savedPosition);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaybackPlayingImplCopyWith<_$PlaybackPlayingImpl> get copyWith =>
      __$$PlaybackPlayingImplCopyWithImpl<_$PlaybackPlayingImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)
        playing,
    required TResult Function() completed,
    required TResult Function() loading,
    required TResult Function(String message) error,
  }) {
    return playing(
        media, type, isPaused, position, duration, speed, savedPosition);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)?
        playing,
    TResult? Function()? completed,
    TResult? Function()? loading,
    TResult? Function(String message)? error,
  }) {
    return playing?.call(
        media, type, isPaused, position, duration, speed, savedPosition);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(Media media, String type, bool isPaused, Duration position,
            Duration? duration, double speed, Duration? savedPosition)?
        playing,
    TResult Function()? completed,
    TResult Function()? loading,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (playing != null) {
      return playing(
          media, type, isPaused, position, duration, speed, savedPosition);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaybackInitial value) initial,
    required TResult Function(PlaybackPlaying value) playing,
    required TResult Function(PlaybackCompleted value) completed,
    required TResult Function(PlaybackLoading value) loading,
    required TResult Function(PlaybackError value) error,
  }) {
    return playing(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaybackInitial value)? initial,
    TResult? Function(PlaybackPlaying value)? playing,
    TResult? Function(PlaybackCompleted value)? completed,
    TResult? Function(PlaybackLoading value)? loading,
    TResult? Function(PlaybackError value)? error,
  }) {
    return playing?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaybackInitial value)? initial,
    TResult Function(PlaybackPlaying value)? playing,
    TResult Function(PlaybackCompleted value)? completed,
    TResult Function(PlaybackLoading value)? loading,
    TResult Function(PlaybackError value)? error,
    required TResult orElse(),
  }) {
    if (playing != null) {
      return playing(this);
    }
    return orElse();
  }
}

abstract class PlaybackPlaying implements PlaybackState {
  const factory PlaybackPlaying(
      {required final Media media,
      required final String type,
      final bool isPaused,
      final Duration position,
      final Duration? duration,
      final double speed,
      final Duration? savedPosition}) = _$PlaybackPlayingImpl;

  Media get media;
  String get type; // 'audio' or 'video'
  bool get isPaused;
  Duration get position;
  Duration? get duration;
  double get speed;
  Duration? get savedPosition;
  @JsonKey(ignore: true)
  _$$PlaybackPlayingImplCopyWith<_$PlaybackPlayingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$PlaybackCompletedImplCopyWith<$Res> {
  factory _$$PlaybackCompletedImplCopyWith(_$PlaybackCompletedImpl value,
          $Res Function(_$PlaybackCompletedImpl) then) =
      __$$PlaybackCompletedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlaybackCompletedImplCopyWithImpl<$Res>
    extends _$PlaybackStateCopyWithImpl<$Res, _$PlaybackCompletedImpl>
    implements _$$PlaybackCompletedImplCopyWith<$Res> {
  __$$PlaybackCompletedImplCopyWithImpl(_$PlaybackCompletedImpl _value,
      $Res Function(_$PlaybackCompletedImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlaybackCompletedImpl implements PlaybackCompleted {
  const _$PlaybackCompletedImpl();

  @override
  String toString() {
    return 'PlaybackState.completed()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$PlaybackCompletedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)
        playing,
    required TResult Function() completed,
    required TResult Function() loading,
    required TResult Function(String message) error,
  }) {
    return completed();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)?
        playing,
    TResult? Function()? completed,
    TResult? Function()? loading,
    TResult? Function(String message)? error,
  }) {
    return completed?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(Media media, String type, bool isPaused, Duration position,
            Duration? duration, double speed, Duration? savedPosition)?
        playing,
    TResult Function()? completed,
    TResult Function()? loading,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaybackInitial value) initial,
    required TResult Function(PlaybackPlaying value) playing,
    required TResult Function(PlaybackCompleted value) completed,
    required TResult Function(PlaybackLoading value) loading,
    required TResult Function(PlaybackError value) error,
  }) {
    return completed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaybackInitial value)? initial,
    TResult? Function(PlaybackPlaying value)? playing,
    TResult? Function(PlaybackCompleted value)? completed,
    TResult? Function(PlaybackLoading value)? loading,
    TResult? Function(PlaybackError value)? error,
  }) {
    return completed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaybackInitial value)? initial,
    TResult Function(PlaybackPlaying value)? playing,
    TResult Function(PlaybackCompleted value)? completed,
    TResult Function(PlaybackLoading value)? loading,
    TResult Function(PlaybackError value)? error,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(this);
    }
    return orElse();
  }
}

abstract class PlaybackCompleted implements PlaybackState {
  const factory PlaybackCompleted() = _$PlaybackCompletedImpl;
}

/// @nodoc
abstract class _$$PlaybackLoadingImplCopyWith<$Res> {
  factory _$$PlaybackLoadingImplCopyWith(_$PlaybackLoadingImpl value,
          $Res Function(_$PlaybackLoadingImpl) then) =
      __$$PlaybackLoadingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlaybackLoadingImplCopyWithImpl<$Res>
    extends _$PlaybackStateCopyWithImpl<$Res, _$PlaybackLoadingImpl>
    implements _$$PlaybackLoadingImplCopyWith<$Res> {
  __$$PlaybackLoadingImplCopyWithImpl(
      _$PlaybackLoadingImpl _value, $Res Function(_$PlaybackLoadingImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlaybackLoadingImpl implements PlaybackLoading {
  const _$PlaybackLoadingImpl();

  @override
  String toString() {
    return 'PlaybackState.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$PlaybackLoadingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)
        playing,
    required TResult Function() completed,
    required TResult Function() loading,
    required TResult Function(String message) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)?
        playing,
    TResult? Function()? completed,
    TResult? Function()? loading,
    TResult? Function(String message)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(Media media, String type, bool isPaused, Duration position,
            Duration? duration, double speed, Duration? savedPosition)?
        playing,
    TResult Function()? completed,
    TResult Function()? loading,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaybackInitial value) initial,
    required TResult Function(PlaybackPlaying value) playing,
    required TResult Function(PlaybackCompleted value) completed,
    required TResult Function(PlaybackLoading value) loading,
    required TResult Function(PlaybackError value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaybackInitial value)? initial,
    TResult? Function(PlaybackPlaying value)? playing,
    TResult? Function(PlaybackCompleted value)? completed,
    TResult? Function(PlaybackLoading value)? loading,
    TResult? Function(PlaybackError value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaybackInitial value)? initial,
    TResult Function(PlaybackPlaying value)? playing,
    TResult Function(PlaybackCompleted value)? completed,
    TResult Function(PlaybackLoading value)? loading,
    TResult Function(PlaybackError value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class PlaybackLoading implements PlaybackState {
  const factory PlaybackLoading() = _$PlaybackLoadingImpl;
}

/// @nodoc
abstract class _$$PlaybackErrorImplCopyWith<$Res> {
  factory _$$PlaybackErrorImplCopyWith(
          _$PlaybackErrorImpl value, $Res Function(_$PlaybackErrorImpl) then) =
      __$$PlaybackErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$PlaybackErrorImplCopyWithImpl<$Res>
    extends _$PlaybackStateCopyWithImpl<$Res, _$PlaybackErrorImpl>
    implements _$$PlaybackErrorImplCopyWith<$Res> {
  __$$PlaybackErrorImplCopyWithImpl(
      _$PlaybackErrorImpl _value, $Res Function(_$PlaybackErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$PlaybackErrorImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$PlaybackErrorImpl implements PlaybackError {
  const _$PlaybackErrorImpl({required this.message});

  @override
  final String message;

  @override
  String toString() {
    return 'PlaybackState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaybackErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaybackErrorImplCopyWith<_$PlaybackErrorImpl> get copyWith =>
      __$$PlaybackErrorImplCopyWithImpl<_$PlaybackErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)
        playing,
    required TResult Function() completed,
    required TResult Function() loading,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media,
            String type,
            bool isPaused,
            Duration position,
            Duration? duration,
            double speed,
            Duration? savedPosition)?
        playing,
    TResult? Function()? completed,
    TResult? Function()? loading,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(Media media, String type, bool isPaused, Duration position,
            Duration? duration, double speed, Duration? savedPosition)?
        playing,
    TResult Function()? completed,
    TResult Function()? loading,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlaybackInitial value) initial,
    required TResult Function(PlaybackPlaying value) playing,
    required TResult Function(PlaybackCompleted value) completed,
    required TResult Function(PlaybackLoading value) loading,
    required TResult Function(PlaybackError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlaybackInitial value)? initial,
    TResult? Function(PlaybackPlaying value)? playing,
    TResult? Function(PlaybackCompleted value)? completed,
    TResult? Function(PlaybackLoading value)? loading,
    TResult? Function(PlaybackError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlaybackInitial value)? initial,
    TResult Function(PlaybackPlaying value)? playing,
    TResult Function(PlaybackCompleted value)? completed,
    TResult Function(PlaybackLoading value)? loading,
    TResult Function(PlaybackError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class PlaybackError implements PlaybackState {
  const factory PlaybackError({required final String message}) =
      _$PlaybackErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$PlaybackErrorImplCopyWith<_$PlaybackErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
