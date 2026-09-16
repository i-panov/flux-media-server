// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Media {

 int get id; String get title;@MediaTypeConverter() MediaType get type;@JsonKey(name: 'file_size') int get fileSize;@JsonKey(name: 'filename') String get filename; int? get year; String? get description; int? get duration;@JsonKey(name: 'thumbnail_url') String? get thumbnailUrl;@JsonKey(name: 'cover_url') String? get coverUrl; List<Artist> get artists; String? get album; String? get genre; Metadata? get metadata;@JsonKey(name: 'file_hash') String get fileHash;@JsonKey(name: 'updated_at') DateTime? get updatedAt;@JsonKey(name: 'created_at') DateTime? get createdAt;
/// Create a copy of Media
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaCopyWith<Media> get copyWith => _$MediaCopyWithImpl<Media>(this as Media, _$identity);

  /// Serializes this Media to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Media;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Media&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.fileSize, _this.fileSize) || other.fileSize == _this.fileSize)&&(identical(other.filename, _this.filename) || other.filename == _this.filename)&&(identical(other.year, _this.year) || other.year == _this.year)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.duration, _this.duration) || other.duration == _this.duration)&&(identical(other.thumbnailUrl, _this.thumbnailUrl) || other.thumbnailUrl == _this.thumbnailUrl)&&(identical(other.coverUrl, _this.coverUrl) || other.coverUrl == _this.coverUrl)&&const DeepCollectionEquality().equals(other.artists, _this.artists)&&(identical(other.album, _this.album) || other.album == _this.album)&&(identical(other.genre, _this.genre) || other.genre == _this.genre)&&(identical(other.metadata, _this.metadata) || other.metadata == _this.metadata)&&(identical(other.fileHash, _this.fileHash) || other.fileHash == _this.fileHash)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Media;
  return Object.hash(runtimeType,_this.id,_this.title,_this.type,_this.fileSize,_this.filename,_this.year,_this.description,_this.duration,_this.thumbnailUrl,_this.coverUrl,const DeepCollectionEquality().hash(_this.artists),_this.album,_this.genre,_this.metadata,_this.fileHash,_this.updatedAt,_this.createdAt);
}

