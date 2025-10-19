import 'package:flutter/material.dart';
import 'dart:async';
import 'sensor/streaming.dart';
import 'sensor/config.dart';
import 'model/log.dart';
import 'model/baseline.dart';
import 'model/config.dart';
import 'widgets/fatigue_gauge.dart';

void main() async {
  print('\n🚀 앱 시작...');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  WidgetsFlutterBinding.ensureInitialized();

  // 데이터베이스 초기화
  print('🗄️ 데이터베이스 초기화 중...');
  try {
    final db = await FatigueDatabase.instance.database;
    print('✅ 측정 데이터 DB 초기화 완료');
    print('   - DB 경로: ${db.path}');

    // Baseline 데이터베이스 초기화
    await BaselineManager.instance.database;
    print('✅ Baseline DB 초기화 완료');
  } catch (e, stackTrace) {
    print('❌ 데이터베이스 초기화 실패: $e');
    print('스택 트레이스: $stackTrace');
  }

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '근피로도 측정',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SensorDataPage(),
    );
  }
}

class SensorDataPage extends StatefulWidget {
  const SensorDataPage({super.key});

  @override
  State<SensorDataPage> createState() => _SensorDataPageState();
}

class _SensorDataPageState extends State<SensorDataPage> {
  final SensorStreaming _sensorStreaming = SensorStreaming();
  Timer? _updateTimer;
  bool _isCollecting = false;

  // 실시간 표시용
  int _dataCount = 0;
  double _currentSamplingRate = 0.0;

  // 윈도우 분석 결과
  Map<String, dynamic>? _analysisResult;

  // 자동 종료 타이머
  Timer? _autoStopTimer;
  int _remainingSeconds = 0;

  // 데이터베이스에서 불러온 히스토리
  List<FatigueResult> _savedResults = [];

  // Baseline 값
  double _currentRmsBase = 0.1;
  double _currentFreqBase = 10.0;
  List<BaselineData> _baselineHistory = [];

  @override
  void initState() {
    super.initState();
    _loadSavedResults();
    _loadBaseline();

    // 분석 결과 콜백 등록
    _sensorStreaming.onAnalysisResult = (result) {
      if (mounted) {
        setState(() {
          _analysisResult = result;
        });
        // 저장된 결과 다시 로드
        _loadSavedResults();
        _loadBaseline();
      }
    };
  }

  // 저장된 결과 불러오기
  Future<void> _loadSavedResults() async {
    try {
      print('📂 저장된 결과 불러오기 시도...');
      final results = await FatigueDatabase.instance.getRecentResults(
        DatabaseConstants.defaultQueryLimit,
      );
      print('✅ ${results.length}개의 결과를 불러왔습니다');

      if (mounted) {
        setState(() {
          _savedResults = results;
        });
      }
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
    }
  }

