import 'dart:async';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';

import '../model/model_downloader.dart';
import 'worker_manager.dart';

class ModelUpdateScheduler {
  ModelUpdateScheduler._internal();

  static final ModelUpdateScheduler instance = ModelUpdateScheduler._internal();

  Timer? _initialTimer;
  Timer? _periodicTimer;
  Timer? _retryTimer;
  bool _started = false;

  static const Duration _weekly = Duration(days: 7);
  static const Duration _retryDelay = Duration(hours: 1);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _enqueueDownload(force: true);
    _scheduleWeeklyTask();
  }

  void dispose() {
    _initialTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    _started = false;
  }

  void _scheduleWeeklyTask() {
    _initialTimer?.cancel();
    _periodicTimer?.cancel();

    final now = DateTime.now();
    DateTime nextRun = DateTime(now.year, now.month, now.day, 4);

    int daysToSunday = (DateTime.sunday - now.weekday) % 7;
    if (daysToSunday == 0 && !now.isBefore(nextRun)) {
      daysToSunday = 7;
    }
    nextRun = nextRun.add(Duration(days: daysToSunday));

    final initialDelay = nextRun.difference(now);

    _initialTimer = Timer(initialDelay, () async {
      await _enqueueDownload();
      _periodicTimer = Timer.periodic(_weekly, (_) async {
        await _enqueueDownload();
      });
    });

    appLog(
      '🕓 모델 다운로드 백그라운드 스케줄 시작: 첫 실행 ${nextRun.toLocal()} '
      '(매주 일요일 04:00)',
    );
  }

  Future<void> _enqueueDownload({bool force = false}) async {
    try {
      _retryTimer?.cancel();
      _retryTimer = null;
      final manager = await getWorkerManager();
      await manager.addModelDownloadTask(force: force);
    } catch (e, stackTrace) {
      appLog('❌ 모델 다운로드 작업 등록 실패: $e');
      appLog(stackTrace);
      // 즉시 직접 시도 (예: 워커 초기화 전)
      try {
        await ModelDownloader.instance.downloadLatest(force: force);
      } catch (inner) {
        appLog('❌ 모델 직접 다운로드 재시도 실패: $inner');
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      _enqueueDownload();
    });
    appLog('⏳ 모델 다운로드 재시도 예약: ${_retryDelay.inMinutes}분 후');
  }
}
