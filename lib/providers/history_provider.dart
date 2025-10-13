import 'package:flutter/foundation.dart';
import '../models/fatigue_result.dart';
import '../services/local_storage_service.dart';
import '../services/api_service.dart';

/// 측정 기록 상태관리 Provider
class HistoryProvider extends ChangeNotifier {
  final LocalStorageService _storageService;
  final ApiService _apiService;

  HistoryProvider({
    required LocalStorageService storageService,
    required ApiService apiService,
  })  : _storageService = storageService,
        _apiService = apiService;

  List<FatigueResult> _results = [];
  List<FatigueResult> get results => List.unmodifiable(_results);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 로컬에서 최근 결과 불러오기
  Future<void> loadLocalResults({int limit = 30}) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      _results = await _storageService.getRecentResults(limit: limit);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = '데이터 불러오기 오류: $e';
      notifyListeners();
    }
  }

  /// 기간별 결과 조회
  Future<void> loadResultsByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      _results = await _storageService.getResultsByDateRange(
        start: start,
        end: end,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = '데이터 불러오기 오류: $e';
      notifyListeners();
    }
  }

  /// 주간 평균 계산
  double? get weeklyAverage {
    if (_results.isEmpty) return null;

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    final weeklyResults = _results.where((r) => r.timestamp.isAfter(weekAgo));
    if (weeklyResults.isEmpty) return null;

    final sum = weeklyResults.fold<double>(
      0,
      (sum, result) => sum + result.fatigueIndex,
    );
    return sum / weeklyResults.length;
  }

  /// 최근 결과
  FatigueResult? get latestResult => _results.isNotEmpty ? _results.first : null;

  /// 서버와 동기화
  Future<void> syncWithServer() async {
    try {
      // TODO: 로컬 데이터를 서버로 업로드
      // TODO: 서버 데이터를 로컬로 가져오기
      notifyListeners();
    } catch (e) {
      _errorMessage = '동기화 오류: $e';
      notifyListeners();
    }
  }

  /// 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

