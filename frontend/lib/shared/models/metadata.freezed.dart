// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Metadata {

 int get id;@JsonKey(name: 'external_id') String? get externalId; String? get source; String? get title; int? get year; String? get description;@JsonKey(name: 'poster_url') String? get posterUrl;@JsonKey(name: 'backdrop_url') String? get backdropUrl; double? get rating;@JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? get genres;@JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? get cast;
/// Create a copy of Metadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataCopyWith<Metadata> get copyWith => _$MetadataCopyWithImpl<Metadata>(this as Metadata, _$identity);

  /// Serializes this Metadata to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Metadata;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Metadata&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.externalId, _this.externalId) || other.externalId == _this.externalId)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.year, _this.year) || other.year == _this.year)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.posterUrl, _this.posterUrl) || other.posterUrl == _this.posterUrl)&&(identical(other.backdropUrl, _this.backdropUrl) || other.backdropUrl == _this.backdropUrl)&&(identical(other.rating, _this.rating) || other.rating == _this.rating)&&const DeepCollectionEquality().equals(other.genres, _this.genres)&&const DeepCollectionEquality().equals(other.cast, _this.cast));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Metadata;
  return Object.hash(runtimeType,_this.id,_this.externalId,_this.source,_this.title,_this.year,_this.description,_this.posterUrl,_this.backdropUrl,_this.rating,const DeepCollectionEquality().hash(_this.genres),const DeepCollectionEquality().hash(_this.cast));
}

@override
String toString() {
  final _this = this as Metadata;
  return 'Metadata(id: ${_this.id}, externalId: ${_this.externalId}, source: ${_this.source}, title: ${_this.title}, year: ${_this.year}, description: ${_this.description}, posterUrl: ${_this.posterUrl}, backdropUrl: ${_this.backdropUrl}, rating: ${_this.rating}, genres: ${_this.genres}, cast: ${_this.cast})';
}


}

