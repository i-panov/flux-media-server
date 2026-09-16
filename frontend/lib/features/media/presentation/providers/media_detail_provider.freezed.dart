// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_detail_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MediaDetailState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaDetailState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MediaDetailState()';
}


}

/// @nodoc
class $MediaDetailStateCopyWith<$Res>  {
$MediaDetailStateCopyWith(MediaDetailState _, $Res Function(MediaDetailState) __);
}


/// Adds pattern-matching-related methods to [MediaDetailState].
extension MediaDetailStatePatterns on MediaDetailState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MediaDetailLoading value)?  loading,TResult Function( MediaDetailLoaded value)?  loaded,TResult Function( MediaDetailError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MediaDetailLoading() when loading != null:
return loading(_that);case MediaDetailLoaded() when loaded != null:
return loaded(_that);case MediaDetailError() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MediaDetailLoading value)  loading,required TResult Function( MediaDetailLoaded value)  loaded,required TResult Function( MediaDetailError value)  error,}){
final _that = this;
switch (_that) {
case MediaDetailLoading():
return loading(_that);case MediaDetailLoaded():
return loaded(_that);case MediaDetailError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MediaDetailLoading value)?  loading,TResult? Function( MediaDetailLoaded value)?  loaded,TResult? Function( MediaDetailError value)?  error,}){
final _that = this;
switch (_that) {
case MediaDetailLoading() when loading != null:
return loading(_that);case MediaDetailLoaded() when loaded != null:
return loaded(_that);case MediaDetailError() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  loading,TResult Function( Media media)?  loaded,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MediaDetailLoading() when loading != null:
return loading();case MediaDetailLoaded() when loaded != null:
return loaded(_that.media);case MediaDetailError() when error != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  loading,required TResult Function( Media media)  loaded,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case MediaDetailLoading():
return loading();case MediaDetailLoaded():
return loaded(_that.media);case MediaDetailError():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  loading,TResult? Function( Media media)?  loaded,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case MediaDetailLoading() when loading != null:
return loading();case MediaDetailLoaded() when loaded != null:
return loaded(_that.media);case MediaDetailError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class MediaDetailLoading implements MediaDetailState {
  const MediaDetailLoading();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaDetailLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MediaDetailState.loading()';
}


}




/// @nodoc


class MediaDetailLoaded implements MediaDetailState {
  const MediaDetailLoaded({required this.media});
  

 final  Media media;

/// Create a copy of MediaDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaDetailLoadedCopyWith<MediaDetailLoaded> get copyWith => _$MediaDetailLoadedCopyWithImpl<MediaDetailLoaded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaDetailLoaded&&(identical(other.media, media) || other.media == media));
}


@override
int get hashCode {
    return Object.hash(runtimeType,media);
}

@override
String toString() {
    return 'MediaDetailState.loaded(media: $media)';
}


}

/// @nodoc
abstract mixin class $MediaDetailLoadedCopyWith<$Res> implements $MediaDetailStateCopyWith<$Res> {
  factory $MediaDetailLoadedCopyWith(MediaDetailLoaded value, $Res Function(MediaDetailLoaded) _then) = _$MediaDetailLoadedCopyWithImpl;
@useResult
$Res call({
 Media media
});


$MediaCopyWith<$Res> get media;

}
/// @nodoc
class _$MediaDetailLoadedCopyWithImpl<$Res>
    implements $MediaDetailLoadedCopyWith<$Res> {
  _$MediaDetailLoadedCopyWithImpl(this._self, this._then);

  final MediaDetailLoaded _self;
  final $Res Function(MediaDetailLoaded) _then;

/// Create a copy of MediaDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? media = null,}) {
  return _then(MediaDetailLoaded(
media: null == media ? _self.media : media // ignore: cast_nullable_to_non_nullable
as Media,
  ));
}

/// Create a copy of MediaDetailState
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


class MediaDetailError implements MediaDetailState {
  const MediaDetailError({required this.message});
  

 final  String message;

/// Create a copy of MediaDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaDetailErrorCopyWith<MediaDetailError> get copyWith => _$MediaDetailErrorCopyWithImpl<MediaDetailError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaDetailError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'MediaDetailState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $MediaDetailErrorCopyWith<$Res> implements $MediaDetailStateCopyWith<$Res> {
  factory $MediaDetailErrorCopyWith(MediaDetailError value, $Res Function(MediaDetailError) _then) = _$MediaDetailErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$MediaDetailErrorCopyWithImpl<$Res>
    implements $MediaDetailErrorCopyWith<$Res> {
  _$MediaDetailErrorCopyWithImpl(this._self, this._then);

  final MediaDetailError _self;
  final $Res Function(MediaDetailError) _then;

/// Create a copy of MediaDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(MediaDetailError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
