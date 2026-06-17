import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(libraryProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Libraries')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (libraries) => RefreshIndicator(
          onRefresh: () => ref.read(libraryProvider.notifier).load(),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: libraries.length,
            itemBuilder: (context, index) {
              final library = libraries[index];
              return Card(
                child: ListTile(
                  title: Text(library.name),
                  subtitle: Text(library.path),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: library.enabled,
                        onChanged: null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.sync),
                        onPressed: () {
                          ref.read(libraryProvider.notifier).scan(library.id);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        error: (message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(libraryProvider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final libraryProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  throw UnimplementedError(
    'libraryProvider must be overridden at app level',
  );
});
