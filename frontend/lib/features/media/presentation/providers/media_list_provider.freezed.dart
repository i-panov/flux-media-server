// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_list_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$MediaListState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<Media> items, int total, bool hasReachedMax)
        loaded,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<Media> items, int total, bool hasReachedMax)? loaded,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<Media> items, int total, bool hasReachedMax)? loaded,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaListLoading value) loading,
    required TResult Function(MediaListLoaded value) loaded,
    required TResult Function(MediaListError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaListLoading value)? loading,
    TResult? Function(MediaListLoaded value)? loaded,
    TResult? Function(MediaListError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaListLoading value)? loading,
    TResult Function(MediaListLoaded value)? loaded,
    TResult Function(MediaListError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MediaListStateCopyWith<$Res> {
  factory $MediaListStateCopyWith(
          MediaListState value, $Res Function(MediaListState) then) =
      _$MediaListStateCopyWithImpl<$Res, MediaListState>;
}

/// @nodoc
class _$MediaListStateCopyWithImpl<$Res, $Val extends MediaListState>
    implements $MediaListStateCopyWith<$Res> {
  _$MediaListStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$MediaListLoadingImplCopyWith<$Res> {
  factory _$$MediaListLoadingImplCopyWith(_$MediaListLoadingImpl value,
          $Res Function(_$MediaListLoadingImpl) then) =
      __$$MediaListLoadingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$MediaListLoadingImplCopyWithImpl<$Res>
    extends _$MediaListStateCopyWithImpl<$Res, _$MediaListLoadingImpl>
    implements _$$MediaListLoadingImplCopyWith<$Res> {
  __$$MediaListLoadingImplCopyWithImpl(_$MediaListLoadingImpl _value,
      $Res Function(_$MediaListLoadingImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$MediaListLoadingImpl implements MediaListLoading {
  const _$MediaListLoadingImpl();

  @override
  String toString() {
    return 'MediaListState.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$MediaListLoadingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<Media> items, int total, bool hasReachedMax)
        loaded,
    required TResult Function(String message) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<Media> items, int total, bool hasReachedMax)? loaded,
    TResult? Function(String message)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<Media> items, int total, bool hasReachedMax)? loaded,
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
    required TResult Function(MediaListLoading value) loading,
    required TResult Function(MediaListLoaded value) loaded,
    required TResult Function(MediaListError value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaListLoading value)? loading,
    TResult? Function(MediaListLoaded value)? loaded,
    TResult? Function(MediaListError value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaListLoading value)? loading,
    TResult Function(MediaListLoaded value)? loaded,
    TResult Function(MediaListError value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class MediaListLoading implements MediaListState {
  const factory MediaListLoading() = _$MediaListLoadingImpl;
}

/// @nodoc
abstract class _$$MediaListLoadedImplCopyWith<$Res> {
  factory _$$MediaListLoadedImplCopyWith(_$MediaListLoadedImpl value,
          $Res Function(_$MediaListLoadedImpl) then) =
      __$$MediaListLoadedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({List<Media> items, int total, bool hasReachedMax});
}

/// @nodoc
class __$$MediaListLoadedImplCopyWithImpl<$Res>
    extends _$MediaListStateCopyWithImpl<$Res, _$MediaListLoadedImpl>
    implements _$$MediaListLoadedImplCopyWith<$Res> {
  __$$MediaListLoadedImplCopyWithImpl(
      _$MediaListLoadedImpl _value, $Res Function(_$MediaListLoadedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? items = null,
    Object? total = null,
    Object? hasReachedMax = null,
  }) {
    return _then(_$MediaListLoadedImpl(
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<Media>,
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      hasReachedMax: null == hasReachedMax
          ? _value.hasReachedMax
          : hasReachedMax // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$MediaListLoadedImpl implements MediaListLoaded {
  const _$MediaListLoadedImpl(
      {required final List<Media> items,
      required this.total,
      required this.hasReachedMax})
      : _items = items;

  final List<Media> _items;
  @override
  List<Media> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final int total;
  @override
  final bool hasReachedMax;

  @override
  String toString() {
    return 'MediaListState.loaded(items: $items, total: $total, hasReachedMax: $hasReachedMax)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaListLoadedImpl &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.hasReachedMax, hasReachedMax) ||
                other.hasReachedMax == hasReachedMax));
  }

  @override
  int get hashCode => Object.hash(runtimeType,
      const DeepCollectionEquality().hash(_items), total, hasReachedMax);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaListLoadedImplCopyWith<_$MediaListLoadedImpl> get copyWith =>
      __$$MediaListLoadedImplCopyWithImpl<_$MediaListLoadedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<Media> items, int total, bool hasReachedMax)
        loaded,
    required TResult Function(String message) error,
  }) {
    return loaded(items, total, hasReachedMax);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<Media> items, int total, bool hasReachedMax)? loaded,
    TResult? Function(String message)? error,
  }) {
    return loaded?.call(items, total, hasReachedMax);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<Media> items, int total, bool hasReachedMax)? loaded,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(items, total, hasReachedMax);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MediaListLoading value) loading,
    required TResult Function(MediaListLoaded value) loaded,
    required TResult Function(MediaListError value) error,
  }) {
    return loaded(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaListLoading value)? loading,
    TResult? Function(MediaListLoaded value)? loaded,
    TResult? Function(MediaListError value)? error,
  }) {
    return loaded?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaListLoading value)? loading,
    TResult Function(MediaListLoaded value)? loaded,
    TResult Function(MediaListError value)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(this);
    }
    return orElse();
  }
}

abstract class MediaListLoaded implements MediaListState {
  const factory MediaListLoaded(
      {required final List<Media> items,
      required final int total,
      required final bool hasReachedMax}) = _$MediaListLoadedImpl;

  List<Media> get items;
  int get total;
  bool get hasReachedMax;
  @JsonKey(ignore: true)
  _$$MediaListLoadedImplCopyWith<_$MediaListLoadedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MediaListErrorImplCopyWith<$Res> {
  factory _$$MediaListErrorImplCopyWith(_$MediaListErrorImpl value,
          $Res Function(_$MediaListErrorImpl) then) =
      __$$MediaListErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$MediaListErrorImplCopyWithImpl<$Res>
    extends _$MediaListStateCopyWithImpl<$Res, _$MediaListErrorImpl>
    implements _$$MediaListErrorImplCopyWith<$Res> {
  __$$MediaListErrorImplCopyWithImpl(
      _$MediaListErrorImpl _value, $Res Function(_$MediaListErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$MediaListErrorImpl(
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$MediaListErrorImpl implements MediaListError {
  const _$MediaListErrorImpl({required this.message});

  @override
  final String message;

  @override
  String toString() {
    return 'MediaListState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MediaListErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MediaListErrorImplCopyWith<_$MediaListErrorImpl> get copyWith =>
      __$$MediaListErrorImplCopyWithImpl<_$MediaListErrorImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<Media> items, int total, bool hasReachedMax)
        loaded,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<Media> items, int total, bool hasReachedMax)? loaded,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<Media> items, int total, bool hasReachedMax)? loaded,
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
    required TResult Function(MediaListLoading value) loading,
    required TResult Function(MediaListLoaded value) loaded,
    required TResult Function(MediaListError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MediaListLoading value)? loading,
    TResult? Function(MediaListLoaded value)? loaded,
    TResult? Function(MediaListError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MediaListLoading value)? loading,
    TResult Function(MediaListLoaded value)? loaded,
    TResult Function(MediaListError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class MediaListError implements MediaListState {
  const factory MediaListError({required final String message}) =
      _$MediaListErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$MediaListErrorImplCopyWith<_$MediaListErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