@override
String toString() {
  final _this = this as Media;
  return 'Media(id: ${_this.id}, title: ${_this.title}, type: ${_this.type}, fileSize: ${_this.fileSize}, filename: ${_this.filename}, year: ${_this.year}, description: ${_this.description}, duration: ${_this.duration}, thumbnailUrl: ${_this.thumbnailUrl}, coverUrl: ${_this.coverUrl}, artists: ${_this.artists}, album: ${_this.album}, genre: ${_this.genre}, metadata: ${_this.metadata}, fileHash: ${_this.fileHash}, updatedAt: ${_this.updatedAt}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $MediaCopyWith<$Res>  {
  factory $MediaCopyWith(Media value, $Res Function(Media) _then) = _$MediaCopyWithImpl;
@useResult
$Res call({
 int id, String title,@MediaTypeConverter() MediaType type,@JsonKey(name: 'file_size') int fileSize,@JsonKey(name: 'filename') String filename, int? year, String? description, int? duration,@JsonKey(name: 'thumbnail_url') String? thumbnailUrl,@JsonKey(name: 'cover_url') String? coverUrl, List<Artist> artists, String? album, String? genre, Metadata? metadata,@JsonKey(name: 'file_hash') String fileHash,@JsonKey(name: 'updated_at') DateTime? updatedAt,@JsonKey(name: 'created_at') DateTime? createdAt
});


$MetadataCopyWith<$Res>? get metadata;

}
/// @nodoc
class _$MediaCopyWithImpl<$Res>
    implements $MediaCopyWith<$Res> {
  _$MediaCopyWithImpl(this._self, this._then);

  final Media _self;
  final $Res Function(Media) _then;

/// Create a copy of Media
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? type = null,Object? fileSize = null,Object? filename = null,Object? year = freezed,Object? description = freezed,Object? duration = freezed,Object? thumbnailUrl = freezed,Object? coverUrl = freezed,Object? artists = null,Object? album = freezed,Object? genre = freezed,Object? metadata = freezed,Object? fileHash = null,Object? updatedAt = freezed,Object? createdAt = freezed,}) {
  return _then(Media(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int,filename: null == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int?,thumbnailUrl: freezed == thumbnailUrl ? _self.thumbnailUrl : thumbnailUrl // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,artists: null == artists ? _self.artists : artists // ignore: cast_nullable_to_non_nullable
as List<Artist>,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,genre: freezed == genre ? _self.genre : genre // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Metadata?,fileHash: null == fileHash ? _self.fileHash : fileHash // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of Media
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataCopyWith<$Res>? get metadata {
    if (_self.metadata == null) {
    return null;
  }

  return $MetadataCopyWith<$Res>(_self.metadata!, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}


/// Adds pattern-matching-related methods to [Media].
extension MediaPatterns on Media {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Media value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Media() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Media value)  $default,){
final _that = this;
switch (_that) {
case _Media():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Media value)?  $default,){
final _that = this;
switch (_that) {
case _Media() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String title, @MediaTypeConverter()  MediaType type, @JsonKey(name: 'file_size')  int fileSize, @JsonKey(name: 'filename')  String filename,  int? year,  String? description,  int? duration, @JsonKey(name: 'thumbnail_url')  String? thumbnailUrl, @JsonKey(name: 'cover_url')  String? coverUrl,  List<Artist> artists,  String? album,  String? genre,  Metadata? metadata, @JsonKey(name: 'file_hash')  String fileHash, @JsonKey(name: 'updated_at')  DateTime? updatedAt, @JsonKey(name: 'created_at')  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Media() when $default != null:
return $default(_that.id,_that.title,_that.type,_that.fileSize,_that.filename,_that.year,_that.description,_that.duration,_that.thumbnailUrl,_that.coverUrl,_that.artists,_that.album,_that.genre,_that.metadata,_that.fileHash,_that.updatedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String title, @MediaTypeConverter()  MediaType type, @JsonKey(name: 'file_size')  int fileSize, @JsonKey(name: 'filename')  String filename,  int? year,  String? description,  int? duration, @JsonKey(name: 'thumbnail_url')  String? thumbnailUrl, @JsonKey(name: 'cover_url')  String? coverUrl,  List<Artist> artists,  String? album,  String? genre,  Metadata? metadata, @JsonKey(name: 'file_hash')  String fileHash, @JsonKey(name: 'updated_at')  DateTime? updatedAt, @JsonKey(name: 'created_at')  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _Media():
return $default(_that.id,_that.title,_that.type,_that.fileSize,_that.filename,_that.year,_that.description,_that.duration,_that.thumbnailUrl,_that.coverUrl,_that.artists,_that.album,_that.genre,_that.metadata,_that.fileHash,_that.updatedAt,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String title, @MediaTypeConverter()  MediaType type, @JsonKey(name: 'file_size')  int fileSize, @JsonKey(name: 'filename')  String filename,  int? year,  String? description,  int? duration, @JsonKey(name: 'thumbnail_url')  String? thumbnailUrl, @JsonKey(name: 'cover_url')  String? coverUrl,  List<Artist> artists,  String? album,  String? genre,  Metadata? metadata, @JsonKey(name: 'file_hash')  String fileHash, @JsonKey(name: 'updated_at')  DateTime? updatedAt, @JsonKey(name: 'created_at')  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _Media() when $default != null:
return $default(_that.id,_that.title,_that.type,_that.fileSize,_that.filename,_that.year,_that.description,_that.duration,_that.thumbnailUrl,_that.coverUrl,_that.artists,_that.album,_that.genre,_that.metadata,_that.fileHash,_that.updatedAt,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Media implements Media {
  const _Media({required this.id, required this.title, @MediaTypeConverter() required this.type, @JsonKey(name: 'file_size') required this.fileSize, @JsonKey(name: 'filename') this.filename = '', this.year, this.description, this.duration, @JsonKey(name: 'thumbnail_url') this.thumbnailUrl, @JsonKey(name: 'cover_url') this.coverUrl,  List<Artist> artists = const <Artist>[], this.album, this.genre, this.metadata, @JsonKey(name: 'file_hash') this.fileHash = '', @JsonKey(name: 'updated_at') this.updatedAt, @JsonKey(name: 'created_at') this.createdAt}): _artists = artists;
  factory _Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);

@override final  int id;
@override final  String title;
@override@MediaTypeConverter() final  MediaType type;
@override@JsonKey(name: 'file_size') final  int fileSize;
@override@JsonKey(name: 'filename') final  String filename;
@override final  int? year;
@override final  String? description;
@override final  int? duration;
@override@JsonKey(name: 'thumbnail_url') final  String? thumbnailUrl;
@override@JsonKey(name: 'cover_url') final  String? coverUrl;
 final  List<Artist> _artists;
@override@JsonKey() List<Artist> get artists {
  if (_artists is EqualUnmodifiableListView) return _artists;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_artists);
}

@override final  String? album;
@override final  String? genre;
@override final  Metadata? metadata;
@override@JsonKey(name: 'file_hash') final  String fileHash;
@override@JsonKey(name: 'updated_at') final  DateTime? updatedAt;
@override@JsonKey(name: 'created_at') final  DateTime? createdAt;

/// Create a copy of Media
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MediaCopyWith<_Media> get copyWith => __$MediaCopyWithImpl<_Media>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MediaToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Media&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.type, type) || other.type == type)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.filename, filename) || other.filename == filename)&&(identical(other.year, year) || other.year == year)&&(identical(other.description, description) || other.description == description)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.thumbnailUrl, thumbnailUrl) || other.thumbnailUrl == thumbnailUrl)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&const DeepCollectionEquality().equals(other.artists, _artists)&&(identical(other.album, album) || other.album == album)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&(identical(other.fileHash, fileHash) || other.fileHash == fileHash)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,title,type,fileSize,filename,year,description,duration,thumbnailUrl,coverUrl,const DeepCollectionEquality().hash(_artists),album,genre,metadata,fileHash,updatedAt,createdAt);
}

