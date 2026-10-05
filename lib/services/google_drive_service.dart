import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

class GoogleDriveService {
  static final Logger _logger = Logger('GoogleDriveService');

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.readonly',
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // ============================================================
  // GET DRIVE API
  // ============================================================

  Future<drive.DriveApi?> getDriveApi({
    bool requestPermission = true,
  }) async {
    try {
      final GoogleSignInAccount user =
          await _googleSignIn.authenticate();

      _logger.info(
        'Google account authenticated: ${user.email}',
      );

      GoogleSignInClientAuthorization? authorization =
          await user.authorizationClient
              .authorizationForScopes(_scopes);

      if (authorization == null) {
        if (!requestPermission) {
          _logger.warning(
            'Google Drive permission has not been granted.',
          );
          return null;
        }

        authorization =
            await user.authorizationClient.authorizeScopes(
          _scopes,
        );
      }

      final Map<String, String>? headers =
          await user.authorizationClient
              .authorizationHeaders(_scopes);

      if (headers == null || headers.isEmpty) {
        throw Exception(
          'Google authorization headers are empty.',
        );
      }

      final GoogleAuthClient client =
          GoogleAuthClient(headers);

      return drive.DriveApi(client);
    } catch (error, stackTrace) {
      _logger.severe(
        'Google Drive API error: $error',
        error,
        stackTrace,
      );

      return null;
    }
  }

  // ============================================================
  // GET MIME TYPE
  // ============================================================

  String _getVideoMimeType(String fileName) {
    final String name = fileName.toLowerCase();

    if (name.endsWith('.mp4')) {
      return 'video/mp4';
    }

    if (name.endsWith('.webm')) {
      return 'video/webm';
    }

    if (name.endsWith('.mov')) {
      return 'video/quicktime';
    }

    if (name.endsWith('.m4v')) {
      return 'video/x-m4v';
    }

    if (name.endsWith('.avi')) {
      return 'video/x-msvideo';
    }

    if (name.endsWith('.mkv')) {
      return 'video/x-matroska';
    }

    if (name.endsWith('.3gp')) {
      return 'video/3gpp';
    }

    return 'video/mp4';
  }

  // ============================================================
  // MAKE FILE PUBLIC
  // ============================================================

  Future<bool> _makeFilePublic(
    drive.DriveApi driveApi,
    String fileId,
  ) async {
    try {
      await driveApi.permissions.create(
        drive.Permission()
          ..type = 'anyone'
          ..role = 'reader'
          ..allowFileDiscovery = false,
        fileId,
      );

      _logger.info(
        'Public permission created for: $fileId',
      );

      return true;
    } catch (error) {
      _logger.warning(
        'Could not create public permission: $error',
      );

      return false;
    }
  }

  // ============================================================
  // VERIFY PUBLIC PERMISSION
  // ============================================================

  Future<bool> _verifyPublicPermission(
    drive.DriveApi driveApi,
    String fileId,
  ) async {
    try {
      final drive.PermissionList permissions =
          await driveApi.permissions.list(fileId);

      final permissionsList =
          permissions.permissions ?? [];

      for (final permission in permissionsList) {
        if (permission.type == 'anyone' &&
            permission.role == 'reader') {
          _logger.info(
            'Verified: file is publicly readable.',
          );

          return true;
        }
      }

      _logger.warning(
        'File does not have anyone/reader permission.',
      );

      return false;
    } catch (error) {
      _logger.warning(
        'Could not verify public permission: $error',
      );

      return false;
    }
  }

  // ============================================================
  // CREATE VIDEO URL
  // ============================================================

  String _createVideoUrl(String fileId) {
    return 'https://drive.google.com/uc'
        '?export=download'
        '&id=$fileId';
  }

  // ============================================================
  // UPLOAD VIDEO
  // ============================================================

