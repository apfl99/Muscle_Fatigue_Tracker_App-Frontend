import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';

import '../worker/server_config.dart';
import 'database_helper.dart';
import 'ml.dart';

void print(Object? message) => appLog(message);

class ModelDownloadException implements Exception {
  const ModelDownloadException(
    this.message, {
    this.uri,
    this.statusCode,
    this.retryable = true,
  });

  final String message;
  final Uri? uri;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() {
    final uriText = uri == null ? '' : ' uri=$uri';
    final codeText = statusCode == null ? '' : ' status=$statusCode';
    return 'ModelDownloadException($message$codeText$uriText, retryable=$retryable)';
  }
}

class ModelDownloader {
  ModelDownloader._internal();

  static final ModelDownloader instance = ModelDownloader._internal();

  static const String _modelType = 'E2E';
  static const String _defaultFilename = 'cnn_gru_fatigue.tflite';

  Future<void> downloadLatest({
    bool force = false,
    int? versionOverride,
    String? filenameOverride,
  }) async {
    final db = DatabaseHelper.instance;
    final localInfo = await db.getModelVersion(_modelType);
    final localVersion = localInfo?['version'] as String? ?? '0';
    final localPath = localInfo?['path'] as String?;
    final localFileExists = localPath != null && await File(localPath).exists();

    if (!force && localFileExists) {
      print(
        'ℹ️ [ModelDownloader] 로컬 모델 유지 '
        '(version=$localVersion, path=$localPath) - 원격 호출 생략',
      );
      return;
    }

    final config = await getServerConfig();
    final baseUri = Uri.parse(config.getModelUrl('/model'));
    final query = <String, String>{};
    if (versionOverride != null) {
      query['version'] = versionOverride.toString();
    }
    if (filenameOverride != null && filenameOverride.isNotEmpty) {
      query['filename'] = filenameOverride;
    }

    final uri =
        query.isEmpty ? baseUri : baseUri.replace(queryParameters: query);
    print('🌐 [ModelDownloader] 요청 → $uri (force=$force)');

    late final http.Response response;
    try {
      response = await http
          .get(uri)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      if (localFileExists) {
        print(
          '⚠️ [ModelDownloader] 요청 시간 초과 - '
          '로컬 모델(version=$localVersion)을 유지합니다',
        );
        return;
      }
      throw ModelDownloadException(
        '모델 다운로드 실패: 요청 시간 초과',
        uri: uri,
        retryable: true,
      );
    } on SocketException catch (error) {
      if (localFileExists) {
        print(
          '⚠️ [ModelDownloader] 네트워크 오류($error) - '
          '로컬 모델(version=$localVersion)을 유지합니다',
        );
        return;
      }
      throw ModelDownloadException(
        '모델 다운로드 실패: 네트워크 오류($error)',
        uri: uri,
        retryable: true,
      );
    } catch (error) {
      if (localFileExists) {
        print(
          '⚠️ [ModelDownloader] 원격 모델 요청 실패($error) - '
          '로컬 모델(version=$localVersion)을 유지합니다',
        );
        return;
      }
      throw ModelDownloadException(
        '모델 다운로드 실패: $error',
        uri: uri,
        retryable: true,
      );
    }

    if (response.statusCode != 200) {
      final errorBody = _summarizeErrorBody(response.bodyBytes);
      if (localFileExists) {
        print(
          '⚠️ [ModelDownloader] HTTP ${response.statusCode} '
          '${response.reasonPhrase ?? ''} - '
          '로컬 모델(version=$localVersion)을 유지합니다: $errorBody',
        );
        return;
      }
      throw ModelDownloadException(
        '모델 다운로드 실패: HTTP ${response.statusCode} '
        '${response.reasonPhrase ?? ''} $errorBody',
        uri: uri,
        statusCode: response.statusCode,
        retryable: _isRetryableStatus(response.statusCode),
      );
    }

    final headerVersion = response.headers['x-model-version'];
    final headerFilename = response.headers['x-model-filename'];
    if ((headerVersion == null || headerVersion.isEmpty) &&
        versionOverride == null) {
      if (localFileExists) {
        print(
          '⚠️ [ModelDownloader] X-Model-Version 헤더 누락 - '
          '로컬 모델(version=$localVersion)을 유지합니다',
        );
        return;
      }
      throw const ModelDownloadException(
        '모델 다운로드 실패: X-Model-Version 헤더가 존재하지 않습니다',
        retryable: false,
      );
    }
    if ((headerFilename == null || headerFilename.isEmpty) &&
        (filenameOverride == null || filenameOverride.isEmpty)) {
      if (localFileExists) {
        print(
          '⚠️ [ModelDownloader] X-Model-Filename 헤더 누락 - '
          '로컬 모델(version=$localVersion)을 유지합니다',
        );
        return;
      }
      throw const ModelDownloadException(
        '모델 다운로드 실패: X-Model-Filename 헤더가 존재하지 않습니다',
        retryable: false,
      );
    }

    final remoteVersion = headerVersion ?? versionOverride?.toString() ?? '0';
    final remoteFilename =
        headerFilename ?? filenameOverride ?? _defaultFilename;
    print(
      '📥 [ModelDownloader] 수신 완료 version=$remoteVersion file=$remoteFilename '
      'size=${response.bodyBytes.length} bytes',
    );

    if (!force &&
        !_isRemoteNewer(remoteVersion, localVersion) &&
        localFileExists) {
      print(
        'ℹ️ [ModelDownloader] 최신 버전 유지 (로컬 $localVersion, 원격 $remoteVersion)',
      );
      return;
    }

    final modelPath = await _saveModelFile(
      bytes: response.bodyBytes,
      filename: remoteFilename,
      version: remoteVersion,
    );

    await db.updateModelVersion(
      modelType: _modelType,
      version: remoteVersion,
      path: modelPath,
    );

    print(
      '✅ [ModelDownloader] DB 업데이트 완료 → version=$remoteVersion path=$modelPath',
    );

    try {
      await MLManager.instance.reloadEndToEndModel();
      print('🔄 [ModelDownloader] MLManager에 모델 리로드 요청 완료');
    } catch (e, stackTrace) {
      print('⚠️ [ModelDownloader] MLManager 리로드 실패: $e');
      print(stackTrace);
    }
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode >= 500 || statusCode == 429;
  }

