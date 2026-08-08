import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/artist.dart';

/// Fetches all artists from the backend. Used by the edit metadata dialog
/// for autocomplete suggestions.
final artistsProvider = FutureProvider.autoDispose<List<Artist>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.getArtists();
  checkResponse(response, 'Failed to fetch artists');
  final body = response.body!;
  final items = body['items'] as List<dynamic>;
  return items
      .map((json) => Artist.fromJson(json as Map<String, dynamic>))
      .toList();
});
