import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/features/library/presentation/providers/library_provider.dart';
import 'package:flux_media_server/shared/models/library.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

@RoutePage()
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final notifier = ref.read(libraryProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Libraries')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (libraries) => RefreshIndicator(
          onRefresh: () async => notifier.refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: libraries.length,
            itemBuilder: (context, index) {
              final library = libraries[index];
              final isScanning = notifier.scanningLibraryId == library.id;
              return _LibraryCard(
                library: library,
                isScanning: isScanning,
                onScan: () => notifier.scan(library.id),
              );
            },
          ),
        ),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => notifier.refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryCard extends ConsumerWidget {
  const _LibraryCard({
    required this.library,
    required this.isScanning,
    required this.onScan,
  });

  final MediaLibrary library;
  final bool isScanning;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch scan status when scanning
    final scanStatusAsync =
        isScanning ? ref.watch(scanStatusProvider(library.id)) : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          title: Text(library.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(library.path),
              if (isScanning) ...[
                const SizedBox(height: 8),
                _ScanStatusBar(scanStatus: scanStatusAsync),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: library.enabled,
                onChanged: null, // Read-only for now
              ),
              IconButton(
                icon: isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                onPressed: isScanning ? null : onScan,
                tooltip: isScanning ? 'Scanning...' : 'Scan library',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({required this.scanStatus});

  final AsyncValue<ScanStatus?>? scanStatus;

  @override
  Widget build(BuildContext context) {
    return scanStatus?.when(
          data: (status) {
            if (status == null) return const SizedBox.shrink();
            if (status.running) {
              return Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Scanning...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              );
            }
            if (status.lastError != null && status.lastError!.isNotEmpty) {
              return Text(
                'Error: ${status.lastError}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              );
            }
            return Text(
              'Scan completed',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ) ??
        const SizedBox.shrink();
  }
}