  // Baseline 불러오기
  Future<void> _loadBaseline() async {
    try {
      final baselineManager = BaselineManager.instance;
      final history = await baselineManager.getBaselineHistory(
        DatabaseConstants.baselineHistoryLimit,
      );

      if (mounted) {
        setState(() {
          _currentRmsBase = baselineManager.rmsBase;
          _currentFreqBase = baselineManager.freqBase;
          _baselineHistory = history;
        });
      }
    } catch (e) {
      print('❌ Baseline 로드 실패: $e');
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _autoStopTimer?.cancel();
    _sensorStreaming.dispose();
    super.dispose();
  }

  // 데이터 수집 시작
  Future<void> _startCollection() async {
    final success = await _sensorStreaming.startSensor();

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('센서를 시작할 수 없습니다. 기기가 센서를 지원하는지 확인해주세요.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isCollecting = true;
      _analysisResult = null;
      _remainingSeconds = SensorConfig.windowSeconds;
    });

    // 100ms마다 UI 업데이트
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _dataCount = _sensorStreaming.getDataCount();
          _currentSamplingRate = _sensorStreaming.getCurrentSamplingRate();
        });
      }
    });

    // 남은 시간 카운트다운
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isCollecting || _remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {
          _remainingSeconds--;
        });
      }
    });

    // 설정된 시간 후 자동 종료
    _autoStopTimer = Timer(
      Duration(seconds: SensorConfig.windowSeconds),
      () {
        if (_isCollecting) {
          _stopCollection();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${SensorConfig.windowSeconds}초 측정이 완료되었습니다.',
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      },
    );
  }

  // 데이터 수집 중지
  void _stopCollection() {
    _sensorStreaming.stopSensor();
    _updateTimer?.cancel();
    _autoStopTimer?.cancel();

    setState(() {
      _isCollecting = false;
      _remainingSeconds = 0;
    });
  }

  // 데이터 초기화
  void _clearData() {
    _sensorStreaming.clearData();

    setState(() {
      _dataCount = 0;
      _currentSamplingRate = 0.0;
      _analysisResult = null;
    });
  }

  // 모든 저장된 데이터 삭제
  Future<void> _clearAllSavedData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('확인'),
        content: const Text('모든 저장된 측정 데이터를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FatigueDatabase.instance.deleteAllResults();
      _loadSavedResults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 데이터가 삭제되었습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('근피로도 측정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 수집 상태 표시
            Card(
              color:
                  _isCollecting ? Colors.green.shade50 : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      _isCollecting
                          ? Icons.fiber_manual_record
                          : Icons.check_circle,
                      color: _isCollecting ? Colors.green : Colors.grey,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isCollecting
                          ? '측정 중... ($_remainingSeconds초 남음)'
                          : _analysisResult != null
                              ? '측정 완료'
                              : '대기 중',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _isCollecting ? Colors.green.shade700 : null,
                          ),
                    ),
                    if (_isCollecting) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: 1 -
                            (_remainingSeconds / SensorConfig.windowSeconds),
                        backgroundColor: Colors.grey.shade300,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '총 데이터: $_dataCount 개',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '샘플링: ${_currentSamplingRate.toStringAsFixed(1)} Hz',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 측정 결과 카드 (주요 값: RMS, Variance, Freq)
            if (_analysisResult != null) ...[
              _buildFatigueScoreCard(_analysisResult!),
              const SizedBox(height: 16),
              _buildMainResultCard(_analysisResult!),
              const SizedBox(height: 16),
              _buildDetailedAnalysisCard(_analysisResult!),
              const SizedBox(height: 16),
            ],

            // Baseline 정보 카드
            _buildBaselineCard(),
            const SizedBox(height: 16),

            // 저장된 측정 히스토리 (항상 표시)
            _buildSavedResultsCard(),
            const SizedBox(height: 16),

            // 컨트롤 버튼들
            ElevatedButton.icon(
              onPressed: _isCollecting ? null : _startCollection,
              icon: Icon(
                _isCollecting ? Icons.hourglass_empty : Icons.play_arrow,
              ),
              label: Text(
                _isCollecting
                    ? '측정 중... ($_remainingSeconds초)'
                    : '${SensorConfig.windowSeconds}초 측정 시작',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCollecting ? Colors.grey : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isCollecting) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _stopCollection,
                icon: const Icon(Icons.stop),
                label: const Text('측정 중지'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _dataCount > 0 ? _clearData : null,
              icon: const Icon(Icons.clear_all),
              label: const Text('데이터 초기화'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 피로도 점수 카드 (게이지 위젯 사용)
  Widget _buildFatigueScoreCard(Map<String, dynamic> result) {
    final fatigueScore = result['fatigueScore'] ?? 1.0;

    // 이전 측정값 가져오기 (트렌드 표시용)
    double? previousScore;
    if (_savedResults.isNotEmpty) {
      previousScore = _savedResults.first.fatigue;
    }

    return Column(
      children: [
        FatigueGaugeWidget(
          fatigueScore: fatigueScore,
          previousScore: previousScore,
        ),
        if (result['dbId'] != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.save, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '데이터베이스에 저장됨 (ID: ${result['dbId']})',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // 주요 결과 카드 (RMS, Variance, Freq)
  Widget _buildMainResultCard(Map<String, dynamic> result) {
    return Card(
      elevation: 6,
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics, color: Colors.purple.shade700, size: 28),
                const SizedBox(width: 8),
                Text(
                  '측정 데이터',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // RMS
            _buildBigValueCard(
              'RMS',
              result['fatigueRMS'].toStringAsFixed(4),
              '진동 강도',
              Icons.vibration,
              Colors.purple,
            ),
            const SizedBox(height: 16),

            // Variance
            _buildBigValueCard(
              'Variance',
              result['fatigueVariance'].toStringAsFixed(4),
              '변동성',
              Icons.show_chart,
              Colors.deepPurple,
            ),
            const SizedBox(height: 16),

            // Peak Frequency
            _buildBigValueCard(
              'Peak Frequency',
              '${result['peakFreq'].toStringAsFixed(2)} Hz',
              '최대 진폭 주파수',
              Icons.waves,
              Colors.indigo,
            ),

            const SizedBox(height: 16),
            Divider(color: Colors.purple.shade200),
            const SizedBox(height: 8),
            Text(
              '측정 시간: ${_formatTime(result['timestamp'])}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 큰 값 표시 카드
  Widget _buildBigValueCard(
    String label,
    String value,
    String description,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 상세 분석 결과 카드
  Widget _buildDetailedAnalysisCard(Map<String, dynamic> result) {
    return Card(
      elevation: 4,
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.purple, size: 28),
                const SizedBox(width: 8),
                Text(
                  '${result['windowSeconds']}초 윈도우 분석 결과',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildAnalysisRow(
              '샘플 수',
              '${result['sampleCount']}개',
              Colors.purple,
            ),
            const SizedBox(height: 12),
            Text(
              '💪 근피로도 특징 (FFT 기반)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              'RMS',
              result['fatigueRMS'].toStringAsFixed(4),
              Colors.purple,
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              '분산',
              result['fatigueVariance'].toStringAsFixed(4),
              Colors.purple,
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              'Peak Frequency',
              '${result['peakFreq'].toStringAsFixed(2)} Hz',
              Colors.deepPurple,
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              'Mean Power Freq',
              '${result['meanPowerFreq'].toStringAsFixed(2)} Hz',
              Colors.deepPurple,
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              'Median Freq',
              '${result['medianFreq'].toStringAsFixed(2)} Hz',
              Colors.deepPurple,
            ),
            const SizedBox(height: 12),
            Text(
              '📊 원본 데이터 (비교용)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              'RMS',
              result['rawRMS'].toStringAsFixed(4),
              Colors.grey,
            ),
            const SizedBox(height: 8),
            _buildAnalysisRow(
              '분산',
              result['rawVariance'].toStringAsFixed(4),
              Colors.grey,
            ),
            const SizedBox(height: 12),
            _buildAnalysisRow(
              '실시간 샘플링',
              '${result['samplingRate'].toStringAsFixed(1)} Hz',
              Colors.blue,
            ),
            const SizedBox(height: 12),
            Text(
              '시간: ${_formatTime(result['timestamp'])}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Baseline 정보 카드
  Widget _buildBaselineCard() {
    return Card(
      elevation: 3,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.balance, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Baseline (기준값)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadBaseline,
                  tooltip: '새로고침',
                ),
              ],
            ),
            const Divider(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            'RMS Base',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentRmsBase.toStringAsFixed(4),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade300,
                      ),
                      Column(
                        children: [
                          Text(
                            'Freq Base',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_currentFreqBase.toStringAsFixed(2)} Hz',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '최근 5회 측정의 Moving Average',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            if (_baselineHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text(
                  'Baseline 히스토리 (${_baselineHistory.length}개)',
                  style: const TextStyle(fontSize: 14),
                ),
                children: [
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      itemCount: _baselineHistory.length,
                      itemBuilder: (context, index) {
                        final baseline = _baselineHistory[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          title: Text(
                            _formatDateTime(baseline.timestamp),
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            'RMS: ${baseline.rmsBase.toStringAsFixed(4)} | Freq: ${baseline.freqBase.toStringAsFixed(2)} Hz',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 저장된 측정 결과 히스토리
  Widget _buildSavedResultsCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '저장된 측정 기록 (${_savedResults.length}개)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadSavedResults,
                      tooltip: '새로고침',
                    ),
                    IconButton(
                      icon:
                          Icon(Icons.delete_sweep, color: Colors.red.shade400),
                      onPressed:
                          _savedResults.isEmpty ? null : _clearAllSavedData,
                      tooltip: '전체 삭제',
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            _savedResults.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '저장된 측정 기록이 없습니다',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '측정을 시작하면 자동으로 저장됩니다',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SizedBox(
                    height: 400,
                    child: ListView.builder(
                      itemCount: _savedResults.length,
                      itemBuilder: (context, index) {
                        final result = _savedResults[index];
                        return _buildSavedResultItem(result, index);
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // 저장된 결과 항목
  Widget _buildSavedResultItem(FatigueResult result, int index) {
    final fatigueLevel = FatigueCalculator.getFatigueLevel(result.fatigue);
    final fatigueColor = FatigueCalculator.getFatigueColor(result.fatigue);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: fatigueColor,
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _formatDateTime(result.timestamp),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: fatigueColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                result.fatigue.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          fatigueLevel,
          style: TextStyle(
            fontSize: 12,
            color: fatigueColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildResultDetailRow('RMS', result.rms.toStringAsFixed(4)),
                const SizedBox(height: 8),
                _buildResultDetailRow(
                  'Variance',
                  result.variance.toStringAsFixed(4),
                ),
                const SizedBox(height: 8),
                _buildResultDetailRow(
                  'Peak Freq',
                  '${result.peakFreq.toStringAsFixed(2)} Hz',
                ),
                const SizedBox(height: 8),
                _buildResultDetailRow(
                  'Mean Power Freq',
                  '${result.meanPowerFreq.toStringAsFixed(2)} Hz',
                ),
                const SizedBox(height: 8),
                _buildResultDetailRow(
                  'Median Freq',
                  '${result.medianFreq.toStringAsFixed(2)} Hz',
                ),
                const SizedBox(height: 8),
                _buildResultDetailRow('샘플 수', '${result.sampleCount}개'),
                const SizedBox(height: 8),
                _buildResultDetailRow(
                  '샘플링 레이트',
                  '${result.samplingRate.toStringAsFixed(1)} Hz',
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await FatigueDatabase.instance.deleteResult(result.id!);
                    _loadSavedResults();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('측정 기록이 삭제되었습니다.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete),
                  label: const Text('삭제'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 결과 상세 행
  Widget _buildResultDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // 분석 결과 행 위젯
  Widget _buildAnalysisRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }

  // 시간 포맷팅
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  // 날짜+시간 포맷팅
  String _formatDateTime(DateTime time) {
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  // 설정 다이얼로그
  void _showSettingsDialog() {
    int tempWindowSeconds = SensorConfig.windowSeconds;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('측정 설정'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '윈도우 크기 (초)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: tempWindowSeconds.toDouble(),
                          min: 1,
                          max: 30,
                          divisions: 29,
                          label: '$tempWindowSeconds초',
                          onChanged: _isCollecting
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    tempWindowSeconds = value.toInt();
                                  });
                                },
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text(
                          '$tempWindowSeconds초',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  if (_isCollecting)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        '⚠️ 측정 중에는 설정을 변경할 수 없습니다.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    '현재 샘플링 레이트: ${SensorConfig.samplingRate.toStringAsFixed(0)} Hz',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: _isCollecting
                      ? null
                      : () {
                          setState(() {
                            SensorConfig.setWindowSeconds(tempWindowSeconds);
                          });
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '윈도우 크기가 $tempWindowSeconds초로 설정되었습니다.',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  child: const Text('적용'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
