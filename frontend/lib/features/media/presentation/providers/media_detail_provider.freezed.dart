// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_detail_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$MediaDetailState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(Media media) loaded,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(Media media)? loaded,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(Media media)? loaded,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaDetailLoading value) loading,
    required TResult Function(MediaDetailLoaded value) loaded,
    required TResult Function(MediaDetailError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaDetailLoading value)? loading,
    TResult? Function(MediaDetailLoaded value)? loaded,
    TResult? Function(MediaDetailError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaDetailLoading value)? loading,
    TResult Function(MediaDetailLoaded value)? loaded,
    TResult Function(MediaDetailError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaDetailStateCopyWith<$Res> {
  factory $MediaDetailStateCopyWith(
          MediaDetailState value, $Res Function(MediaDetailState) then) =
      _$MediaDetailStateCopyWithImpl<$Res, MediaDetailState>;
}

/// @nodoc
class _$MediaDetailStateCopyWithImpl<$Res, $Val extends MediaDetailState>
    implements $MediaDetailStateCopyWith<$Res> {
  _$MediaDetailStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$MediaDetailLoadingImplCopyWith<$Res> {
  factory _$$MediaDetailLoadingImplCopyWith(_$MediaDetailLoadingImpl value,
          $Res Function(_$MediaDetailLoadingImpl) then) =
      __$$MediaDetailLoadingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$MediaDetailLoadingImplCopyWithImpl<$Res>
    extends _$MediaDetailStateCopyWithImpl<$Res, _$MediaDetailLoadingImpl>
    implements _$$MediaDetailLoadingImplCopyWith<$Res> {
  __$$MediaDetailLoadingImplCopyWithImpl(_$MediaDetailLoadingImpl _value,
      $Res Function(_$MediaDetailLoadingImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$MediaDetailLoadingImpl implements MediaDetailLoading {
  const _$MediaDetailLoadingImpl();

  @override
  String toString() {
    return 'MediaDetailState.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$MediaDetailLoadingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(Media media) loaded,
    required TResult Function(String message) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(Media media)? loaded,
    TResult? Function(String message)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(Media media)? loaded,
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
    required TResult Function(MediaDetailLoading value) loading,
    required TResult Function(MediaDetailLoaded value) loaded,
    required TResult Function(MediaDetailError value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaDetailLoading value)? loading,
    TResult? Function(MediaDetailLoaded value)? loaded,
    TResult? Function(MediaDetailError value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaDetailLoading value)? loading,
    TResult Function(MediaDetailLoaded value)? loaded,
    TResult Function(MediaDetailError value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class MediaDetailLoading implements MediaDetailState {
  const factory MediaDetailLoading() = _$MediaDetailLoadingImpl;
}

/// @nodoc
abstract class _$$MediaDetailLoadedImplCopyWith<$Res> {
  factory _$$MediaDetailLoadedImplCopyWith(_$MediaDetailLoadedImpl value,
          $Res Function(_$MediaDetailLoadedImpl) then) =
      __$$MediaDetailLoadedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Media media});

  $MediaCopyWith<$Res> get media;
}

/// @nodoc
class __$$MediaDetailLoadedImplCopyWithImpl<$Res>
    extends _$MediaDetailStateCopyWithImpl<$Res, _$MediaDetailLoadedImpl>
    implements _$$MediaDetailLoadedImplCopyWith<$Res> {
  __$$MediaDetailLoadedImplCopyWithImpl(_$MediaDetailLoadedImpl _value,
      $Res Function(_$MediaDetailLoadedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? media = null,
  }) {
    return _then(_$MediaDetailLoadedImpl(
      media: null == media
          ? _value.media
          : media // ignore: cast_nullable_to_non_nullable
              as Media,
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

class _$MediaDetailLoadedImpl implements MediaDetailLoaded {
  const _$MediaDetailLoadedImpl({required this.media});

  @override
  final Media media;

  @override
  String toString() {
    return 'MediaDetailState.loaded(media: $media)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaDetailLoadedImpl &&
            (identical(other.media, media) || other.media == media));
  }

  @override
  int get hashCode => Object.hash(runtimeType, media);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaDetailLoadedImplCopyWith<_$MediaDetailLoadedImpl> get copyWith =>
      __$$MediaDetailLoadedImplCopyWithImpl<_$MediaDetailLoadedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(Media media) loaded,
    required TResult Function(String message) error,
  }) {
    return loaded(media);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(Media media)? loaded,
    TResult? Function(String message)? error,
  }) {
    return loaded?.call(media);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(Media media)? loaded,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(media);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaDetailLoading value) loading,
    required TResult Function(MediaDetailLoaded value) loaded,
    required TResult Function(MediaDetailError value) error,
  }) {
    return loaded(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaDetailLoading value)? loading,
    TResult? Function(MediaDetailLoaded value)? loaded,
    TResult? Function(MediaDetailError value)? error,
  }) {
    return loaded?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaDetailLoading value)? loading,
    TResult Function(MediaDetailLoaded value)? loaded,
    TResult Function(MediaDetailError value)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(this);
    }
    return orElse();
  }
}

abstract class MediaDetailLoaded implements MediaDetailState {
  const factory MediaDetailLoaded({required final Media media}) =
      _$MediaDetailLoadedImpl;

  Media get media;
  @JsonKey(ignore: true)
  _$$MediaDetailLoadedImplCopyWith<_$MediaDetailLoadedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MediaDetailErrorImplCopyWith<$Res> {
  factory _$$MediaDetailErrorImplCopyWith(_$MediaDetailErrorImpl value,
          $Res Function(_$MediaDetailErrorImpl) then) =
      __$$MediaDetailErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$MediaDetailErrorImplCopyWithImpl<$Res>
    extends _$MediaDetailStateCopyWithImpl<$Res, _$MediaDetailErrorImpl>
    implements _$$MediaDetailErrorImplCopyWith<$Res> {
  __$$MediaDetailErrorImplCopyWithImpl(_$MediaDetailErrorImpl _value,
      $Res Function(_$MediaDetailErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$MediaDetailErrorImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$MediaDetailErrorImpl implements MediaDetailError {
  const _$MediaDetailErrorImpl({required this.message});

  @override
  final String message;

  @override
  String toString() {
    return 'MediaDetailState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaDetailErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaDetailErrorImplCopyWith<_$MediaDetailErrorImpl> get copyWith =>
      __$$MediaDetailErrorImplCopyWithImpl<_$MediaDetailErrorImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(Media media) loaded,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(Media media)? loaded,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(Media media)? loaded,
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
    required TResult Function(MediaDetailLoading value) loading,
    required TResult Function(MediaDetailLoaded value) loaded,
    required TResult Function(MediaDetailError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaDetailLoading value)? loading,
    TResult? Function(MediaDetailLoaded value)? loaded,
    TResult? Function(MediaDetailError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaDetailLoading value)? loading,
    TResult Function(MediaDetailLoaded value)? loaded,
    TResult Function(MediaDetailError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class MediaDetailError implements MediaDetailState {
  const factory MediaDetailError({required final String message}) =
      _$MediaDetailErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$MediaDetailErrorImplCopyWith<_$MediaDetailErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
