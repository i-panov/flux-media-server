import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/media/data/repositories/media_repository_impl.dart';
import 'package:flux_media_server/features/media/domain/models/metadata_edit.dart';

void main() {
  group('editToJson source_url mapping', () {
    test('non-empty URL is sent', () {
      final json = MediaRepositoryImpl.editToJson(
        const MetadataEdit(
          title: 'T',
          artists: [],
          sourceUrl: 'https://www.youtube.com/watch?v=abc',
        ),
      );

      expect(json['source_url'], 'https://www.youtube.com/watch?v=abc');
    });

    test('empty string is sent to clear the link, not dropped', () {
      final json = MediaRepositoryImpl.editToJson(
        const MetadataEdit(title: 'T', artists: [], sourceUrl: ''),
      );

      expect(json, contains('source_url'));
      expect(json['source_url'], '');
    });

    test('null leaves the key out (link untouched)', () {
      final json = MediaRepositoryImpl.editToJson(
        const MetadataEdit(title: 'T', artists: []),
      );

      expect(json, isNot(contains('source_url')));
    });

    test('other fields map as before', () {
      final json = MediaRepositoryImpl.editToJson(
        const MetadataEdit(title: 'T', artists: ['A'], album: 'Al', year: 2001),
      );

      expect(json['title'], 'T');
      expect(json['artists'], ['A']);
      expect(json['album'], 'Al');
      expect(json['year'], 2001);
      expect(json, isNot(contains('genre')));
      expect(json, isNot(contains('description')));
    });
  });
}
