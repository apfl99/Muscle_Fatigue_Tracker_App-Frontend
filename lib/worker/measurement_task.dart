/// 측정 작업 데이터 모델
/// 큐에서 처리할 측정 데이터의 구조를 정의합니다.
library;

class MeasurementTask {
  final String taskId;
  final String userId;
  final String sessionId;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final int priority;
  final int retryCount;
  final int maxRetries;
  TaskStatus status;

  MeasurementTask({
    required this.taskId,
    required this.userId,
    required this.sessionId,
    required this.timestamp,
    required this.data,
    this.priority = 1,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.status = TaskStatus.pending,
  });

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'user_id': userId,
      'session_id': sessionId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'priority': priority,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'status': status.toString().split('.').last,
    };
  }

  /// JSON에서 객체 생성
  factory MeasurementTask.fromJson(Map<String, dynamic> json) {
    return MeasurementTask(
      taskId: json['task_id'] ?? '',
      userId: json['user_id'] ?? '',
      sessionId: json['session_id'] ?? '',
      timestamp:
          DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      priority: json['priority'] ?? 1,
      retryCount: json['retry_count'] ?? 0,
      maxRetries: json['max_retries'] ?? 3,
      status: TaskStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => TaskStatus.pending,
      ),
    );
  }

  /// 재시도용 복사본 생성
  MeasurementTask copyWithRetry() {
    return MeasurementTask(
      taskId: taskId,
      userId: userId,
      sessionId: sessionId,
      timestamp: timestamp,
      data: data,
      priority: priority + 1, // 우선순위 낮춤
      retryCount: retryCount + 1,
      maxRetries: maxRetries,
      status: TaskStatus.pending,
    );
  }

  /// 완료 상태로 복사본 생성
  MeasurementTask copyWithCompleted(Map<String, dynamic>? result) {
    return MeasurementTask(
      taskId: taskId,
      userId: userId,
      sessionId: sessionId,
      timestamp: timestamp,
      data: result != null ? {...data, ...result} : data,
      priority: priority,
      retryCount: retryCount,
      maxRetries: maxRetries,
      status: TaskStatus.completed,
    );
  }

  /// 실패 상태로 복사본 생성
  MeasurementTask copyWithFailed(String error) {
    return MeasurementTask(
      taskId: taskId,
      userId: userId,
      sessionId: sessionId,
      timestamp: timestamp,
      data: {...data, 'error': error},
      priority: priority,
      retryCount: retryCount,
      maxRetries: maxRetries,
      status: TaskStatus.failed,
    );
  }

  @override
  String toString() {
    return 'MeasurementTask(taskId: $taskId, userId: $userId, status: $status, priority: $priority)';
  }
}

/// 작업 상태 열거형
enum TaskStatus {
  pending,
  processing,
  completed,
  failed,
}

/// 사용자 상태 데이터 타입 (user_state 테이블 구조)
class UserStateData {
  final String userId;
  final double? rmsBase;
  final double? freqBase;
  final List<double> userEmb;
  final String? modelVersion;
  final DateTime lastSync;

  UserStateData({
    required this.userId,
    this.rmsBase,
    this.freqBase,
    required this.userEmb,
    this.modelVersion,
    required this.lastSync,
  });

  /// SQLite Map에서 생성
  factory UserStateData.fromMap(Map<String, dynamic> map) {
    return UserStateData(
      userId: map['user_id'] as String,
      rmsBase: map['rms_base'] as double?,
      freqBase: map['freq_base'] as double?,
      userEmb: map['user_emb'] != null
          ? List<double>.from(map['user_emb'] as List)
          : List.filled(12, 0.0),
      modelVersion: map['model_version'] as String?,
      lastSync: DateTime.parse(map['last_sync'] as String),
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'rms_base': rmsBase,
      'freq_base': freqBase,
      'user_emb': userEmb,
      'model_version': modelVersion,
      'last_sync': lastSync.toIso8601String(),
    };
  }
}

/// 측정 데이터 타입 (fatigue_dataset 세션 구조)
class FatigueDatasetSession {
  final String userId;
  final String sessionId;
  final double avgRms;
  final double avgFreq;
  final double avgFatigue;
  final String mode;
  final int windowCount;
  final int synced;
  final int? firstWindowStartMs;
  final int? lastWindowEndMs;
  final List<Map<String, dynamic>> windows;

  FatigueDatasetSession({
    required this.userId,
    required this.sessionId,
    required this.avgRms,
    required this.avgFreq,
    required this.avgFatigue,
    required this.mode,
    required this.windowCount,
    required this.synced,
    this.firstWindowStartMs,
    this.lastWindowEndMs,
    this.windows = const [],
  });

  /// SQLite Map에서 생성
  factory FatigueDatasetSession.fromMap(
    Map<String, dynamic> map, {
    List<Map<String, dynamic>> windows = const [],
  }) {
    return FatigueDatasetSession(
      userId: map['user_id'] ?? 'local_user',
      sessionId: map['session_id'] ?? '',
      avgRms: (map['rms'] ?? 0.0).toDouble(),
      avgFreq: (map['freq'] ?? 0.0).toDouble(),
      avgFatigue: (map['fatigue'] ?? 0.0).toDouble(),
      mode: map['mode'] ?? 'ema',
      windowCount: map['window_count'] ?? windows.length,
      synced: map['synced'] ?? 0,
      firstWindowStartMs: map['first_window_start_ms'] as int?,
      lastWindowEndMs: map['last_window_end_ms'] as int?,
      windows: windows,
    );
  }

  /// JSON으로 변환 (API 전송용)
  Map<String, dynamic> toApiJson() {
    return {
      'user_id': userId,
      'session_id': sessionId,
      'avg_rms': avgRms,
      'avg_freq': avgFreq,
      'avg_fatigue': avgFatigue,
      'mode': mode,
      'window_count': windowCount,
      'synced': synced,
      'first_window_start_ms': firstWindowStartMs,
      'last_window_end_ms': lastWindowEndMs,
      'windows': windows,
    };
  }

  @override
  String toString() {
    return 'FatigueDatasetSession(userId: $userId, sessionId: $sessionId, avgFatigue: $avgFatigue)';
  }
}
