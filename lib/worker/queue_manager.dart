/// 비동기 큐 관리자
/// 측정 작업들을 순차적으로 처리하기 위한 큐 시스템입니다.
library;

import 'dart:convert';
import 'dart:async';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'measurement_task.dart';

class QueueManager {
  static const String _queueKey = 'measurement_queue';
  static const int _maxQueueSize = 1000;

  final List<MeasurementTask> _pendingTasks = [];
  final List<MeasurementTask> _processingTasks = [];
  final List<MeasurementTask> _completedTasks = [];
  final List<MeasurementTask> _failedTasks = [];

  // 동시성 제어를 위한 락
  bool _isProcessing = false;
  Future<void> _mutationChain = Future<void>.value();

  Future<T> _runLocked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationChain = _mutationChain.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// 큐에 작업 추가
  Future<void> addTask(MeasurementTask task) async {
    await _runLocked(() async {
      if (_pendingTasks.length >= _maxQueueSize) {
        appLog('⚠️ 큐가 가득 참, 오래된 작업 제거');
        _pendingTasks.removeAt(0);
      }

      // 우선순위에 따라 삽입
      int insertIndex = _pendingTasks.length;
      for (int i = 0; i < _pendingTasks.length; i++) {
        if (task.priority < _pendingTasks[i].priority) {
          insertIndex = i;
          break;
        }
      }

      _pendingTasks.insert(insertIndex, task);
      appLog('📝 작업 추가: ${task.taskId} (우선순위: ${task.priority})');
      await _saveQueueStateUnlocked();
    });
  }

  /// 다음 처리할 작업 가져오기
  Future<MeasurementTask?> getNextTask() async {
    return _runLocked(() async {
      // 동시성 제어: 이미 처리 중이면 null 반환
      if (_isProcessing) {
        return null;
      }

      if (_pendingTasks.isEmpty) {
        return null;
      }

      _isProcessing = true;
      try {
        final task = _pendingTasks.removeAt(0);
        task.status = TaskStatus.processing;
        _processingTasks.add(task);

        await _saveQueueStateUnlocked();
        return task;
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// 작업 완료 처리
  Future<void> completeTask(
    String taskId, {
    Map<String, dynamic>? result,
  }) async {
    await _runLocked(() async {
      final taskIndex = _processingTasks.indexWhere((t) => t.taskId == taskId);
      if (taskIndex == -1) return;

      final task = _processingTasks.removeAt(taskIndex);
      final completedTask = task.copyWithCompleted(result);
      _completedTasks.add(completedTask);

      // 재시도된 작업이 성공한 경우, 이전 실패 기록 제거
      if (task.retryCount > 0) {
        _failedTasks.removeWhere((t) => t.taskId == taskId);
        appLog('✅ 작업 완료 (재시도 성공): $taskId (${task.retryCount}번 재시도 후)');
      } else {
        appLog('✅ 작업 완료: $taskId');
      }

      await _saveQueueStateUnlocked();
    });
  }

  /// 작업 실패 처리
  Future<void> failTask(String taskId, String errorMessage) async {
    await _runLocked(() async {
      final taskIndex = _processingTasks.indexWhere((t) => t.taskId == taskId);
      if (taskIndex == -1) return;

      final task = _processingTasks.removeAt(taskIndex);

      if (task.retryCount < task.maxRetries) {
        // 재시도 - 큐에 다시 추가
        final retryTask = task.copyWithRetry();
        _pendingTasks.add(retryTask);
        appLog(
          '🔄 작업 재시도: $taskId (${task.retryCount + 1}/${task.maxRetries}) - 에러: $errorMessage',
        );
      } else {
        // 최대 재시도 초과 - 실패 목록에 추가
        final failedTask = task.copyWithFailed(errorMessage);
        _failedTasks.add(failedTask);
        appLog('❌ 작업 최종 실패: $taskId - 최종 에러: $errorMessage');
      }

      await _saveQueueStateUnlocked();
    });
  }

  /// 큐 상태 조회
  Map<String, dynamic> getQueueStats() {
    return {
      'pending': _pendingTasks.length,
      'processing': _processingTasks.length,
      'completed': _completedTasks.length,
      'failed': _failedTasks.length,
      'total': _pendingTasks.length +
          _processingTasks.length +
          _completedTasks.length +
          _failedTasks.length,
    };
  }

  bool hasTask({
    required String sessionId,
    String? userId,
  }) {
    bool matches(MeasurementTask task) =>
        task.sessionId == sessionId &&
        (userId == null || task.userId == userId);
    return _pendingTasks.any(matches) || _processingTasks.any(matches);
  }

  bool hasTaskOfType(String type) {
    bool matches(MeasurementTask task) =>
        (task.data['type'] as String?) == type;
    return _pendingTasks.any(matches) || _processingTasks.any(matches);
  }

  /// 완료된 작업 정리 (지정된 개수만 유지)
  Future<void> cleanupCompletedTasks({int keepCount = 50}) async {
    await _runLocked(() async {
      if (_completedTasks.length > keepCount) {
        final removeCount = _completedTasks.length - keepCount;
        _completedTasks.removeRange(0, removeCount);
        appLog('🧹 완료된 작업 정리: $removeCount개 제거');
        await _saveQueueStateUnlocked();
      }
    });
  }

  /// 큐 상태를 SharedPreferences에 저장
  Future<void> saveQueueState() async {
    await _runLocked(() async {
      await _saveQueueStateUnlocked();
    });
  }

  Future<void> _saveQueueStateUnlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final queueData = {
        'pending': _pendingTasks.map((t) => t.toJson()).toList(),
        'processing': _processingTasks.map((t) => t.toJson()).toList(),
        'completed': _completedTasks.map((t) => t.toJson()).toList(),
        'failed': _failedTasks.map((t) => t.toJson()).toList(),
        'last_updated': DateTime.now().toIso8601String(),
      };

      final queueJson = jsonEncode(queueData);
      await prefs.setString(_queueKey, queueJson);
    } catch (e) {
      appLog('❌ 큐 상태 저장 실패: $e');
    }
  }

  /// SharedPreferences에서 큐 상태 복원
  Future<void> loadQueueState() async {
    await _runLocked(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final queueJson = prefs.getString(_queueKey);

        if (queueJson != null) {
          final queueData = jsonDecode(queueJson) as Map<String, dynamic>;

          _pendingTasks.clear();
          _processingTasks.clear();
          _completedTasks.clear();
          _failedTasks.clear();

          // 대기 중인 작업들 복원
          final pendingList = queueData['pending'] as List<dynamic>? ?? [];
          for (final taskData in pendingList) {
            final task =
                MeasurementTask.fromJson(taskData as Map<String, dynamic>);
            task.status = TaskStatus.pending; // 상태 재설정
            _pendingTasks.add(task);
          }

          // 처리 중인 작업들 복원
          final processingList =
              queueData['processing'] as List<dynamic>? ?? [];
          for (final taskData in processingList) {
            final task =
                MeasurementTask.fromJson(taskData as Map<String, dynamic>);
            task.status = TaskStatus.processing;
            _processingTasks.add(task);
          }

          // 완료된 작업들 복원
          final completedList = queueData['completed'] as List<dynamic>? ?? [];
          for (final taskData in completedList) {
            final task =
                MeasurementTask.fromJson(taskData as Map<String, dynamic>);
            task.status = TaskStatus.completed;
            _completedTasks.add(task);
          }

          // 실패한 작업들 복원
          final failedList = queueData['failed'] as List<dynamic>? ?? [];
          for (final taskData in failedList) {
            final task =
                MeasurementTask.fromJson(taskData as Map<String, dynamic>);
            task.status = TaskStatus.failed;
            _failedTasks.add(task);
          }

          appLog(
            '✅ 큐 상태 복원 완료: ${_pendingTasks.length} pending, ${_processingTasks.length} processing',
          );
        }
      } catch (e) {
        appLog('❌ 큐 상태 복원 실패: $e');
      }
    });
  }