  bool _isRemoteNewer(String remote, String local) {
    List<int> parseParts(String value) {
      return value
          .split('.')
          .map((part) => int.tryParse(part.trim()) ?? 0)
          .toList();
    }

    final remoteParts = parseParts(remote);
    final localParts = parseParts(local);
    final length = remoteParts.length > localParts.length
        ? remoteParts.length
        : localParts.length;

    for (int i = 0; i < length; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final l = i < localParts.length ? localParts[i] : 0;
      if (r != l) return r > l;
    }
    return false;
  }

  Future<String> _saveModelFile({
    required List<int> bytes,
    required String filename,
    required String version,
  }) async {
    if (bytes.isEmpty) {
      throw const HttpException('모델 다운로드 실패: 빈 파일을 수신했습니다');
    }

    final dir = await getApplicationSupportDirectory();
    final modelDir = Directory(p.join(dir.path, 'models', _modelType));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final filePath = p.join(modelDir.path, '${version}_$filename');
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    print('💾 [ModelDownloader] 파일 저장 완료 → $filePath');
    return filePath;
  }

  String _safeDecode(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return bytes.toString();
    }
  }

  String _summarizeErrorBody(List<int>? bytes) {
    final decoded = _safeDecode(bytes).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (decoded.isEmpty) {
      return '';
    }
    if (decoded.length <= 220) {
      return decoded;
    }
    return '${decoded.substring(0, 220)}...';
  }
}
