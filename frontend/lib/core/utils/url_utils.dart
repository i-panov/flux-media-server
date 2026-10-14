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
/// - убирает конечный слэш.
///
/// Хранится ровно то, что ввёл пользователь (без навязанного `/api`):
/// сегмент API подставляет [normalizeServerUrl] динамически при каждом
/// построении baseUrl. Query/fragment/userInfo отбрасываются молча и
/// осознанно: учётные данные в адресе сервера не нужны и утекли бы в логи.
String normalizeServerAddress(String input) {
  var value = input.trim();
  if (value.isEmpty) return value;
  if (!value.contains('://')) {
    value = 'http://$value';
  }
  // tryParse, а не parse: кривой ввод ("http://[invalid") возвращается
  // как есть, а не FormatException наружу.
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return input.trim();
  // pathSegments уже отбрасывает пустые сегменты от двойных слэшей.
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
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

/// Срезает ровно один хвостовой сегмент `api` с адреса (миграция
/// старых хранимых значений). Сравнение регистронезависимое (роуты
/// case-sensitive: `.../API` валидным baseUrl не было и не будет —
/// normalizeServerUrl всё равно допишет строчный `api`).
/// Query/fragment/userInfo отбрасываются ВСЕГДА, а не только в api-ветке:
/// в хранимом адресе им не место (токен в stored-строке светить нельзя).
/// Кривой ввод возвращается как есть (триммированный), а не исключением.
String stripApiSuffix(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return trimmed;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
    segments.removeLast();
  }
  var result = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments,
  ).toString();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Строит полный baseUrl API из адреса сервера: [normalizeServerAddress]
/// плюс ровно один хвостовой сегмент `api`.
///
/// Вызывается динамически при каждом построении baseUrl (baseUrlProvider),
/// а не хранится: экран показывает введённое, дубли исключены
/// идемпотентностью (хранимые старые значения с `/api` работают как были).
/// Путь вроде /api/v2 валидным baseUrl не является (Chopper собрал бы
/// /api/v2/media/... вместо /api/media/...) — дописываем api и туда.
String normalizeServerUrl(String input) {
  final address = normalizeServerAddress(input);
  if (address.isEmpty) return address;
  // Адрес уже проверен выше; tryParse — на случай гонки форматов.
  final uri = Uri.tryParse(address);
  if (uri == null) return input;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty || segments.last.toLowerCase() != 'api') {
    segments.add('api');
  } else {
    // Кривой регистр чиним в каноничный: .../API валидным baseUrl
    // не был (case-sensitive роуты), а .../API/api — тем более.
    segments[segments.length - 1] = 'api';
  }
  var result = uri.replace(pathSegments: segments).toString();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
