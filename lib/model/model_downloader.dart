import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../worker/server_config.dart';
import 'database_helper.dart';
import 'ml.dart';

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

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      final errorBody = _safeDecode(response.bodyBytes);
      throw HttpException(
        '모델 다운로드 실패: HTTP ${response.statusCode} '
        '${response.reasonPhrase ?? ''} $errorBody',
        uri: uri,
      );
    }

    final headerVersion = response.headers['x-model-version'];
    final headerFilename = response.headers['x-model-filename'];
    if ((headerVersion == null || headerVersion.isEmpty) &&
        versionOverride == null) {
      throw const HttpException(
        '모델 다운로드 실패: X-Model-Version 헤더가 존재하지 않습니다',
      );
    }
    if ((headerFilename == null || headerFilename.isEmpty) &&
        (filenameOverride == null || filenameOverride.isEmpty)) {
      throw const HttpException(
        '모델 다운로드 실패: X-Model-Filename 헤더가 존재하지 않습니다',
      );
    }

    final remoteVersion = headerVersion ?? versionOverride?.toString() ?? '0';
    final remoteFilename =
        headerFilename ?? filenameOverride ?? _defaultFilename;
    print(
      '📥 [ModelDownloader] 수신 완료 version=$remoteVersion file=$remoteFilename '
      'size=${response.bodyBytes.length} bytes',
    );

    final db = DatabaseHelper.instance;
    final localInfo = await db.getModelVersion(_modelType);
    final localVersion = localInfo?['version'] as String? ?? '0';
    final localPath = localInfo?['path'] as String?;

    final localFileExists = localPath != null && await File(localPath).exists();

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
}
