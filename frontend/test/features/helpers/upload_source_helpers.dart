import 'dart:io';

import 'package:flux_media_server/features/media/domain/models/upload_source.dart';

/// Источник файла для тестов: имя, путь и пустой поток.
///
/// Содержимое в тестах не нужно: хешер и загрузка подменяются фейками.
UploadSource fakeUploadSource({
  String name = 'file.mp3',
  int length = 100,
}) => UploadSource(
  path: '/tmp/$name',
  name: name,
  openRead: () => const Stream<List<int>>.empty(),
);

/// Источник из реального локального файла — для тестов, где нужен
/// настоящий поток данных (multipart-загрузка проверяет тело запроса).
UploadSource fileUploadSource(File file, {String? name}) => UploadSource(
  path: file.path,
  name: name ?? file.path.split('/').last,
  openRead: file.openRead,
);
