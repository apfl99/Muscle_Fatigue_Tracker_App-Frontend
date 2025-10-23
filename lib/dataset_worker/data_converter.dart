/// 데이터 변환기
/// SQLite에서 데이터를 읽어서 JSON 형태로 변환합니다.
library;

import '../model/database_helper.dart';
import 'measurement_task.dart';

class DataConverter {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 동기화되지 않은 fatigue_logs 데이터를 읽어서 JSON으로 변환
  Future<List<Map<String, dynamic>>> getUnsyncedFatigueLogs({
    int? limit,
    String? userId,
  }) async {
    try {
      final db = await _dbHelper.database;

      String query = '''
        SELECT user_id, session_id, measure_date, rms, freq, fatigue, 
               mode, window_count, created_at, synced
        FROM fatigue_logs
        WHERE synced = 0
      ''';

      List<dynamic> whereArgs = [];

      if (userId != null) {
        query += ' AND user_id = ?';
        whereArgs.add(userId);
      }

      query += ' ORDER BY created_at ASC';

      if (limit != null) {
        query += ' LIMIT ?';
        whereArgs.add(limit);
      }

      final List<Map<String, dynamic>> results =
          await db.rawQuery(query, whereArgs);

      // JSON 형태로 변환
      final List<Map<String, dynamic>> jsonData = results.map((row) {
        return {
          'user_id': row['user_id'],
          'session_id': row['session_id'],
          'measure_date': row['measure_date'],
          'rms': row['rms'],
          'freq': row['freq'],
          'fatigue': row['fatigue'],
          'mode': row['mode'],
          'window_count': row['window_count'],
          'created_at': row['created_at'],
          'synced': row['synced'],
        };
      }).toList();

      return jsonData;
    } catch (e) {
      print('❌ 동기화되지 않은 fatigue_logs 조회 실패: $e');
      return [];
    }
  }

  /// 사용자 상태 데이터를 JSON으로 변환
  Future<Map<String, dynamic>?> getUserStateJson(String userId) async {
    try {
      final userState = await _dbHelper.getUserState(userId: userId);

      if (userState == null) {
        return null;
      }

      return {
        'user_id': userId,
        'rms_base': userState['rms_base'],
        'freq_base': userState['freq_base'],
        'user_emb': userState['user_emb'],
        'model_version': userState['model_version'],
        'last_sync': userState['last_sync'],
      };
    } catch (e) {
      print('❌ 사용자 상태 조회 실패: $e');
      return null;
    }
  }

  /// 측정 작업으로 변환
  Future<List<MeasurementTask>> convertToMeasurementTasks({
    int? limit,
    String? userId,
    int priority = 1,
  }) async {
    try {
      // 동기화되지 않은 fatigue_logs 조회
      final fatigueLogs =
          await getUnsyncedFatigueLogs(limit: limit, userId: userId);

      final List<MeasurementTask> tasks = [];

      for (final log in fatigueLogs) {
        final taskId =
            '${log['user_id']}_${log['session_id']}_${DateTime.now().millisecondsSinceEpoch}';

        final task = MeasurementTask(
          taskId: taskId,
          userId: log['user_id'] ?? '',
          sessionId: log['session_id'] ?? '',
          timestamp: DateTime.now(),
          data: {
            'fatigue_log': log,
            'type': 'fatigue_log_upload',
          },
          priority: priority,
        );

        tasks.add(task);
      }

      return tasks;
    } catch (e) {
      print('❌ 측정 작업 변환 실패: $e');
      return [];
    }
  }

  /// 사용자 상태 업로드 작업으로 변환
  Future<MeasurementTask?> convertUserStateToTask(String userId,
      {int priority = 1}) async {
    try {
      final userState = await getUserStateJson(userId);

      if (userState == null) {
        return null;
      }

      final taskId =
          '${userId}_user_state_${DateTime.now().millisecondsSinceEpoch}';

      return MeasurementTask(
        taskId: taskId,
        userId: userId,
        sessionId: 'user_state_sync',
        timestamp: DateTime.now(),
        data: {
          'user_state': userState,
          'type': 'user_state_upload',
        },
        priority: priority,
      );
    } catch (e) {
      print('❌ 사용자 상태 작업 변환 실패: $e');
      return null;
    }
  }

  /// 배치 측정 작업으로 변환 (5개씩 묶어서)
  Future<List<MeasurementTask>> convertToBatchTasks({
    int batchSize = 5,
    String? userId,
    int priority = 1,
  }) async {
    try {
      final allLogs = await getUnsyncedFatigueLogs(userId: userId);
      final List<MeasurementTask> batchTasks = [];

      // 배치 크기만큼 나누어서 작업 생성
      for (int i = 0; i < allLogs.length; i += batchSize) {
        final batch = allLogs.skip(i).take(batchSize).toList();

        final taskId =
            '${userId ?? 'all'}_batch_${DateTime.now().millisecondsSinceEpoch}_${i ~/ batchSize}';

        final task = MeasurementTask(
          taskId: taskId,
          userId: userId ?? 'all',
          sessionId: 'batch_upload_${i ~/ batchSize}',
          timestamp: DateTime.now(),
          data: {
            'fatigue_logs_batch': batch,
            'batch_size': batch.length,
            'type': 'batch_fatigue_logs_upload',
          },
          priority: priority,
        );

        batchTasks.add(task);
      }

      return batchTasks;
    } catch (e) {
      print('❌ 배치 작업 변환 실패: $e');
      return [];
    }
  }

  /// 동기화 완료 처리
  Future<void> markAsSynced(List<String> sessionIds) async {
    try {
      for (final sessionId in sessionIds) {
        await _dbHelper.markFatigueLogAsSynced(sessionId);
      }
      print('✅ 동기화 완료 처리: ${sessionIds.length}개');
    } catch (e) {
      print('❌ 동기화 완료 처리 실패: $e');
    }
  }

  /// 동기화 통계 조회
  Future<Map<String, int>> getSyncStats({String? userId}) async {
    try {
      final db = await _dbHelper.database;

      String query = '''
        SELECT 
          COUNT(*) as total,
          SUM(CASE WHEN synced = 0 THEN 1 ELSE 0 END) as unsynced,
          SUM(CASE WHEN synced = 1 THEN 1 ELSE 0 END) as synced
        FROM fatigue_logs
      ''';

      List<dynamic> whereArgs = [];

      if (userId != null) {
        query += ' WHERE user_id = ?';
        whereArgs.add(userId);
      }

      final List<Map<String, dynamic>> results =
          await db.rawQuery(query, whereArgs);

      if (results.isNotEmpty) {
        final row = results.first;
        return {
          'total': row['total'] ?? 0,
          'unsynced': row['unsynced'] ?? 0,
          'synced': row['synced'] ?? 0,
        };
      }

      return {'total': 0, 'unsynced': 0, 'synced': 0};
    } catch (e) {
      print('❌ 동기화 통계 조회 실패: $e');
      return {'total': 0, 'unsynced': 0, 'synced': 0};
    }
  }
}