/// @nodoc
abstract mixin class $MetadataCopyWith<$Res>  {
  factory $MetadataCopyWith(Metadata value, $Res Function(Metadata) _then) = _$MetadataCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'external_id') String? externalId, String? source, String? title, int? year, String? description,@JsonKey(name: 'poster_url') String? posterUrl,@JsonKey(name: 'backdrop_url') String? backdropUrl, double? rating,@JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? genres,@JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? cast
});




}
/// @nodoc
class _$MetadataCopyWithImpl<$Res>
    implements $MetadataCopyWith<$Res> {
  _$MetadataCopyWithImpl(this._self, this._then);

  final Metadata _self;
  final $Res Function(Metadata) _then;

/// Create a copy of Metadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? externalId = freezed,Object? source = freezed,Object? title = freezed,Object? year = freezed,Object? description = freezed,Object? posterUrl = freezed,Object? backdropUrl = freezed,Object? rating = freezed,Object? genres = freezed,Object? cast = freezed,}) {
  return _then(Metadata(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,externalId: freezed == externalId ? _self.externalId : externalId // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,posterUrl: freezed == posterUrl ? _self.posterUrl : posterUrl // ignore: cast_nullable_to_non_nullable
as String?,backdropUrl: freezed == backdropUrl ? _self.backdropUrl : backdropUrl // ignore: cast_nullable_to_non_nullable
as String?,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double?,genres: freezed == genres ? _self.genres : genres // ignore: cast_nullable_to_non_nullable
as List<String>?,cast: freezed == cast ? _self.cast : cast // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}

}


/// Adds pattern-matching-related methods to [Metadata].
extension MetadataPatterns on Metadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Metadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Metadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Metadata value)  $default,){
final _that = this;
switch (_that) {
case _Metadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Metadata value)?  $default,){
final _that = this;
switch (_that) {
case _Metadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'external_id')  String? externalId,  String? source,  String? title,  int? year,  String? description, @JsonKey(name: 'poster_url')  String? posterUrl, @JsonKey(name: 'backdrop_url')  String? backdropUrl,  double? rating, @JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? genres, @JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? cast)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Metadata() when $default != null:
return $default(_that.id,_that.externalId,_that.source,_that.title,_that.year,_that.description,_that.posterUrl,_that.backdropUrl,_that.rating,_that.genres,_that.cast);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'external_id')  String? externalId,  String? source,  String? title,  int? year,  String? description, @JsonKey(name: 'poster_url')  String? posterUrl, @JsonKey(name: 'backdrop_url')  String? backdropUrl,  double? rating, @JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? genres, @JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? cast)  $default,) {final _that = this;
switch (_that) {
case _Metadata():
return $default(_that.id,_that.externalId,_that.source,_that.title,_that.year,_that.description,_that.posterUrl,_that.backdropUrl,_that.rating,_that.genres,_that.cast);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'external_id')  String? externalId,  String? source,  String? title,  int? year,  String? description, @JsonKey(name: 'poster_url')  String? posterUrl, @JsonKey(name: 'backdrop_url')  String? backdropUrl,  double? rating, @JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? genres, @JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? cast)?  $default,) {final _that = this;
switch (_that) {
case _Metadata() when $default != null:
return $default(_that.id,_that.externalId,_that.source,_that.title,_that.year,_that.description,_that.posterUrl,_that.backdropUrl,_that.rating,_that.genres,_that.cast);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Metadata implements Metadata {
  const _Metadata({required this.id, @JsonKey(name: 'external_id') this.externalId, this.source, this.title, this.year, this.description, @JsonKey(name: 'poster_url') this.posterUrl, @JsonKey(name: 'backdrop_url') this.backdropUrl, this.rating, @JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? genres, @JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson)  List<String>? cast}): _genres = genres,_cast = cast;
  factory _Metadata.fromJson(Map<String, dynamic> json) => _$MetadataFromJson(json);

@override final  int id;
@override@JsonKey(name: 'external_id') final  String? externalId;
@override final  String? source;
@override final  String? title;
@override final  int? year;
@override final  String? description;
@override@JsonKey(name: 'poster_url') final  String? posterUrl;
@override@JsonKey(name: 'backdrop_url') final  String? backdropUrl;
@override final  double? rating;
 final  List<String>? _genres;
@override@JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? get genres {
  final value = _genres;
  if (value == null) return null;
  if (_genres is EqualUnmodifiableListView) return _genres;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<String>? _cast;
@override@JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? get cast {
  final value = _cast;
  if (value == null) return null;
  if (_cast is EqualUnmodifiableListView) return _cast;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of Metadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetadataCopyWith<_Metadata> get copyWith => __$MetadataCopyWithImpl<_Metadata>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MetadataToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Metadata&&(identical(other.id, id) || other.id == id)&&(identical(other.externalId, externalId) || other.externalId == externalId)&&(identical(other.source, source) || other.source == source)&&(identical(other.title, title) || other.title == title)&&(identical(other.year, year) || other.year == year)&&(identical(other.description, description) || other.description == description)&&(identical(other.posterUrl, posterUrl) || other.posterUrl == posterUrl)&&(identical(other.backdropUrl, backdropUrl) || other.backdropUrl == backdropUrl)&&(identical(other.rating, rating) || other.rating == rating)&&const DeepCollectionEquality().equals(other.genres, _genres)&&const DeepCollectionEquality().equals(other.cast, _cast));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,externalId,source,title,year,description,posterUrl,backdropUrl,rating,const DeepCollectionEquality().hash(_genres),const DeepCollectionEquality().hash(_cast));
}

@override
String toString() {
    return 'Metadata(id: $id, externalId: $externalId, source: $source, title: $title, year: $year, description: $description, posterUrl: $posterUrl, backdropUrl: $backdropUrl, rating: $rating, genres: $genres, cast: $cast)';
}


}

/// @nodoc
abstract mixin class _$MetadataCopyWith<$Res> implements $MetadataCopyWith<$Res> {
  factory _$MetadataCopyWith(_Metadata value, $Res Function(_Metadata) _then) = __$MetadataCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'external_id') String? externalId, String? source, String? title, int? year, String? description,@JsonKey(name: 'poster_url') String? posterUrl,@JsonKey(name: 'backdrop_url') String? backdropUrl, double? rating,@JsonKey(name: 'genres', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? genres,@JsonKey(name: 'cast', fromJson: _stringListFromJson, toJson: _stringListToJson) List<String>? cast
});




}
/// @nodoc
class __$MetadataCopyWithImpl<$Res>
    implements _$MetadataCopyWith<$Res> {
  __$MetadataCopyWithImpl(this._self, this._then);

  final _Metadata _self;
  final $Res Function(_Metadata) _then;

/// Create a copy of Metadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? externalId = freezed,Object? source = freezed,Object? title = freezed,Object? year = freezed,Object? description = freezed,Object? posterUrl = freezed,Object? backdropUrl = freezed,Object? rating = freezed,Object? genres = freezed,Object? cast = freezed,}) {
  return _then(_Metadata(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,externalId: freezed == externalId ? _self.externalId : externalId // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,posterUrl: freezed == posterUrl ? _self.posterUrl : posterUrl // ignore: cast_nullable_to_non_nullable
as String?,backdropUrl: freezed == backdropUrl ? _self.backdropUrl : backdropUrl // ignore: cast_nullable_to_non_nullable
as String?,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double?,genres: freezed == genres ? _self._genres : genres // ignore: cast_nullable_to_non_nullable
as List<String>?,cast: freezed == cast ? _self._cast : cast // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}


}

// dart format on
