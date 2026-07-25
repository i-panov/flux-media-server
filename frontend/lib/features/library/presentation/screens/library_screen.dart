import 'package:auto_route/auto_route.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
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
  Widget _buildGroupedList(IList<MediaLibrary> libraries, LibraryNotifier notifier) {
    final videoLibs = libraries.where((l) => l.type == 'video').toIList();
    final audioLibs = libraries.where((l) => l.type == 'audio').toIList();

    return RefreshIndicator(
      onRefresh: () async => notifier.refresh(),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          if (videoLibs.isNotEmpty) ...[
            _buildSectionHeader('Video', Icons.movie, videoLibs.length),
            ...videoLibs.map((l) => _buildCard(l, notifier)),
          ],
          if (audioLibs.isNotEmpty) ...[
            _buildSectionHeader('Audio', Icons.music_note, audioLibs.length),
            ...audioLibs.map((l) => _buildCard(l, notifier)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('($count)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildCard(MediaLibrary library, LibraryNotifier notifier) {
    final isScanning = notifier.scanningLibraryId == library.id;
    return _LibraryCard(
      library: library,
      isScanning: isScanning,
      onScan: () => notifier.scan(library.id),
      onDelete: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Library'),
            content: Text('Delete "${library.name}"? Files on disk will not be removed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (confirm == true) {
          final error = await notifier.deleteLibrary(library.id);
          if (error != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    String type = 'video';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Library'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Movies',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'video', child: Text('Video')),
                  DropdownMenuItem(value: 'audio', child: Text('Audio')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => type = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                final error = await ref
                    .read(libraryProvider.notifier)
                    .createLibrary(name: name, type: type);

                if (error != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final notifier = ref.read(libraryProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Libraries')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'library_fab',
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        data: (libraries) {
          if (libraries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_music_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No libraries yet', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Library'),
                  ),
                ],
              ),
            );
          }
          return _buildGroupedList(libraries, notifier);
        },
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
    required this.onDelete,
  });

  final MediaLibrary library;
  final bool isScanning;
  final VoidCallback onScan;
  final VoidCallback onDelete;

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
              if (isScanning) ...[
                const SizedBox(height: 8),
                _ScanStatusBar(scanStatus: scanStatusAsync),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
                tooltip: 'Delete library',
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
