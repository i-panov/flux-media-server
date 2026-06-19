// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PlayerNotifierState {
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
    required TResult Function(PlayerNotifierInitial value) initial,
    required TResult Function(PlayerNotifierPlaying value) playing,
    required TResult Function(PlayerNotifierCompleted value) completed,
    required TResult Function(PlayerNotifierError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerNotifierInitial value)? initial,
    TResult? Function(PlayerNotifierPlaying value)? playing,
    TResult? Function(PlayerNotifierCompleted value)? completed,
    TResult? Function(PlayerNotifierError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerNotifierInitial value)? initial,
    TResult Function(PlayerNotifierPlaying value)? playing,
    TResult Function(PlayerNotifierCompleted value)? completed,
    TResult Function(PlayerNotifierError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlayerNotifierStateCopyWith<$Res> {
  factory $PlayerNotifierStateCopyWith(
          PlayerNotifierState value, $Res Function(PlayerNotifierState) then) =
      _$PlayerNotifierStateCopyWithImpl<$Res, PlayerNotifierState>;
}

/// @nodoc
class _$PlayerNotifierStateCopyWithImpl<$Res, $Val extends PlayerNotifierState>
    implements $PlayerNotifierStateCopyWith<$Res> {
  _$PlayerNotifierStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$PlayerNotifierInitialImplCopyWith<$Res> {
  factory _$$PlayerNotifierInitialImplCopyWith(
          _$PlayerNotifierInitialImpl value,
          $Res Function(_$PlayerNotifierInitialImpl) then) =
      __$$PlayerNotifierInitialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlayerNotifierInitialImplCopyWithImpl<$Res>
    extends _$PlayerNotifierStateCopyWithImpl<$Res, _$PlayerNotifierInitialImpl>
    implements _$$PlayerNotifierInitialImplCopyWith<$Res> {
  __$$PlayerNotifierInitialImplCopyWithImpl(_$PlayerNotifierInitialImpl _value,
      $Res Function(_$PlayerNotifierInitialImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlayerNotifierInitialImpl implements PlayerNotifierInitial {
  const _$PlayerNotifierInitialImpl();

  @override
  String toString() {
    return 'PlayerNotifierState.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerNotifierInitialImpl);
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
    required TResult Function(PlayerNotifierInitial value) initial,
    required TResult Function(PlayerNotifierPlaying value) playing,
    required TResult Function(PlayerNotifierCompleted value) completed,
    required TResult Function(PlayerNotifierError value) error,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerNotifierInitial value)? initial,
    TResult? Function(PlayerNotifierPlaying value)? playing,
    TResult? Function(PlayerNotifierCompleted value)? completed,
    TResult? Function(PlayerNotifierError value)? error,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerNotifierInitial value)? initial,
    TResult Function(PlayerNotifierPlaying value)? playing,
    TResult Function(PlayerNotifierCompleted value)? completed,
    TResult Function(PlayerNotifierError value)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class PlayerNotifierInitial implements PlayerNotifierState {
  const factory PlayerNotifierInitial() = _$PlayerNotifierInitialImpl;
}

/// @nodoc
abstract class _$$PlayerNotifierPlayingImplCopyWith<$Res> {
  factory _$$PlayerNotifierPlayingImplCopyWith(
          _$PlayerNotifierPlayingImpl value,
          $Res Function(_$PlayerNotifierPlayingImpl) then) =
      __$$PlayerNotifierPlayingImplCopyWithImpl<$Res>;
  @useResult
  $Res call(
      {Media media, bool isPaused, Duration position, Duration? duration});

  $MediaCopyWith<$Res> get media;
}

/// @nodoc
class __$$PlayerNotifierPlayingImplCopyWithImpl<$Res>
    extends _$PlayerNotifierStateCopyWithImpl<$Res, _$PlayerNotifierPlayingImpl>
    implements _$$PlayerNotifierPlayingImplCopyWith<$Res> {
  __$$PlayerNotifierPlayingImplCopyWithImpl(_$PlayerNotifierPlayingImpl _value,
      $Res Function(_$PlayerNotifierPlayingImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? media = null,
    Object? isPaused = null,
    Object? position = null,
    Object? duration = freezed,
  }) {
    return _then(_$PlayerNotifierPlayingImpl(
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

class _$PlayerNotifierPlayingImpl implements PlayerNotifierPlaying {
  const _$PlayerNotifierPlayingImpl(
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
    return 'PlayerNotifierState.playing(media: $media, isPaused: $isPaused, position: $position, duration: $duration)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerNotifierPlayingImpl &&
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
  _$$PlayerNotifierPlayingImplCopyWith<_$PlayerNotifierPlayingImpl>
      get copyWith => __$$PlayerNotifierPlayingImplCopyWithImpl<
          _$PlayerNotifierPlayingImpl>(this, _$identity);

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
    required TResult Function(PlayerNotifierInitial value) initial,
    required TResult Function(PlayerNotifierPlaying value) playing,
    required TResult Function(PlayerNotifierCompleted value) completed,
    required TResult Function(PlayerNotifierError value) error,
  }) {
    return playing(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerNotifierInitial value)? initial,
    TResult? Function(PlayerNotifierPlaying value)? playing,
    TResult? Function(PlayerNotifierCompleted value)? completed,
    TResult? Function(PlayerNotifierError value)? error,
  }) {
    return playing?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerNotifierInitial value)? initial,
    TResult Function(PlayerNotifierPlaying value)? playing,
    TResult Function(PlayerNotifierCompleted value)? completed,
    TResult Function(PlayerNotifierError value)? error,
    required TResult orElse(),
  }) {
    if (playing != null) {
      return playing(this);
    }
    return orElse();
  }
}

abstract class PlayerNotifierPlaying implements PlayerNotifierState {
  const factory PlayerNotifierPlaying(
      {required final Media media,
      final bool isPaused,
      final Duration position,
      final Duration? duration}) = _$PlayerNotifierPlayingImpl;

  Media get media;
  bool get isPaused;
  Duration get position;
  Duration? get duration;
  @JsonKey(ignore: true)
  _$$PlayerNotifierPlayingImplCopyWith<_$PlayerNotifierPlayingImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$PlayerNotifierCompletedImplCopyWith<$Res> {
  factory _$$PlayerNotifierCompletedImplCopyWith(
          _$PlayerNotifierCompletedImpl value,
          $Res Function(_$PlayerNotifierCompletedImpl) then) =
      __$$PlayerNotifierCompletedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$PlayerNotifierCompletedImplCopyWithImpl<$Res>
    extends _$PlayerNotifierStateCopyWithImpl<$Res,
        _$PlayerNotifierCompletedImpl>
    implements _$$PlayerNotifierCompletedImplCopyWith<$Res> {
  __$$PlayerNotifierCompletedImplCopyWithImpl(
      _$PlayerNotifierCompletedImpl _value,
      $Res Function(_$PlayerNotifierCompletedImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$PlayerNotifierCompletedImpl implements PlayerNotifierCompleted {
  const _$PlayerNotifierCompletedImpl();

  @override
  String toString() {
    return 'PlayerNotifierState.completed()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerNotifierCompletedImpl);
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
    required TResult Function(PlayerNotifierInitial value) initial,
    required TResult Function(PlayerNotifierPlaying value) playing,
    required TResult Function(PlayerNotifierCompleted value) completed,
    required TResult Function(PlayerNotifierError value) error,
  }) {
    return completed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerNotifierInitial value)? initial,
    TResult? Function(PlayerNotifierPlaying value)? playing,
    TResult? Function(PlayerNotifierCompleted value)? completed,
    TResult? Function(PlayerNotifierError value)? error,
  }) {
    return completed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerNotifierInitial value)? initial,
    TResult Function(PlayerNotifierPlaying value)? playing,
    TResult Function(PlayerNotifierCompleted value)? completed,
    TResult Function(PlayerNotifierError value)? error,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(this);
    }
    return orElse();
  }
}

abstract class PlayerNotifierCompleted implements PlayerNotifierState {
  const factory PlayerNotifierCompleted() = _$PlayerNotifierCompletedImpl;
}

/// @nodoc
abstract class _$$PlayerNotifierErrorImplCopyWith<$Res> {
  factory _$$PlayerNotifierErrorImplCopyWith(_$PlayerNotifierErrorImpl value,
          $Res Function(_$PlayerNotifierErrorImpl) then) =
      __$$PlayerNotifierErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$PlayerNotifierErrorImplCopyWithImpl<$Res>
    extends _$PlayerNotifierStateCopyWithImpl<$Res, _$PlayerNotifierErrorImpl>
    implements _$$PlayerNotifierErrorImplCopyWith<$Res> {
  __$$PlayerNotifierErrorImplCopyWithImpl(_$PlayerNotifierErrorImpl _value,
      $Res Function(_$PlayerNotifierErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$PlayerNotifierErrorImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$PlayerNotifierErrorImpl implements PlayerNotifierError {
  const _$PlayerNotifierErrorImpl({required this.message});

  @override
  final String message;

  @override
  String toString() {
    return 'PlayerNotifierState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlayerNotifierErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PlayerNotifierErrorImplCopyWith<_$PlayerNotifierErrorImpl> get copyWith =>
      __$$PlayerNotifierErrorImplCopyWithImpl<_$PlayerNotifierErrorImpl>(
          this, _$identity);

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
    required TResult Function(PlayerNotifierInitial value) initial,
    required TResult Function(PlayerNotifierPlaying value) playing,
    required TResult Function(PlayerNotifierCompleted value) completed,
    required TResult Function(PlayerNotifierError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(PlayerNotifierInitial value)? initial,
    TResult? Function(PlayerNotifierPlaying value)? playing,
    TResult? Function(PlayerNotifierCompleted value)? completed,
    TResult? Function(PlayerNotifierError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(PlayerNotifierInitial value)? initial,
    TResult Function(PlayerNotifierPlaying value)? playing,
    TResult Function(PlayerNotifierCompleted value)? completed,
    TResult Function(PlayerNotifierError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class PlayerNotifierError implements PlayerNotifierState {
  const factory PlayerNotifierError({required final String message}) =
      _$PlayerNotifierErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$PlayerNotifierErrorImplCopyWith<_$PlayerNotifierErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
