/// 워커 매니저
/// 여러 HTTP 워커들을 관리하고 큐 처리를 조율합니다.
library;

import 'dart:async';
import 'measurement_task.dart';
import 'queue_manager.dart';
import 'server_config.dart';
import 'http_worker.dart';

class WorkerManager {
  final QueueManager _queueManager;
  final ServerConfig _serverConfig;

  final List<HttpWorker> _workers = [];

  bool _isRunning = false;
  late final int _workerCount;
  Timer? _monitorTimer;
  Timer? _cleanupTimer;

  WorkerManager({
    required QueueManager queueManager,
    required ServerConfig serverConfig,
    int? workerCount,
  })  : _queueManager = queueManager,
        _serverConfig = serverConfig,
        _workerCount = workerCount ?? 1;

  /// 워커 매니저 시작
  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ Worker Manager가 이미 실행 중입니다');
      return;
    }

    print('🚀 Worker Manager 시작');
    _isRunning = true;

    // 기존 워커들 정리
    for (final worker in _workers) {
      worker.stop();
    }
    _workers.clear();

    // 큐 상태 복원
    await _queueManager.loadQueueState();

    // 처리 중인 작업들을 대기 상태로 복원 (앱 재시작 시)
    await _queueManager.resetProcessingTasks();

    // 워커들 시작
    for (int i = 0; i < _workerCount; i++) {
      final worker = HttpWorker(_queueManager, _serverConfig, workerId: i + 1);
      _workers.add(worker);

      // 워커를 백그라운드에서 실행
      Future.microtask(() async {
        await worker.start();
      });
    }

    // 모니터링 시작
    _startMonitoring();

    // 정리 작업 시작
    _startCleanup();

    print('✅ Worker Manager 시작 완료 (워커 ${_workers.length}개)');
  }

  /// 워커 매니저 중지
  Future<void> stop() async {
    if (!_isRunning) return;

    print('🛑 Worker Manager 중지 중');
    _isRunning = false;

    // 모니터링 중지
    _monitorTimer?.cancel();
    _cleanupTimer?.cancel();

    // 워커들 중지
    for (final worker in _workers) {
      worker.stop();
    }

    _workers.clear();

    // 큐 상태 저장
    await _queueManager.saveQueueState();

    print('✅ Worker Manager 중지 완료');
  }

  /// 데이터셋 업로드 작업을 큐에 추가
  Future<void> addDatasetUploadTask({
    required String userId,
    required String sessionId,
    required Map<String, dynamic> dataset,
    int priority = 1,
  }) async {
    final taskId =
        '${userId}_${sessionId}_${DateTime.now().millisecondsSinceEpoch}';

    final task = MeasurementTask(
      taskId: taskId,
      userId: userId,
      sessionId: sessionId,
      timestamp: DateTime.now(),
      data: {
        'dataset': dataset,
        'type': 'dataset_upload',
      },
      priority: priority,
    );

    await _queueManager.addTask(task);
    print('📝 데이터셋 업로드 작업 추가됨: $taskId');

    // 큐 상태 확인
    final stats = _queueManager.getQueueStats();
    print(
      '📊 현재 큐 상태: Pending=${stats['pending']}, Processing=${stats['processing']}',
    );
  }

  /// 큐 상태 조회
  Map<String, dynamic> getQueueStatus() {
    final queueStats = _queueManager.getQueueStats();
    final workerStatus = _workers.map((w) => w.getWorkerStatus()).toList();

    return {
      'queue_stats': queueStats,
      'worker_status': workerStatus,
      'manager_running': _isRunning,
      'worker_count': _workers.length,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 서버 연결 상태 확인
  Future<bool> checkServerHealth() async {
    if (_workers.isEmpty) return false;

    return await _workers.first.checkServerHealth();
  }

  /// 모니터링 시작
  void _startMonitoring() {
    _monitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // 큐 상태 로깅 (대기 중이거나 처리 중인 작업이 있을 때만)
        final stats = _queueManager.getQueueStats();
        if (stats['pending'] > 0 || stats['processing'] > 0) {
          print(
            '📊 큐 상태: Pending=${stats['pending']}, Processing=${stats['processing']}, Completed=${stats['completed']}, Failed=${stats['failed']}',
          );
        }

        // 서버 상태 확인 (문제가 있을 때만 로그)
        final isHealthy = await checkServerHealth();
        if (!isHealthy) {
          print('⚠️ 서버 연결 상태 불량');
        }
      } catch (e) {
        print('❌ 모니터링 오류: $e');
      }
    });
  }

  /// 정리 작업 시작
  void _startCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      try {
        // 완료된 작업들 정리
        await _queueManager.cleanupCompletedTasks(keepCount: 50);

        print('🧹 정기 정리 작업 완료');
      } catch (e) {
        print('❌ 정리 작업 오류: $e');
      }
    });
  }

  /// 사용자 상태 업로드 작업 추가
  Future<String> addUploadStateTask({
    required String userId,
    int priority = 1,
  }) async {
    return await _queueManager.addUploadStateTask(
      userId: userId,
      priority: priority,
    );
  }

  /// 큐 상태 출력
  void printStatus() {
    final status = getQueueStatus();
    print('📊 Worker Manager 상태:');
    print('   매니저 실행 중: ${status['manager_running']}');
    print('   워커 수: ${status['worker_count']}');

    final queueStats = status['queue_stats'] as Map<String, dynamic>;
    print('   큐 상태:');
    print('     대기 중: ${queueStats['pending']}');
    print('     처리 중: ${queueStats['processing']}');
    print('     완료: ${queueStats['completed']}');
    print('     실패: ${queueStats['failed']}');
  }
}

/// 전역 워커 매니저 인스턴스
WorkerManager? _globalWorkerManager;

/// 전역 워커 매니저 가져오기
Future<WorkerManager> getWorkerManager() async {
  if (_globalWorkerManager == null) {
    final queueManager = QueueManager();
    final serverConfig = await getServerConfig();
    _globalWorkerManager = WorkerManager(
      queueManager: queueManager,
      serverConfig: serverConfig,
      workerCount: 2,
    );
  }
  return _globalWorkerManager!;
}

/// 전역 워커 매니저 초기화
Future<void> initializeWorkerManager() async {
  final manager = await getWorkerManager();
  await manager.start();
}