@override
String toString() {
    return 'Media(id: $id, title: $title, type: $type, fileSize: $fileSize, filename: $filename, year: $year, description: $description, duration: $duration, thumbnailUrl: $thumbnailUrl, coverUrl: $coverUrl, artists: $artists, album: $album, genre: $genre, metadata: $metadata, fileHash: $fileHash, updatedAt: $updatedAt, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$MediaCopyWith<$Res> implements $MediaCopyWith<$Res> {
  factory _$MediaCopyWith(_Media value, $Res Function(_Media) _then) = __$MediaCopyWithImpl;
@override @useResult
$Res call({
 int id, String title,@MediaTypeConverter() MediaType type,@JsonKey(name: 'file_size') int fileSize,@JsonKey(name: 'filename') String filename, int? year, String? description, int? duration,@JsonKey(name: 'thumbnail_url') String? thumbnailUrl,@JsonKey(name: 'cover_url') String? coverUrl, List<Artist> artists, String? album, String? genre, Metadata? metadata,@JsonKey(name: 'file_hash') String fileHash,@JsonKey(name: 'updated_at') DateTime? updatedAt,@JsonKey(name: 'created_at') DateTime? createdAt
});


@override $MetadataCopyWith<$Res>? get metadata;

}
/// @nodoc
class __$MediaCopyWithImpl<$Res>
    implements _$MediaCopyWith<$Res> {
  __$MediaCopyWithImpl(this._self, this._then);

  final _Media _self;
  final $Res Function(_Media) _then;

/// Create a copy of Media
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? type = null,Object? fileSize = null,Object? filename = null,Object? year = freezed,Object? description = freezed,Object? duration = freezed,Object? thumbnailUrl = freezed,Object? coverUrl = freezed,Object? artists = null,Object? album = freezed,Object? genre = freezed,Object? metadata = freezed,Object? fileHash = null,Object? updatedAt = freezed,Object? createdAt = freezed,}) {
  return _then(_Media(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int,filename: null == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int?,thumbnailUrl: freezed == thumbnailUrl ? _self.thumbnailUrl : thumbnailUrl // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,artists: null == artists ? _self._artists : artists // ignore: cast_nullable_to_non_nullable
as List<Artist>,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,genre: freezed == genre ? _self.genre : genre // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Metadata?,fileHash: null == fileHash ? _self.fileHash : fileHash // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of Media
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataCopyWith<$Res>? get metadata {
    if (_self.metadata == null) {
    return null;
  }

  return $MetadataCopyWith<$Res>(_self.metadata!, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}

// dart format on
