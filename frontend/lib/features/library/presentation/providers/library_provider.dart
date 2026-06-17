import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flux_media_server/features/library/domain/repositories/library_repository.dart';
import 'package:flux_media_server/shared/models/library.dart';

part 'library_provider.freezed.dart';

@freezed
class LibraryState with _$LibraryState {
  const factory LibraryState.loading() = LibraryLoading;
  const factory LibraryState.loaded({required List<MediaLibrary> libraries}) = LibraryLoaded;
  const factory LibraryState.error({required String message}) = LibraryError;
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier({
    required LibraryRepository repository,
  })  : _repository = repository,
        super(const LibraryState.loading());

  final LibraryRepository _repository;

  Future<void> load() async {
    state = const LibraryState.loading();
    final result = await _repository.getLibraries();
    result.fold(
      (failure) => state = LibraryState.error(message: failure.message),
      (libraries) => state = LibraryState.loaded(libraries: libraries),
    );
  }

  Future<void> scan(int id) async {
    await _repository.scanLibrary(id);
    await load();
  }
}
