import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class StorageService {
  // ============================================================================
  // CLOUDINARY CONFIGURATION - UPDATE WITH YOUR VALUES
  // ============================================================================
  static const String cloudinaryCloudName = 'dpqzzyfdk';
  // Get these from https://cloudinary.com/console/settings/upload
  static const String profileUploadPreset = 'libretrack_profile_uploads';
  static const String bookCoverUploadPreset = 'libretrack_book_covers';
  static const String pdfUploadPreset = 'libretrack_pdf_uploads';

  // ============================================================================
  // UPLOAD PROFILE PICTURE (for user registration/profile update)
  // ============================================================================
  Future<String> uploadProfilePicture(File imageFile) async {
    return _uploadFile(
      imageFile,
      'image/upload',
      profileUploadPreset,
      'profile_pictures',
    );
  }

  // ============================================================================
  // UPLOAD BOOK COVER (for librarian book management)
  // ============================================================================
  Future<String> uploadBookCover(File imageFile) async {
    return _uploadFile(
      imageFile,
      'image/upload',
      bookCoverUploadPreset,
      'book_covers',
    );
  }

  // ============================================================================
  // UPLOAD PDF (for school modules or book PDFs)
  // ============================================================================
  Future<String> uploadPDF(File pdfFile) async {
    return _uploadFile(pdfFile, 'raw/upload', pdfUploadPreset, 'pdf_files');
  }

  // ============================================================================
  // GENERIC FILE UPLOAD (handles images and PDFs)
  // ============================================================================
  Future<String> _uploadFile(
    File file,
    String resourceType, // 'image/upload' or 'raw/upload'
    String uploadPreset,
    String folderPath,
  ) async {
    try {
      // Validate file exists
      if (!await file.exists()) {
        throw Exception('File does not exist: ${file.path}');
      }

      // Validate file size (100MB max)
      final fileSizeInBytes = await file.length();
      const maxSizeInBytes = 100 * 1024 * 1024; // 100MB
      if (fileSizeInBytes > maxSizeInBytes) {
        throw Exception(
          'File too large: ${(fileSizeInBytes / 1024 / 1024).toStringAsFixed(2)}MB (max 100MB)',
        );
      }

      // Build upload URL
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/$resourceType',
      );

      var response = await _sendMultipartUpload(
        uri: uri,
        file: file,
        uploadPreset: uploadPreset,
        folder: 'libretrack/$folderPath',
      );

      if (_shouldRetryWithoutFolder(response)) {
        debugPrint(
          '[StorageService] Upload preset rejected folder. Retrying without folder.',
        );
        response = await _sendMultipartUpload(
          uri: uri,
          file: file,
          uploadPreset: uploadPreset,
        );
      }

      // Handle response
      if (response.statusCode == 200) {
        final responseData = _decodeResponse(response.body);
        final secureUrl = responseData['secure_url'];
        final publicId = responseData['public_id'];

        if (secureUrl is! String || secureUrl.isEmpty) {
          throw Exception('Upload completed, but no file URL was returned.');
        }

        debugPrint('[StorageService] Upload successful');
        debugPrint('[StorageService] Public ID: $publicId');

        return secureUrl;
      } else {
        throw Exception(_cloudinaryErrorMessage(response));
      }
    } catch (e) {
      debugPrint('[StorageService] Upload error: $e');
      rethrow;
    }
  }

  Future<http.Response> _sendMultipartUpload({
    required Uri uri,
    required File file,
    required String uploadPreset,
    String? folder,
  }) async {
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset;

    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
    );
    return http.Response.fromStream(streamedResponse);
  }

  bool _shouldRetryWithoutFolder(http.Response response) {
    if (response.statusCode < 400) {
      return false;
    }

    final message = _cloudinaryErrorMessage(response).toLowerCase();
    return message.contains('folder') ||
        message.contains('public id') ||
        message.contains('not allowed') ||
        message.contains('disallowed');
  }

  String _cloudinaryErrorMessage(http.Response response) {
    final errorBody = _decodeResponse(response.body);
    final error = errorBody['error'];
    final message = error is Map<String, dynamic> ? error['message'] : null;

    if (message is String && message.isNotEmpty) {
      return 'Cloudinary upload failed (${response.statusCode}): $message';
    }

    return 'Cloudinary upload failed (${response.statusCode}): ${response.body}';
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // The caller includes the raw response body in the thrown message.
    }

    return <String, dynamic>{};
  }

  // ============================================================================
  // DELETE FILE FROM CLOUDINARY (Backend only for security)
  // ============================================================================
  // NOTE: File deletion requires your API Secret key, which should NEVER
  // be exposed in client-side code. Instead:
  //
  // 1. Create a backend Cloud Function (Firebase, AWS Lambda, etc.)
  // 2. Have the app call: `/api/delete-file?publicId=xyz`
  // 3. The backend handles deletion securely
  //
  // Example backend endpoint (Node.js/Firebase Cloud Function):
  // ```
  // const cloudinary = require('cloudinary').v2;
  // exports.deleteFile = functions.https.onRequest(async (req, res) => {
  //   const { publicId } = req.query;
  //   try {
  //     const result = await cloudinary.uploader.destroy(publicId);
  //     res.json({ success: true, result });
  //   } catch (error) {
  //     res.status(400).json({ error: error.message });
  //   }
  // });
  // ```
}
