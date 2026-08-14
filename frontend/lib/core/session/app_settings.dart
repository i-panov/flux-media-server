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

  /// Токены не должны попадать в логи: маскируем их в [toString].
  @override
  String toString() {
    final safeAuthToken = authToken == null ? null : '***';
    final safeRefreshToken = refreshToken == null ? null : '***';
    return 'AppSettings(serverUrl: $serverUrl, '
        'authToken: $safeAuthToken, '
        'refreshToken: $safeRefreshToken, '
        'locale: $locale)';
  }
}
