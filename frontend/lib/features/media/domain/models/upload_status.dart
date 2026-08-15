import 'package:flux_media_server/shared/models/media.dart';

/// Статус асинхронного upload-джоба (GET /media/uploads/{id}).
///
/// [status]: queued | processing | done | error. При `done` в [media]
/// лежит готовый объект медиа (если сервер его вернул), при `error` —
/// описание в [error].
class UploadStatus {
  const UploadStatus({
    required this.id,
    required this.status,
    this.error,
    this.media,
  });

  final int id;
  final String status;
  final String? error;
  final Media? media;

  bool get isDone => status == 'done';
  bool get isError => status == 'error';
}