  /// 큐 상태 출력
  void printQueueStatus() {
    final stats = getQueueStats();
    appLog('📊 큐 상태:');
    appLog('   대기 중: ${stats['pending']}');
    appLog('   처리 중: ${stats['processing']}');
    appLog('   완료: ${stats['completed']}');
    appLog('   실패: ${stats['failed']}');
    appLog('   총합: ${stats['total']}');

    // 상세 정보
    if (_pendingTasks.isNotEmpty) {
      appLog(
        '   대기 작업: ${_pendingTasks.map((t) => '${t.taskId}(${t.retryCount})').join(', ')}',
      );
    }
    if (_processingTasks.isNotEmpty) {
      appLog(
        '   처리 작업: ${_processingTasks.map((t) => '${t.taskId}(${t.retryCount})').join(', ')}',
      );
    }
  }

  /// 사용자 상태 업로드 작업 추가
  Future<String> addUploadStateTask({
    required String userId,
    int priority = 1,
  }) async {
    final taskId = 'upload_state_${DateTime.now().millisecondsSinceEpoch}';

    final task = MeasurementTask(
      taskId: taskId,
      userId: userId,
      sessionId: 'upload_state',
      timestamp: DateTime.now(),
      data: {
        'type': 'upload_state',
        'user_id': userId,
      },
      priority: priority,
    );

    await addTask(task);
    appLog('📤 사용자 상태 업로드 작업 추가: $taskId');
    return taskId;
  }

  Future<String> addModelDownloadTask({
    bool force = false,
    int? version,
    int priority = 1,
  }) async {
    if (hasTaskOfType('model_download')) {
      appLog('ℹ️ 모델 다운로드 작업이 이미 큐에 존재합니다. (force=$force)');
      return 'model_download_existing';
    }

    final taskId = 'model_download_${DateTime.now().millisecondsSinceEpoch}';

    final task = MeasurementTask(
      taskId: taskId,
      userId: 'system',
      sessionId: 'model_download',
      timestamp: DateTime.now(),
      data: {
        'type': 'model_download',
        'force': force,
        if (version != null) 'version': version,
      },
      priority: priority,
      maxRetries: 2,
    );

    await addTask(task);
    appLog(
      '🧠 모델 다운로드 작업 추가: $taskId '
      '(force=$force, version=${version ?? 'latest'})',
    );
    return taskId;
  }

  /// 큐 초기화
  Future<void> clearQueue() async {
    await _runLocked(() async {
      _pendingTasks.clear();
      _processingTasks.clear();
      _completedTasks.clear();
      _failedTasks.clear();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);

      appLog('🧹 큐 초기화 완료');
    });
  }

  /// 처리 중인 작업들을 대기 상태로 되돌리기 (앱 재시작 시)
  Future<void> resetProcessingTasks() async {
    await _runLocked(() async {
      for (final task in _processingTasks) {
        task.status = TaskStatus.pending;
        _pendingTasks.add(task);
      }
      _processingTasks.clear();

      await _saveQueueStateUnlocked();
      appLog('🔄 처리 중인 작업들을 대기 상태로 복원');
    });
  }
}
