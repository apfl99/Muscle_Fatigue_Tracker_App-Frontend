/// HTTP 워커
/// 큐에서 작업을 가져와서 서버로 전송하는 워커입니다.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'measurement_task.dart';
import 'queue_manager.dart';
import 'server_config.dart';
import '../model/database_helper.dart';

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

    // batch_data에 measurement_count 추가 (새로운 맵 생성)
    final originalBatchData = dataset['batch_data'] as List<dynamic>;
    final newBatchData = <Map<String, dynamic>>[];

    for (int i = 0; i < originalBatchData.length; i++) {
      final item = Map<String, dynamic>.from(originalBatchData[i]);
      item['measurement_count'] = i + 1;

      // windows 필드 정리 (null이거나 빈 리스트인 경우 빈 리스트로 설정)
      if (item['windows'] == null ||
          item['windows'] is! List ||
          (item['windows'] as List).isEmpty) {
        item['windows'] = <Map<String, dynamic>>[];
      }

      newBatchData.add(item);
    }

    dataset['batch_data'] = newBatchData;
    print('📊 배치 데이터에 measurement_count 추가 완료');

    // API로 전송
    final response = await _sendDataset(dataset);

    if (response['success']) {
      // SQLite에서 synced 상태 업데이트
      await _markBatchAsSynced(dataset);
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

  /// 배치 데이터를 synced로 마킹
  Future<void> _markBatchAsSynced(Map<String, dynamic> dataset) async {
    try {
      final batchData = dataset['batch_data'] as List<dynamic>;
      final sessionIds =
          batchData.map((item) => item['session_id'] as String).toList();

      await DatabaseHelper.instance.markLogsAsSynced(sessionIds);
      print('✅ ${sessionIds.length}개 세션 데이터 synced 상태로 업데이트 완료');
    } catch (e) {
      print('⚠️ synced 상태 업데이트 실패: $e');
    }
  }

  /// 서버 연결 상태 확인
  Future<bool> checkServerHealth() async {
    try {
      final url = Uri.parse(_serverConfig.baseUrl);

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
      'server_url': _serverConfig.baseUrl,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
