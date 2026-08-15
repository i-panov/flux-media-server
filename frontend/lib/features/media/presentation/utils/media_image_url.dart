/// Тип картинки медиа на сервере.
enum MediaImageKind {
  thumb,
  cover;

  String get path => switch (this) {
        MediaImageKind.thumb => 'thumb',
        MediaImageKind.cover => 'cover',
      };
}

/// Строит URL картинки медиа (`{baseUrl}/media/{id}/thumb|cover`) с
/// cache-buster'ом для принудительной перезагрузки после смены обложки.
///
/// Единая точка сборки — раньше URL захардкожены в трёх местах.
String buildMediaImageUrl({
  required String baseUrl,
  required int mediaId,
  required MediaImageKind kind,
  int? cacheBust,
}) {
  final buster = cacheBust != null ? '?v=$cacheBust' : '';
  return '$baseUrl/media/$mediaId/${kind.path}$buster';
}

/// true, если у медиа есть год (0 = «нет данных» на бэкенде).
bool hasMediaYear(int? year) => year != null && year > 0;
