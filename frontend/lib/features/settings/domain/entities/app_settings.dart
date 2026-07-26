import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';

@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    String? serverUrl,
    String? authToken,
    String? refreshToken,
    @Default('en') String locale,
  }) = _AppSettings;
}
