import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/lyrics.dart';

class LyricsRemoteDataSource {
  LyricsRemoteDataSource(this.apiClient);

  final MediaApiClient apiClient;

  Future<Lyrics?> getLyrics(int mediaId) async {
    final response = await apiClient.getLyrics(mediaId);
    if (response.statusCode == 404) {
      return null;
    }
    checkResponse(response, 'Failed to fetch lyrics');
    return Lyrics.fromJson(response.body!);
  }

  Future<Lyrics> upsertLyrics(
    int mediaId, {
    required String lyricsText,
    required String source,
    String? translation,
    String? syncData,
  }) async {
    final response = await apiClient.upsertLyrics(mediaId, {
      'lyrics_text': lyricsText,
      'translation': translation ?? '',
      'sync_data': syncData ?? '',
      'source': source,
    });
    checkResponse(response, 'Failed to save lyrics');
    return Lyrics.fromJson(response.body!);
  }
}
