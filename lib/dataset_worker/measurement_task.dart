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

/// 측정 데이터 타입 (fatigue_logs 테이블 구조)
class FatigueLogData {
  final String userId;
  final String sessionId;
  final String measureDate;
  final double rms;
  final double freq;
  final double fatigue;
  final String mode;
  final int windowCount;
  final DateTime createdAt;
  final int synced;

  FatigueLogData({
    required this.userId,
    required this.sessionId,
    required this.measureDate,
    required this.rms,
    required this.freq,
    required this.fatigue,
    required this.mode,
    required this.windowCount,
    required this.createdAt,
    required this.synced,
  });

  /// SQLite Map에서 생성
  factory FatigueLogData.fromMap(Map<String, dynamic> map) {
    return FatigueLogData(
      userId: map['user_id'] ?? '',
      sessionId: map['session_id'] ?? '',
      measureDate: map['measure_date'] ?? '',
      rms: (map['rms'] ?? 0.0).toDouble(),
      freq: (map['freq'] ?? 0.0).toDouble(),
      fatigue: (map['fatigue'] ?? 0.0).toDouble(),
      mode: map['mode'] ?? 'EMA',
      windowCount: map['window_count'] ?? 0,
      createdAt:
          DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      synced: map['synced'] ?? 0,
    );
  }

  /// JSON으로 변환 (API 전송용)
  Map<String, dynamic> toApiJson() {
    return {
      'user_id': userId,
      'session_id': sessionId,
      'measure_date': measureDate,
      'rms': rms,
      'freq': freq,
      'fatigue': fatigue,
      'mode': mode,
      'window_count': windowCount,
      'synced': synced,
    };
  }

  @override
  String toString() {
    return 'FatigueLogData(userId: $userId, sessionId: $sessionId, fatigue: $fatigue)';
  }
}
