/// HTTP 워커
/// 큐에서 작업을 가져와서 서버로 전송하는 워커입니다.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'measurement_task.dart';
import 'queue_manager.dart';
import 'server_config.dart';
import '../model/database_helper.dart';
import '../model/model_downloader.dart';

class HttpWorker {
  final QueueManager _queueManager;
  final ServerConfig _serverConfig;
  bool _isRunning = false;
  final int _workerId;

  HttpWorker(this._queueManager, this._serverConfig, {int? workerId})
      : _workerId = workerId ?? DateTime.now().millisecondsSinceEpoch;

  /// 워커 시작
  Future<void> start() async {
    _isRunning = true;
    print('🚀 HTTP Worker $_workerId 시작');

    while (_isRunning) {
      try {
        // 큐에서 작업 가져오기
        final task = await _queueManager.getNextTask();

        if (task == null) {
          // 큐가 비어있으면 잠시 대기
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        print('🔧 Worker $_workerId 작업 처리 시작: ${task.taskId}');
        // 작업 처리
        await _processTask(task);
      } catch (e) {
        print('❌ Worker $_workerId 오류: $e');
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    print('🛑 HTTP Worker $_workerId 종료');
  }

  /// 워커 중지
  void stop() {
    _isRunning = false;
    print('⏹️ HTTP Worker $_workerId 중지 요청');
  }

  /// 작업 처리
  Future<void> _processTask(MeasurementTask task) async {
    print('🔧 작업 처리 시작: ${task.taskId}');

    try {
      // 작업 타입에 따른 처리
      final taskType = task.data['type'] as String? ?? '';

      switch (taskType) {
        case 'dataset_upload':
          await _processDatasetUpload(task);
          break;
        case 'upload_state':
          await _processUploadState(task);
          break;
        case 'model_download':
          await _processModelDownload(task);
          break;
        default:
          throw Exception('알 수 없는 작업 타입: $taskType');
      }
    } catch (e) {
      final errorMessage = e.toString();
      print('❌ 작업 처리 실패: ${task.taskId} - $errorMessage');
      await _queueManager.failTask(task.taskId, errorMessage);
    }
  }

  /// 데이터셋 업로드 처리
  Future<void> _processDatasetUpload(MeasurementTask task) async {
    final dataset = task.data['dataset'] as Map<String, dynamic>;
    final measurementData = Map<String, dynamic>.from(dataset);

    final sessionId = measurementData['session_id'] as String? ?? '';
    final userId = await DatabaseHelper.resolveUserId(
      measurementData['user_id'] as String?,
    );
    measurementData['user_id'] = userId;

    // 윈도우 데이터 확보 (큐에 들어있는 값이 없으면 DB에서 조회)
    List<Map<String, dynamic>> windows = [];
    if (measurementData['windows'] is List) {
      windows = (measurementData['windows'] as List)
          .whereType<Map>()
          .map((w) => Map<String, dynamic>.from(w))
          .toList();
    }
    if (windows.isEmpty && sessionId.isNotEmpty) {
      windows = await DatabaseHelper.instance.getWindowsBySession(
        sessionId,
        userId: userId,
        onlyUnsynced: true,
      );
    } else {
      windows = windows.where((w) {
        final synced = w['synced'];
        if (synced == null) return true;
        if (synced is int) return synced == 0;
        if (synced is bool) return !synced;
        return true;
      }).toList();
    }

    if (windows.isEmpty) {
      print('ℹ️ 이미 업로드된 세션이거나 전송할 윈도우가 없습니다: $sessionId');
      await _queueManager.completeTask(
        task.taskId,
        result: {
          'skipped': true,
          'reason': 'already_synced',
        },
      );
      return;
    }

    // DatasetItem 스펙에 맞게 변환
    final batchData = windows.map((window) {
      final windowMap = Map<String, dynamic>.from(window);
      windowMap['user_id'] = userId;
      windowMap['session_id'] = sessionId;

      // user_emb JSON 문자열 → 리스트
      final emb = windowMap['user_emb'];
      if (emb is String && emb.isNotEmpty) {
        try {
          final decoded = jsonDecode(emb) as List<dynamic>;
          windowMap['user_emb'] =
              decoded.map((e) => (e as num).toDouble()).toList();
        } catch (_) {
          windowMap['user_emb'] = null;
        }
      }
      if (windowMap['user_emb'] == null) {
        final sessionEmb = measurementData['user_emb'];
        if (sessionEmb is String && sessionEmb.isNotEmpty) {
          try {
            final decoded = jsonDecode(sessionEmb) as List<dynamic>;
            windowMap['user_emb'] =
                decoded.map((e) => (e as num).toDouble()).toList();
          } catch (_) {
            windowMap['user_emb'] = null;
          }
        } else if (sessionEmb is List) {
          windowMap['user_emb'] =
              sessionEmb.map((e) => (e as num).toDouble()).toList();
        }
        if (windowMap['user_emb'] == null) {
          windowMap['user_emb'] = List<double>.filled(12, 0.0);
        }
      }

      // 기본값 보정
      windowMap['quality_flag'] ??= 1;
      windowMap['window_size_ms'] ??= 2000;
      windowMap['overlap_rate'] ??= 0.5;
      windowMap['rms_base'] ??=
          (measurementData['rms_base'] as num?)?.toDouble() ?? 0.0;
      windowMap['freq_base'] ??=
          (measurementData['freq_base'] as num?)?.toDouble() ?? 0.0;

      const doubleFields = [
        'acc_x_mean',
        'acc_y_mean',
        'acc_z_mean',
        'gyro_x_mean',
        'gyro_y_mean',
        'gyro_z_mean',
        'linacc_x_mean',
        'linacc_y_mean',
        'linacc_z_mean',
        'gravity_x_mean',
        'gravity_y_mean',
        'gravity_z_mean',
        'acc_x_std',
        'acc_y_std',
        'acc_z_std',
        'gyro_x_std',
        'gyro_y_std',
        'gyro_z_std',
        'rms_acc',
        'rms_gyro',
        'mean_freq_acc',
        'mean_freq_gyro',
        'entropy_acc',
        'entropy_gyro',
        'jerk_mean',
        'jerk_std',
        'stability_index',
        'overlap_rate',
        'fatigue_prev',
        'fatigue',
        'rms_base',
        'freq_base',
      ];
      for (final key in doubleFields) {
        windowMap[key] = (windowMap[key] as num?)?.toDouble() ?? 0.0;
      }

      const intFields = ['fatigue_level', 'quality_flag', 'window_size_ms'];
      for (final key in intFields) {
        windowMap[key] = (windowMap[key] as num?)?.toInt() ?? 0;
      }
      const longFields = ['window_id', 'window_start_ms', 'window_end_ms'];
      for (final key in longFields) {
        windowMap[key] = (windowMap[key] as num?)?.toInt() ?? 0;
      }
      final timestampUtc = windowMap['timestamp_utc'];
      if (timestampUtc == null) {
        windowMap['timestamp_utc'] = DateTime.now().toUtc().toIso8601String();
      } else if (timestampUtc is! String) {
        windowMap['timestamp_utc'] = timestampUtc.toString();
      }

      windowMap.remove('synced');
      windowMap.remove('mode');
      windowMap.remove('timestamp');
      windowMap.remove('variance');
      windowMap.remove('mean_power_freq');
      windowMap.remove('median_freq');
      windowMap.remove('sample_count');
      windowMap.remove('rms');
      windowMap.remove('freq');
      windowMap.remove('fatigue_personal');
      windowMap.removeWhere((key, value) => value == null);
      return windowMap;
    }).toList();

    final payload = {
      'batch_data': batchData,
    };

    // API로 전송
    final response = await _sendDataset(payload);

    if (response['success']) {
      // SQLite에서 synced 상태 업데이트
      await _markSingleAsSynced(measurementData);
      await _queueManager.completeTask(task.taskId, result: response);
    } else {
      throw Exception('API 전송 실패: ${response['error']}');
    }
  }

  /// 데이터셋을 서버로 전송
  Future<Map<String, dynamic>> _sendDataset(
    Map<String, dynamic> dataset,
  ) async {
    try {
      final url = Uri.parse(_serverConfig.uploadDatasetUrl);
      print('🌐 서버 전송 URL: $url');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(dataset),
          )
          .timeout(Duration(seconds: _serverConfig.timeoutSeconds));

      print('📡 서버 응답: ${response.statusCode}');
      print('📄 응답 내용: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'data': responseData,
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      print('❌ 네트워크 에러: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 사용자 상태 업로드 처리
  Future<void> _processUploadState(MeasurementTask task) async {
    print('📤 사용자 상태 업로드 처리 시작: ${task.taskId}');

    try {
      // SQLite에서 사용자 상태 조회
      final userState =
          await DatabaseHelper.instance.getUserState(userId: task.userId);
      if (userState == null) {
        throw Exception('사용자 상태를 찾을 수 없습니다');
      }

      // 사용자 임베딩 조회
      final userEmb =
          await DatabaseHelper.instance.getUserEmbedding(userId: task.userId);

      // 업로드할 데이터 준비
      final uploadData = {
        'user_id': task.userId,
        'rms_base': userState['rms_base'],
        'freq_base': userState['freq_base'],
        'user_emb': userEmb,
        'model_version': userState['model_version'],
        'last_sync': DateTime.now().toIso8601String(),
      };

      // 서버로 업로드
      final result = await _sendUserState(uploadData);

      if (result['success'] == true) {
        // 동기화 이력 기록
        await DatabaseHelper.instance.insertSyncHistory(
          userId: task.userId,
          syncType: 'upload_state',
          status: 'success',
        );

        await _queueManager.completeTask(task.taskId, result: result);
        print('✅ 사용자 상태 업로드 완료: ${task.taskId}');
      } else {
        throw Exception(result['error'] ?? '업로드 실패');
      }
    } catch (e) {
      print('❌ 사용자 상태 업로드 실패: $e');

      // 실패 이력 기록
      await DatabaseHelper.instance.insertSyncHistory(
        userId: task.userId,
        syncType: 'upload_state',
        status: 'failure',
      );

      rethrow;
    }
  }

  /// 사용자 상태를 서버로 전송
  Future<Map<String, dynamic>> _sendUserState(
    Map<String, dynamic> userStateData,
  ) async {
    try {
      final url = Uri.parse(_serverConfig.getApiUrl('/upload_state'));
      print('🌐 사용자 상태 전송 URL: $url');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(userStateData),
          )
          .timeout(Duration(seconds: _serverConfig.timeoutSeconds));

      print('📡 서버 응답: ${response.statusCode}');
      print('📄 응답 내용: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'data': responseData,
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      print('❌ 네트워크 에러: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<void> _processModelDownload(MeasurementTask task) async {
    print('🧠 모델 다운로드 작업 처리 시작: ${task.taskId}');
    final force = task.data['force'] == true;
    final version = (task.data['version'] as num?)?.toInt();

    try {
      await ModelDownloader.instance
          .downloadLatest(force: force, versionOverride: version);

      await _queueManager.completeTask(
        task.taskId,
        result: {'success': true},
      );
      print('✅ 모델 다운로드 작업 완료: ${task.taskId}');
    } catch (e) {
      print('❌ 모델 다운로드 작업 실패: ${task.taskId} - $e');
      await _queueManager.failTask(task.taskId, e.toString());
    }
  }

  /// 단일 측정 데이터를 synced로 마킹
  Future<void> _markSingleAsSynced(Map<String, dynamic> measurementData) async {
    try {
      final sessionId = measurementData['session_id'] as String;
      final userId = await DatabaseHelper.resolveUserId(
        measurementData['user_id'] as String?,
      );
      await DatabaseHelper.instance.markLogsAsSynced(
        [sessionId],
        userId: userId,
      );
      print('✅ 세션 데이터 synced 상태로 업데이트 완료: $sessionId');
    } catch (e) {
      print('⚠️ synced 상태 업데이트 실패: $e');
    }
  }

  /// 서버 연결 상태 확인
  Future<bool> checkServerHealth() async {
    try {
      final url = Uri.parse(_serverConfig.apiBaseUrl);

      final response = await http.get(url).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        // 서버 상태 정상 로그 제거 (너무 자주 출력됨)
        return true;
      }

      return false;
    } catch (e) {
      if (_serverConfig.enableLogging) {
        print('❌ 서버 연결 확인 실패: $e');
      }
      return false;
    }
  }

  /// 워커 상태 조회
  Map<String, dynamic> getWorkerStatus() {
    return {
      'worker_id': _workerId,
      'is_running': _isRunning,
      'server_url': _serverConfig.apiBaseUrl,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
