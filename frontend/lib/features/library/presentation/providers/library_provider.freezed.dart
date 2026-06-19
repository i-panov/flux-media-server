// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'library_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$LibraryState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<MediaLibrary> libraries) loaded,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<MediaLibrary> libraries)? loaded,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<MediaLibrary> libraries)? loaded,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(LibraryLoading value) loading,
    required TResult Function(LibraryLoaded value) loaded,
    required TResult Function(LibraryError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(LibraryLoading value)? loading,
    TResult? Function(LibraryLoaded value)? loaded,
    TResult? Function(LibraryError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(LibraryLoading value)? loading,
    TResult Function(LibraryLoaded value)? loaded,
    TResult Function(LibraryError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LibraryStateCopyWith<$Res> {
  factory $LibraryStateCopyWith(
          LibraryState value, $Res Function(LibraryState) then) =
      _$LibraryStateCopyWithImpl<$Res, LibraryState>;
}

/// @nodoc
class _$LibraryStateCopyWithImpl<$Res, $Val extends LibraryState>
    implements $LibraryStateCopyWith<$Res> {
  _$LibraryStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$LibraryLoadingImplCopyWith<$Res> {
  factory _$$LibraryLoadingImplCopyWith(_$LibraryLoadingImpl value,
          $Res Function(_$LibraryLoadingImpl) then) =
      __$$LibraryLoadingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$LibraryLoadingImplCopyWithImpl<$Res>
    extends _$LibraryStateCopyWithImpl<$Res, _$LibraryLoadingImpl>
    implements _$$LibraryLoadingImplCopyWith<$Res> {
  __$$LibraryLoadingImplCopyWithImpl(
      _$LibraryLoadingImpl _value, $Res Function(_$LibraryLoadingImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$LibraryLoadingImpl implements LibraryLoading {
  const _$LibraryLoadingImpl();

  @override
  String toString() {
    return 'LibraryState.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$LibraryLoadingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<MediaLibrary> libraries) loaded,
    required TResult Function(String message) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<MediaLibrary> libraries)? loaded,
    TResult? Function(String message)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<MediaLibrary> libraries)? loaded,
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
    required TResult Function(LibraryLoading value) loading,
    required TResult Function(LibraryLoaded value) loaded,
    required TResult Function(LibraryError value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(LibraryLoading value)? loading,
    TResult? Function(LibraryLoaded value)? loaded,
    TResult? Function(LibraryError value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(LibraryLoading value)? loading,
    TResult Function(LibraryLoaded value)? loaded,
    TResult Function(LibraryError value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class LibraryLoading implements LibraryState {
  const factory LibraryLoading() = _$LibraryLoadingImpl;
}

/// @nodoc
abstract class _$$LibraryLoadedImplCopyWith<$Res> {
  factory _$$LibraryLoadedImplCopyWith(
          _$LibraryLoadedImpl value, $Res Function(_$LibraryLoadedImpl) then) =
      __$$LibraryLoadedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({List<MediaLibrary> libraries});
}

/// @nodoc
class __$$LibraryLoadedImplCopyWithImpl<$Res>
    extends _$LibraryStateCopyWithImpl<$Res, _$LibraryLoadedImpl>
    implements _$$LibraryLoadedImplCopyWith<$Res> {
  __$$LibraryLoadedImplCopyWithImpl(
      _$LibraryLoadedImpl _value, $Res Function(_$LibraryLoadedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? libraries = null,
  }) {
    return _then(_$LibraryLoadedImpl(
      libraries: null == libraries
          ? _value._libraries
          : libraries // ignore: cast_nullable_to_non_nullable
              as List<MediaLibrary>,
    ));
  }
}

/// @nodoc

class _$LibraryLoadedImpl implements LibraryLoaded {
  const _$LibraryLoadedImpl({required final List<MediaLibrary> libraries})
      : _libraries = libraries;

  final List<MediaLibrary> _libraries;
  @override
  List<MediaLibrary> get libraries {
    if (_libraries is EqualUnmodifiableListView) return _libraries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_libraries);
  }

  @override
  String toString() {
    return 'LibraryState.loaded(libraries: $libraries)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LibraryLoadedImpl &&
            const DeepCollectionEquality()
                .equals(other._libraries, _libraries));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_libraries));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LibraryLoadedImplCopyWith<_$LibraryLoadedImpl> get copyWith =>
      __$$LibraryLoadedImplCopyWithImpl<_$LibraryLoadedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<MediaLibrary> libraries) loaded,
    required TResult Function(String message) error,
  }) {
    return loaded(libraries);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<MediaLibrary> libraries)? loaded,
    TResult? Function(String message)? error,
  }) {
    return loaded?.call(libraries);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<MediaLibrary> libraries)? loaded,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(libraries);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(LibraryLoading value) loading,
    required TResult Function(LibraryLoaded value) loaded,
    required TResult Function(LibraryError value) error,
  }) {
    return loaded(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(LibraryLoading value)? loading,
    TResult? Function(LibraryLoaded value)? loaded,
    TResult? Function(LibraryError value)? error,
  }) {
    return loaded?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(LibraryLoading value)? loading,
    TResult Function(LibraryLoaded value)? loaded,
    TResult Function(LibraryError value)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(this);
    }
    return orElse();
  }
}

abstract class LibraryLoaded implements LibraryState {
  const factory LibraryLoaded({required final List<MediaLibrary> libraries}) =
      _$LibraryLoadedImpl;

  List<MediaLibrary> get libraries;
  @JsonKey(ignore: true)
  _$$LibraryLoadedImplCopyWith<_$LibraryLoadedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$LibraryErrorImplCopyWith<$Res> {
  factory _$$LibraryErrorImplCopyWith(
          _$LibraryErrorImpl value, $Res Function(_$LibraryErrorImpl) then) =
      __$$LibraryErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$LibraryErrorImplCopyWithImpl<$Res>
    extends _$LibraryStateCopyWithImpl<$Res, _$LibraryErrorImpl>
    implements _$$LibraryErrorImplCopyWith<$Res> {
  __$$LibraryErrorImplCopyWithImpl(
      _$LibraryErrorImpl _value, $Res Function(_$LibraryErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$LibraryErrorImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$LibraryErrorImpl implements LibraryError {
  const _$LibraryErrorImpl({required this.message});

  @override
  final String message;

  @override
  String toString() {
    return 'LibraryState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LibraryErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LibraryErrorImplCopyWith<_$LibraryErrorImpl> get copyWith =>
      __$$LibraryErrorImplCopyWithImpl<_$LibraryErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<MediaLibrary> libraries) loaded,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<MediaLibrary> libraries)? loaded,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<MediaLibrary> libraries)? loaded,
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
    required TResult Function(LibraryLoading value) loading,
    required TResult Function(LibraryLoaded value) loaded,
    required TResult Function(LibraryError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(LibraryLoading value)? loading,
    TResult? Function(LibraryLoaded value)? loaded,
    TResult? Function(LibraryError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(LibraryLoading value)? loading,
    TResult Function(LibraryLoaded value)? loaded,
    TResult Function(LibraryError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class LibraryError implements LibraryState {
  const factory LibraryError({required final String message}) =
      _$LibraryErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$LibraryErrorImplCopyWith<_$LibraryErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
