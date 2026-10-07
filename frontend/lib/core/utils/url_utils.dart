/// Утилиты валидации и нормализации адреса сервера.
library;

/// Адрес сервера по умолчанию (без сегмента `/api`).
const String defaultServerAddress = 'http://localhost:8080';

/// Проверяет, что [input] похож на корректный адрес сервера:
/// непустая строка со схемой http/https и непустым хостом.
bool isValidServerUrl(String input) {
  return _isHttpUrl(input, maxLength: null);
}

/// Проверяет, что [input] — готовая http(s)-ссылка (например, на
/// источник видео): схема и хост на месте, схему НЕ добавляем —
/// в отличие от адреса сервера, здесь нужна полная ссылка.
/// Пустая строка — невалидна (очистку поля диалог обрабатывает отдельно).
///
/// Лимит длины — как на сервере (`maxSourceURLLen = 2048`): паритет,
/// чтобы длинная вставка подсвечивала поле, а не падала на PUT 400.
bool isValidHttpUrl(String input) {
  return _isHttpUrl(input, maxLength: 2048);
}

/// Общее ядро обеих проверок: trim, схема http/https, непустой хост.
/// [maxLength] в символах (руны, как серверный `RuneCountInString`);
/// `null` — без лимита.
bool _isHttpUrl(String input, {required int? maxLength}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return false;
  if (maxLength != null && trimmed.runes.length > maxLength) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  if (uri.host.isEmpty) return false;
  return true;
}

/// Приводит адрес сервера к единому формату хранения:
/// - обрезает пробелы по краям;
/// - добавляет схему `http://`, если её нет;
/// - отбрасывает дублирующиеся слэши;
/// - добавляет сегмент `api`, если его ещё нет в пути;
/// - убирает конечный слэш.
///
/// Хранимое значение является полным baseUrl API (включает `/api`),
/// поэтому Chopper-сервисы объявляют пути относительно него
/// (например `/auth/request-code`), а health-check выполняется
/// по адресу `$result/health` (= `.../api/health`).
String normalizeServerUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return value;
  if (!value.contains('://')) {
    value = 'http://$value';
  }
  final uri = Uri.parse(value);
  // pathSegments уже отбрасывает пустые сегменты от двойных слэшей.
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (!segments.contains('api')) {
    segments.add('api');
  }
  final normalized = Uri(
    scheme: uri.scheme,
    // userInfo намеренно не сохраняется (дефолт null): учётные данные
    // в адресе сервера не нужны и утекли бы в логи при логировании URL.
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments,
  );
  var result = normalized.toString();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
