import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
sealed class User with _$User {
  const factory({
    required int id,
    required String email,
    @JsonKey(name: 'is_admin') @Default(false) bool isAdmin,
  }) = _User;

  factory fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
