import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/artist.dart';

/// Fetches all artists from the backend. Used by the edit metadata dialog
/// for autocomplete suggestions.
///
/// keepAlive: список исполнителей не должен перезапрашиваться при каждом
/// переходе на экран/открытии диалога.
final artistsProvider = FutureProvider.autoDispose<List<Artist>>((ref) async {
  final keepAlive = ref.keepAlive();
  ref.onDispose(keepAlive.close);

  final getArtists = ref.watch(getArtistsProvider);
  final result = await getArtists(const NoParams());
  return result.fold(
    (failure) => throw Exception(failure.message),
    (artists) => artists,
  );
});
