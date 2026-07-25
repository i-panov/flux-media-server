// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lyrics.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Lyrics _$LyricsFromJson(Map<String, dynamic> json) {
  return _Lyrics.fromJson(json);
}

/// @nodoc
mixin _$Lyrics {
  int get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'media_id')
  int get mediaId => throw _privateConstructorUsedError;
  @JsonKey(name: 'lyrics_text')
  String get lyricsText => throw _privateConstructorUsedError;
  @JsonKey(name: 'translation')
  String get translation => throw _privateConstructorUsedError;
  @JsonKey(name: 'sync_data')
  String get syncData => throw _privateConstructorUsedError;
  String get source => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $LyricsCopyWith<Lyrics> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LyricsCopyWith<$Res> {
  factory $LyricsCopyWith(Lyrics value, $Res Function(Lyrics) then) =
      _$LyricsCopyWithImpl<$Res, Lyrics>;
  @useResult
  $Res call(
      {int id,
      @JsonKey(name: 'media_id') int mediaId,
      @JsonKey(name: 'lyrics_text') String lyricsText,
      @JsonKey(name: 'translation') String translation,
      @JsonKey(name: 'sync_data') String syncData,
      String source,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt});
}

/// @nodoc
class _$LyricsCopyWithImpl<$Res, $Val extends Lyrics>
    implements $LyricsCopyWith<$Res> {
  _$LyricsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? mediaId = null,
    Object? lyricsText = null,
    Object? translation = null,
    Object? syncData = null,
    Object? source = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      mediaId: null == mediaId
          ? _value.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as int,
      lyricsText: null == lyricsText
          ? _value.lyricsText
          : lyricsText // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _value.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      syncData: null == syncData
          ? _value.syncData
          : syncData // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$LyricsImplCopyWith<$Res> implements $LyricsCopyWith<$Res> {
  factory _$$LyricsImplCopyWith(
          _$LyricsImpl value, $Res Function(_$LyricsImpl) then) =
      __$$LyricsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int id,
      @JsonKey(name: 'media_id') int mediaId,
      @JsonKey(name: 'lyrics_text') String lyricsText,
      @JsonKey(name: 'translation') String translation,
      @JsonKey(name: 'sync_data') String syncData,
      String source,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt});
}

/// @nodoc
class __$$LyricsImplCopyWithImpl<$Res>
    extends _$LyricsCopyWithImpl<$Res, _$LyricsImpl>
    implements _$$LyricsImplCopyWith<$Res> {
  __$$LyricsImplCopyWithImpl(
      _$LyricsImpl _value, $Res Function(_$LyricsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? mediaId = null,
    Object? lyricsText = null,
    Object? translation = null,
    Object? syncData = null,
    Object? source = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_$LyricsImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      mediaId: null == mediaId
          ? _value.mediaId
          : mediaId // ignore: cast_nullable_to_non_nullable
              as int,
      lyricsText: null == lyricsText
          ? _value.lyricsText
          : lyricsText // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _value.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      syncData: null == syncData
          ? _value.syncData
          : syncData // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LyricsImpl implements _Lyrics {
  const _$LyricsImpl(
      {required this.id,
      @JsonKey(name: 'media_id') required this.mediaId,
      @JsonKey(name: 'lyrics_text') this.lyricsText = '',
      @JsonKey(name: 'translation') this.translation = '',
      @JsonKey(name: 'sync_data') this.syncData = '',
      required this.source,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'updated_at') required this.updatedAt});

  factory _$LyricsImpl.fromJson(Map<String, dynamic> json) =>
      _$$LyricsImplFromJson(json);

  @override
  final int id;
  @override
  @JsonKey(name: 'media_id')
  final int mediaId;
  @override
  @JsonKey(name: 'lyrics_text')
  final String lyricsText;
  @override
  @JsonKey(name: 'translation')
  final String translation;
  @override
  @JsonKey(name: 'sync_data')
  final String syncData;
  @override
  final String source;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  @override
  String toString() {
    return 'Lyrics(id: $id, mediaId: $mediaId, lyricsText: $lyricsText, translation: $translation, syncData: $syncData, source: $source, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LyricsImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.mediaId, mediaId) || other.mediaId == mediaId) &&
            (identical(other.lyricsText, lyricsText) ||
                other.lyricsText == lyricsText) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.syncData, syncData) ||
                other.syncData == syncData) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, mediaId, lyricsText,
      translation, syncData, source, createdAt, updatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LyricsImplCopyWith<_$LyricsImpl> get copyWith =>
      __$$LyricsImplCopyWithImpl<_$LyricsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LyricsImplToJson(
      this,
    );
  }
}

abstract class _Lyrics implements Lyrics {
  const factory _Lyrics(
          {required final int id,
          @JsonKey(name: 'media_id') required final int mediaId,
          @JsonKey(name: 'lyrics_text') final String lyricsText,
          @JsonKey(name: 'translation') final String translation,
          @JsonKey(name: 'sync_data') final String syncData,
          required final String source,
          @JsonKey(name: 'created_at') required final DateTime createdAt,
          @JsonKey(name: 'updated_at') required final DateTime updatedAt}) =
      _$LyricsImpl;

  factory _Lyrics.fromJson(Map<String, dynamic> json) = _$LyricsImpl.fromJson;

  @override
  int get id;
  @override
  @JsonKey(name: 'media_id')
  int get mediaId;
  @override
  @JsonKey(name: 'lyrics_text')
  String get lyricsText;
  @override
  @JsonKey(name: 'translation')
  String get translation;
  @override
  @JsonKey(name: 'sync_data')
  String get syncData;
  @override
  String get source;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt;
  @override
  @JsonKey(ignore: true)
  _$$LyricsImplCopyWith<_$LyricsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
