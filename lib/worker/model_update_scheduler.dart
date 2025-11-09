import 'dart:async';

import '../model/model_downloader.dart';
import 'worker_manager.dart';

class ModelUpdateScheduler {
  ModelUpdateScheduler._internal();

  static final ModelUpdateScheduler instance = ModelUpdateScheduler._internal();

  Timer? _initialTimer;
  Timer? _periodicTimer;
  Timer? _retryTimer;
  bool _started = false;

  static const Duration _daily = Duration(days: 1);
  static const Duration _retryDelay = Duration(hours: 1);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _enqueueDownload(force: true);
    _scheduleDailyTask();
  }

  void dispose() {
    _initialTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    _started = false;
  }

  void _scheduleDailyTask() {
    _initialTimer?.cancel();
    _periodicTimer?.cancel();

    final now = DateTime.now();
    DateTime nextRun = DateTime(now.year, now.month, now.day, 4);
    if (!now.isBefore(nextRun)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }
    final initialDelay = nextRun.difference(now);

    _initialTimer = Timer(initialDelay, () async {
      await _enqueueDownload();
      _periodicTimer = Timer.periodic(_daily, (_) async {
        await _enqueueDownload();
      });
    });

    print('🕓 모델 다운로드 백그라운드 스케줄 시작: 첫 실행 ${nextRun.toLocal()}');
  }

  Future<void> _enqueueDownload({bool force = false}) async {
    try {
      _retryTimer?.cancel();
      _retryTimer = null;
      final manager = await getWorkerManager();
      await manager.addModelDownloadTask(force: force);
    } catch (e, stackTrace) {
      print('❌ 모델 다운로드 작업 등록 실패: $e');
      print(stackTrace);
      // 즉시 직접 시도 (예: 워커 초기화 전)
      try {
        await ModelDownloader.instance.downloadLatest(force: force);
      } catch (inner) {
        print('❌ 모델 직접 다운로드 재시도 실패: $inner');
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      _enqueueDownload();
    });
    print('⏳ 모델 다운로드 재시도 예약: ${_retryDelay.inMinutes}분 후');
  }
}
