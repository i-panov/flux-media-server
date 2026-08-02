import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/shared/models/scan_status.dart';

void main() {
  group('ScanStatus', () {
    test('fromJson parses running scan', () {
      final json = {
        'library_id': 1,
        'running': true,
        'started_at': '2024-01-15T10:30:00Z',
      };

      final status = ScanStatus.fromJson(json);

      expect(status.libraryId, 1);
      expect(status.running, isTrue);
      expect(status.startedAt, isNotNull);
      expect(status.lastError, isNull);
    });

    test('fromJson parses completed scan with error', () {
      final json = {
        'library_id': 2,
        'running': false,
        'started_at': null,
        'last_error': 'Disk full',
      };

      final status = ScanStatus.fromJson(json);

      expect(status.libraryId, 2);
      expect(status.running, isFalse);
      expect(status.startedAt, isNull);
      expect(status.lastError, 'Disk full');
    });

    test('fromJson parses minimal scan', () {
      final json = {
        'library_id': 3,
        'running': false,
      };

      final status = ScanStatus.fromJson(json);

      expect(status.libraryId, 3);
      expect(status.running, isFalse);
      expect(status.startedAt, isNull);
      expect(status.lastError, isNull);
    });

    test('equality works', () {
      const a = ScanStatus(
        libraryId: 1,
        running: true,
        startedAt: null,
        lastError: null,
      );
      const b = ScanStatus(
        libraryId: 1,
        running: true,
        startedAt: null,
        lastError: null,
      );
      expect(a, equals(b));
    });

    test('inequality for different library ids', () {
      const a = ScanStatus(libraryId: 1, running: true, startedAt: null, lastError: null);
      const b = ScanStatus(libraryId: 2, running: true, startedAt: null, lastError: null);
      expect(a, isNot(equals(b)));
    });
  });
}
