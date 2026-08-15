/// Результат POST /media/upload при асинхронном контракте: сервер принял
/// файл и вернул 202 с id джоба. Файл ещё обрабатывается в фоне — статус
/// опрашивается через UploadStatus (см. upload_status.dart).
class UploadResult {
  const UploadResult({required this.jobId});

  final int jobId;
}
