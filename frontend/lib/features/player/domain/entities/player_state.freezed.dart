// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PlayerState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)
        playing,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlayerInitial value) initial,
    required TResult Function(PlayerPlaying value) playing,
    required TResult Function(PlayerCompleted value) completed,
    required TResult Function(PlayerError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerInitial value)? initial,
    TResult? Function(PlayerPlaying value)? playing,
    TResult? Function(PlayerCompleted value)? completed,
    TResult? Function(PlayerError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerInitial value)? initial,
    TResult Function(PlayerPlaying value)? playing,
    TResult Function(PlayerCompleted value)? completed,
    TResult Function(PlayerError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlayerStateCopyWith<$Res> {
  factory $PlayerStateCopyWith(
          PlayerState value, $Res Function(PlayerState) then) =
      _$PlayerStateCopyWithImpl<$Res, PlayerState>;
}

/// @nodoc
class _$PlayerStateCopyWithImpl<$Res, $Val extends PlayerState>
    implements $PlayerStateCopyWith<$Res> {
  _$PlayerStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$PlayerInitialImplCopyWith<$Res> {
  factory _$$PlayerInitialImplCopyWith(
          _$PlayerInitialImpl value, $Res Function(_$PlayerInitialImpl) then) =
      __$$PlayerInitialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlayerInitialImplCopyWithImpl<$Res>
    extends _$PlayerStateCopyWithImpl<$Res, _$PlayerInitialImpl>
    implements _$$PlayerInitialImplCopyWith<$Res> {
  __$$PlayerInitialImplCopyWithImpl(
      _$PlayerInitialImpl _value, $Res Function(_$PlayerInitialImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlayerInitialImpl implements PlayerInitial {
  const _$PlayerInitialImpl();

  @override
  String toString() {
    return 'PlayerState.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$PlayerInitialImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)
        playing,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return initial();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return initial?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult Function()? completed,
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
    required TResult Function(PlayerInitial value) initial,
    required TResult Function(PlayerPlaying value) playing,
    required TResult Function(PlayerCompleted value) completed,
    required TResult Function(PlayerError value) error,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerInitial value)? initial,
    TResult? Function(PlayerPlaying value)? playing,
    TResult? Function(PlayerCompleted value)? completed,
    TResult? Function(PlayerError value)? error,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerInitial value)? initial,
    TResult Function(PlayerPlaying value)? playing,
    TResult Function(PlayerCompleted value)? completed,
    TResult Function(PlayerError value)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class PlayerInitial implements PlayerState {
  const factory PlayerInitial() = _$PlayerInitialImpl;
}

/// @nodoc
abstract class _$$PlayerPlayingImplCopyWith<$Res> {
  factory _$$PlayerPlayingImplCopyWith(
          _$PlayerPlayingImpl value, $Res Function(_$PlayerPlayingImpl) then) =
      __$$PlayerPlayingImplCopyWithImpl<$Res>;
  @useResult
  $Res call(
      {Media media, bool isPaused, Duration position, Duration? duration});

  $MediaCopyWith<$Res> get media;
}

/// @nodoc
class __$$PlayerPlayingImplCopyWithImpl<$Res>
    extends _$PlayerStateCopyWithImpl<$Res, _$PlayerPlayingImpl>
    implements _$$PlayerPlayingImplCopyWith<$Res> {
  __$$PlayerPlayingImplCopyWithImpl(
      _$PlayerPlayingImpl _value, $Res Function(_$PlayerPlayingImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? media = null,
    Object? isPaused = null,
    Object? position = null,
    Object? duration = freezed,
  }) {
    return _then(_$PlayerPlayingImpl(
      media: null == media
          ? _value.media
          : media // ignore: cast_nullable_to_non_nullable
              as Media,
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

class _$PlayerPlayingImpl implements PlayerPlaying {
  const _$PlayerPlayingImpl(
      {required this.media,
      this.isPaused = false,
      this.position = Duration.zero,
      this.duration});

  @override
  final Media media;
  @override
  @JsonKey()
  final bool isPaused;
  @override
  @JsonKey()
  final Duration position;
  @override
  final Duration? duration;

  @override
  String toString() {
    return 'PlayerState.playing(media: $media, isPaused: $isPaused, position: $position, duration: $duration)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerPlayingImpl &&
            (identical(other.media, media) || other.media == media) &&
            (identical(other.isPaused, isPaused) ||
                other.isPaused == isPaused) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.duration, duration) ||
                other.duration == duration));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, media, isPaused, position, duration);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PlayerPlayingImplCopyWith<_$PlayerPlayingImpl> get copyWith =>
      __$$PlayerPlayingImplCopyWithImpl<_$PlayerPlayingImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)
        playing,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return playing(media, isPaused, position, duration);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return playing?.call(media, isPaused, position, duration);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (playing != null) {
      return playing(media, isPaused, position, duration);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(PlayerInitial value) initial,
    required TResult Function(PlayerPlaying value) playing,
    required TResult Function(PlayerCompleted value) completed,
    required TResult Function(PlayerError value) error,
  }) {
    return playing(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerInitial value)? initial,
    TResult? Function(PlayerPlaying value)? playing,
    TResult? Function(PlayerCompleted value)? completed,
    TResult? Function(PlayerError value)? error,
  }) {
    return playing?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerInitial value)? initial,
    TResult Function(PlayerPlaying value)? playing,
    TResult Function(PlayerCompleted value)? completed,
    TResult Function(PlayerError value)? error,
    required TResult orElse(),
  }) {
    if (playing != null) {
      return playing(this);
    }
    return orElse();
  }
}

abstract class PlayerPlaying implements PlayerState {
  const factory PlayerPlaying(
      {required final Media media,
      final bool isPaused,
      final Duration position,
      final Duration? duration}) = _$PlayerPlayingImpl;

  Media get media;
  bool get isPaused;
  Duration get position;
  Duration? get duration;
  @JsonKey(ignore: true)
  _$$PlayerPlayingImplCopyWith<_$PlayerPlayingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$PlayerCompletedImplCopyWith<$Res> {
  factory _$$PlayerCompletedImplCopyWith(_$PlayerCompletedImpl value,
          $Res Function(_$PlayerCompletedImpl) then) =
      __$$PlayerCompletedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlayerCompletedImplCopyWithImpl<$Res>
    extends _$PlayerStateCopyWithImpl<$Res, _$PlayerCompletedImpl>
    implements _$$PlayerCompletedImplCopyWith<$Res> {
  __$$PlayerCompletedImplCopyWithImpl(
      _$PlayerCompletedImpl _value, $Res Function(_$PlayerCompletedImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlayerCompletedImpl implements PlayerCompleted {
  const _$PlayerCompletedImpl();

  @override
  String toString() {
    return 'PlayerState.completed()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$PlayerCompletedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)
        playing,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return completed();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return completed?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult Function()? completed,
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
    required TResult Function(PlayerInitial value) initial,
    required TResult Function(PlayerPlaying value) playing,
    required TResult Function(PlayerCompleted value) completed,
    required TResult Function(PlayerError value) error,
  }) {
    return completed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerInitial value)? initial,
    TResult? Function(PlayerPlaying value)? playing,
    TResult? Function(PlayerCompleted value)? completed,
    TResult? Function(PlayerError value)? error,
  }) {
    return completed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerInitial value)? initial,
    TResult Function(PlayerPlaying value)? playing,
    TResult Function(PlayerCompleted value)? completed,
    TResult Function(PlayerError value)? error,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(this);
    }
    return orElse();
  }
}

abstract class PlayerCompleted implements PlayerState {
  const factory PlayerCompleted() = _$PlayerCompletedImpl;
}

/// @nodoc
abstract class _$$PlayerErrorImplCopyWith<$Res> {
  factory _$$PlayerErrorImplCopyWith(
          _$PlayerErrorImpl value, $Res Function(_$PlayerErrorImpl) then) =
      __$$PlayerErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$PlayerErrorImplCopyWithImpl<$Res>
    extends _$PlayerStateCopyWithImpl<$Res, _$PlayerErrorImpl>
    implements _$$PlayerErrorImplCopyWith<$Res> {
  __$$PlayerErrorImplCopyWithImpl(
      _$PlayerErrorImpl _value, $Res Function(_$PlayerErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$PlayerErrorImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$PlayerErrorImpl implements PlayerError {
  const _$PlayerErrorImpl({required this.message});

  @override
  final String message;

  @override
  String toString() {
    return 'PlayerState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PlayerErrorImplCopyWith<_$PlayerErrorImpl> get copyWith =>
      __$$PlayerErrorImplCopyWithImpl<_$PlayerErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)
        playing,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            Media media, bool isPaused, Duration position, Duration? duration)?
        playing,
    TResult Function()? completed,
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
    required TResult Function(PlayerInitial value) initial,
    required TResult Function(PlayerPlaying value) playing,
    required TResult Function(PlayerCompleted value) completed,
    required TResult Function(PlayerError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerInitial value)? initial,
    TResult? Function(PlayerPlaying value)? playing,
    TResult? Function(PlayerCompleted value)? completed,
    TResult? Function(PlayerError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerInitial value)? initial,
    TResult Function(PlayerPlaying value)? playing,
    TResult Function(PlayerCompleted value)? completed,
    TResult Function(PlayerError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class PlayerError implements PlayerState {
  const factory PlayerError({required final String message}) =
      _$PlayerErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$PlayerErrorImplCopyWith<_$PlayerErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