  Future<VideoUploadResult?> uploadVideo(
    File videoFile,
  ) async {
    try {
      final drive.DriveApi? driveApi =
          await getDriveApi(
        requestPermission: true,
      );

      if (driveApi == null) {
        _logger.warning(
          'Drive API is not available.',
        );
        return null;
      }

      // ----------------------------------------------------------
      // FILE NAME
      // ----------------------------------------------------------

      final String fileName =
          videoFile.path
              .split(Platform.pathSeparator)
              .last;

      _logger.info(
        'Uploading video: $fileName',
      );

      // ----------------------------------------------------------
      // MIME TYPE
      // ----------------------------------------------------------

      final String mimeType =
          _getVideoMimeType(fileName);

      _logger.info(
        'Detected MIME type: $mimeType',
      );

      // ----------------------------------------------------------
      // FILE METADATA
      // ----------------------------------------------------------

      final drive.File fileMetadata =
          drive.File()
            ..name = fileName
            ..mimeType = mimeType;

      // ----------------------------------------------------------
      // VIDEO DATA
      // ----------------------------------------------------------

      final drive.Media media = drive.Media(
        videoFile.openRead(),
        await videoFile.length(),
      );

      // ----------------------------------------------------------
      // UPLOAD
      // ----------------------------------------------------------

      final drive.File uploadedFile =
          await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
        $fields: 'id,name,mimeType,size,webContentLink,webViewLink',
      );

      final String? fileId =
          uploadedFile.id;

      if (fileId == null || fileId.isEmpty) {
        throw Exception(
          'Google Drive did not return file ID.',
        );
      }

      _logger.info(
        'Video uploaded successfully.',
      );

      _logger.info(
        'File ID: $fileId',
      );

      _logger.info(
        'MIME type: ${uploadedFile.mimeType}',
      );

      // ----------------------------------------------------------
      // PUBLIC PERMISSION
      // ----------------------------------------------------------

      final bool publicCreated =
          await _makeFilePublic(
        driveApi,
        fileId,
      );

      if (!publicCreated) {
        throw Exception(
          'Unable to make video public.',
        );
      }

      // ----------------------------------------------------------
      // VERIFY PUBLIC ACCESS
      // ----------------------------------------------------------

      final bool publicVerified =
          await _verifyPublicPermission(
        driveApi,
        fileId,
      );

      if (!publicVerified) {
        throw Exception(
          'Video is not publicly accessible.',
        );
      }

      // ----------------------------------------------------------
      // VIDEO URL
      // ----------------------------------------------------------

      final String videoUrl =
          _createVideoUrl(fileId);

      _logger.info(
        'Video URL: $videoUrl',
      );

      // ----------------------------------------------------------
      // RETURN
      // ----------------------------------------------------------

      return VideoUploadResult(
        fileId: fileId,
        fileName: fileName,
        videoUrl: videoUrl,
      );
    } catch (error, stackTrace) {
      _logger.severe(
        'Video upload failed: $error',
        error,
        stackTrace,
      );

      return null;
    }
  }

  // ============================================================
  // UPLOAD THUMBNAIL
  // ============================================================

  Future<VideoUploadResult?> uploadThumbnail(
    File thumbnailFile,
  ) async {
    try {
      final drive.DriveApi? driveApi =
          await getDriveApi(
        requestPermission: true,
      );

      if (driveApi == null) {
        return null;
      }

      final String fileName =
          thumbnailFile.path
              .split(Platform.pathSeparator)
              .last;

      _logger.info(
        'Uploading thumbnail: $fileName',
      );

      // ----------------------------------------------------------
      // MIME TYPE
      // ----------------------------------------------------------

      final String lowerName =
          fileName.toLowerCase();

      String mimeType = 'image/jpeg';

      if (lowerName.endsWith('.png')) {
        mimeType = 'image/png';
      } else if (lowerName.endsWith('.webp')) {
        mimeType = 'image/webp';
      } else if (lowerName.endsWith('.gif')) {
        mimeType = 'image/gif';
      }

      // ----------------------------------------------------------
      // METADATA
      // ----------------------------------------------------------

      final drive.File fileMetadata =
          drive.File()
            ..name = fileName
            ..mimeType = mimeType;

      // ----------------------------------------------------------
      // DATA
      // ----------------------------------------------------------

      final drive.Media media = drive.Media(
        thumbnailFile.openRead(),
        await thumbnailFile.length(),
      );

      // ----------------------------------------------------------
      // UPLOAD
      // ----------------------------------------------------------

      final drive.File uploadedFile =
          await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
        $fields: 'id,name,mimeType,size,webContentLink,webViewLink',
      );

      final String? fileId =
          uploadedFile.id;

      if (fileId == null || fileId.isEmpty) {
        throw Exception(
          'Google Drive did not return thumbnail ID.',
        );
      }

      _logger.info(
        'Thumbnail uploaded: $fileId',
      );

      // ----------------------------------------------------------
      // PUBLIC PERMISSION
      // ----------------------------------------------------------

      final bool publicCreated =
          await _makeFilePublic(
        driveApi,
        fileId,
      );

      if (!publicCreated) {
        throw Exception(
          'Unable to make thumbnail public.',
        );
      }

      final bool publicVerified =
          await _verifyPublicPermission(
        driveApi,
        fileId,
      );

      if (!publicVerified) {
        throw Exception(
          'Thumbnail is not publicly accessible.',
        );
      }

      // ----------------------------------------------------------
      // THUMBNAIL URL
      // ----------------------------------------------------------

      final String thumbnailUrl =
          _createVideoUrl(fileId);

      _logger.info(
        'Thumbnail URL: $thumbnailUrl',
      );

      return VideoUploadResult(
        fileId: fileId,
        fileName: fileName,
        videoUrl: thumbnailUrl,
      );
    } catch (error, stackTrace) {
      _logger.severe(
        'Thumbnail upload failed: $error',
        error,
        stackTrace,
      );

      return null;
    }
  }

  // ============================================================
  // GET DRIVE FILE
  // ============================================================

  Future<drive.File?> getFile(
    String fileId,
  ) async {
    try {
      final drive.DriveApi? driveApi =
          await getDriveApi(
        requestPermission: true,
      );

      if (driveApi == null) {
        return null;
      }

      final dynamic result =
          await driveApi.files.get(
        fileId,
        $fields:
            'id,name,mimeType,size,webContentLink,webViewLink',
      );

      if (result is! drive.File) {
        return null;
      }

      return result;
    } catch (error, stackTrace) {
      _logger.severe(
        'Unable to get Drive file: $error',
        error,
        stackTrace,
      );

      return null;
    }
  }

  // ============================================================
  // DELETE DRIVE FILE
  // ============================================================

  Future<bool> deleteFile(
    String fileId,
  ) async {
    try {
      final drive.DriveApi? driveApi =
          await getDriveApi(
        requestPermission: true,
      );

      if (driveApi == null) {
        return false;
      }

      await driveApi.files.delete(fileId);

      _logger.info(
        'Drive file deleted: $fileId',
      );

      return true;
    } catch (error, stackTrace) {
      _logger.severe(
        'Unable to delete Drive file: $error',
        error,
        stackTrace,
      );

      return false;
    }
  }
}

// ============================================================
// VIDEO UPLOAD RESULT
// ============================================================

class VideoUploadResult {
  final String fileId;
  final String fileName;
  final String videoUrl;

  VideoUploadResult({
    required this.fileId,
    required this.fileName,
    required this.videoUrl,
  });
}

// ============================================================
// GOOGLE AUTH HTTP CLIENT
// ============================================================

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> headers;

  final http.Client _client =
      http.Client();

  GoogleAuthClient(this.headers);

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
  ) {
    request.headers.addAll(headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}