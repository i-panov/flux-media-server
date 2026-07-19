import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

/// Provides a configured Dio instance for file uploads.
final uploadDioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final token = ref.watch(settingsProvider).settings.authToken;
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    },
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
  ));
  return dio;
});

/// Result of a file upload.
class UploadResult {
  const UploadResult({required this.success, this.mediaId, this.message});

  final bool success;
  final int? mediaId;
  final String? message;
}

/// Service for uploading media files to the server.
class UploadService {
  UploadService(this._dio);

  final Dio _dio;

  /// Uploads a file to the specified library.
  /// Returns an [UploadResult] with the created media info.
  Future<UploadResult> uploadFile({
    required File file,
    required int libraryId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      'library_id': libraryId,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
      ),
    });

    try {
      final response = await _dio.post(
        '/media/upload',
        data: formData,
        onSendProgress: onProgress,
      );

      if (response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        return UploadResult(
          success: true,
          mediaId: data['id'] as int?,
          message: data['message'] as String?,
        );
      }

      return UploadResult(
        success: false,
        message: response.data['error']?.toString() ?? 'Upload failed',
      );
    } on DioException catch (e) {
      return UploadResult(
        success: false,
        message: e.message ?? 'Upload failed',
      );
    }
  }
}

/// Provider for UploadService.
final uploadServiceProvider = Provider<UploadService>((ref) {
  return UploadService(ref.watch(uploadDioProvider));
});
