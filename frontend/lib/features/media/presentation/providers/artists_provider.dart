import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/usecases/usecase.dart';
import 'package:flux_media_server/features/media/presentation/providers/media_list_provider.dart';
import 'package:flux_media_server/shared/models/artist.dart';

/// Fetches all artists from the backend. Used by the edit metadata dialog
/// for autocomplete suggestions.
///
/// Обычный (не autoDispose) FutureProvider: список маленький и редко
/// меняется. Раньше autoDispose + keepAlive противоречили друг другу —
/// keepAlive отменял автоочистку, а инвалидации после мутаций не было.
final artistsProvider = FutureProvider<List<Artist>>((ref) async {
  final getArtists = ref.watch(getArtistsProvider);
  final result = await getArtists(const NoParams());
  return result.fold(
    (failure) => throw Exception(failure.message),
    (artists) => artists,
  );
});
