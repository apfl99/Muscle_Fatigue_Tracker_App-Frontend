import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'sensor/streaming.dart';
import 'sensor/config.dart';
import 'model/database_helper.dart';
import 'model/baseline.dart';
import 'model/measure_session.dart';
import 'model/config.dart';
import 'model/ml.dart';
import 'widgets/fatigue_gauge.dart';
import 'screens/measurement_history_page.dart';
import 'screens/profile_page.dart';
import 'theme/app_theme.dart';
import 'utils/responsive.dart';
import 'dataset_worker/worker_manager.dart'; // 워커 매니저를 위해 필요

void main() async {
  print('\n🚀 앱 시작...');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  WidgetsFlutterBinding.ensureInitialized();

  // 데이터베이스 초기화
  print('🗄️ 데이터베이스 초기화 중...');
  try {
    final db = await DatabaseHelper.instance.database;
    print('✅ 통합 DB 초기화 완료');
    print('   - DB 경로: ${db.path}');

    // Baseline Manager 초기화
    await BaselineManager.instance.initialize();
    print('✅ Baseline Manager 초기화 완료');

    // ML Manager 초기화
    await MLManager.instance.initialize();
    print('✅ ML Manager 초기화 완료');

    // Worker Manager 초기화
    await initializeWorkerManager();
    print('✅ Worker Manager 초기화 완료');
  } catch (e, stackTrace) {
    print('❌ 초기화 실패: $e');
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
      title: 'Muscle Care',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
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
  bool _isCollecting = false;

  // 윈도우 분석 결과
  Map<String, dynamic>? _analysisResult;

  // 자동 종료 타이머
  Timer? _autoStopTimer;
  int _remainingSeconds = 0;

  // (실제 측정 상태를 고정 메시지로 표시)

  @override
  void initState() {
    super.initState();
    _loadBaseline();

    // 분석 결과 콜백 등록
    _sensorStreaming.onAnalysisResult = (result) async {
      if (mounted) {
        setState(() {
          _analysisResult = result;
        });
        // Baseline 다시 로드
        await _loadBaseline();
      }
    };
  }

  // Baseline 불러오기 (내 정보 페이지용 - 메인에서는 사용 안 함)
  Future<void> _loadBaseline() async {
    // DB와 Baseline 카운트 동기화
    await BaselineManager.instance.syncWithDatabase();
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _sensorStreaming.dispose();
    super.dispose();
  }

  // 데이터 수집 시작
  Future<void> _startCollection() async {
    // 새로운 측정 시작 시 이전 데이터 초기화
    setState(() {
      _analysisResult = null;
    });

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
      _remainingSeconds = SensorConfig.windowSeconds;
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
      () async {
        if (_isCollecting) {
          await _stopCollection();
          // 측정 완료 SnackBar 제거 (피로도 결과 카드만 표시)
        }
      },
    );
  }

  // 데이터 수집 중지
  Future<void> _stopCollection() async {
    await _sensorStreaming.stopSensor();
    _autoStopTimer?.cancel();

    setState(() {
      _isCollecting = false;
      _remainingSeconds = 0;
      // _analysisResult는 유지 (측정 결과 표시를 위해)
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        titleSpacing: 8,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = Responsive.isSmallScreen(context);

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(isSmall ? 6 : 8),
                  decoration: AppTheme.cardDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: 10,
                  ),
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    size: isSmall ? 18 : 22,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: isSmall ? 6 : 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isSmall ? 'M Care' : 'Muscle Care',
                      style: GoogleFonts.poppins(
                        fontSize: isSmall ? 16 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          _buildAppBarIcon(
            icon: Icons.history_outlined,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MeasurementHistoryPage(),
                ),
              );
            },
            tooltip: '측정 기록',
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 2 : 6),
          _buildAppBarIcon(
            icon: Icons.person_outline,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfilePage(),
                ),
              );
            },
            tooltip: '내 정보',
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 2 : 6),
          _buildAppBarIcon(
            icon: Icons.settings_outlined,
            onPressed: _showSettingsDialog,
            tooltip: '설정',
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 4 : 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: Responsive.responsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 측정 안내 카드
            _buildInstructionCard(),
            const SizedBox(height: 16),

            // 수집 상태 표시
            Container(
              decoration: AppTheme.cardDecoration(
                gradient: _isCollecting
                    ? const LinearGradient(
                        colors: [
                          Color(0xFF1E1E1E),
                          Color(0xFF2A2A2A),
                        ],
                      )
                    : AppTheme.darkGradient,
              ),
              padding: Responsive.cardPadding(context),
              child: Column(
                children: [
                  // 상태 아이콘
                  Container(
                    padding: EdgeInsets.all(
                      Responsive.isSmallScreen(context) ? 16 : 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isCollecting
                          ? Icons.monitor_heart
                          : _analysisResult != null
                              ? Icons.check_circle
                              : Icons.touch_app_outlined,
                      color: Colors.white,
                      size: Responsive.isSmallScreen(context) ? 40 : 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 상태 텍스트
                  Text(
                    _isCollecting
                        ? '측정 중...'
                        : _analysisResult != null
                            ? '측정 완료'
                            : '측정 준비',
                    style: TextStyle(
                      fontSize: Responsive.isSmallScreen(context) ? 20 : 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (_isCollecting) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_remainingSeconds초 남음',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: 1 -
                            (_remainingSeconds / SensorConfig.windowSeconds),
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                        minHeight: 8,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 실시간 분석 상태 표시 (ML 모드별 색상)
                  _buildAnalysisStatusBox(),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 측정 결과 카드 (측정 완료 후에만 표시)
            if (_analysisResult != null && !_isCollecting) ...[
              _buildFatigueScoreCard(_analysisResult!),
              const SizedBox(height: 16),
              _buildMainResultCard(_analysisResult!),
              const SizedBox(height: 16),
            ],

            // 컨트롤 버튼들
            if (!_isCollecting) ...[
              Container(
                width: double.infinity,
                height: Responsive.isSmallScreen(context) ? 56 : 60,
                decoration: AppTheme.cardDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: 16,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _startCollection,
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: Responsive.isSmallScreen(context) ? 24 : 28,
                        ),
                        SizedBox(
                          width: Responsive.isSmallScreen(context) ? 8 : 12,
                        ),
                        Flexible(
                          child: Text(
                            '${SensorConfig.windowSeconds}초 측정 시작',
                            style: TextStyle(
                              fontSize:
                                  Responsive.isSmallScreen(context) ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                height: Responsive.isSmallScreen(context) ? 56 : 60,
                decoration: AppTheme.cardDecoration(
                  color: AppTheme.highFatigueColor,
                  borderRadius: 16,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _stopCollection,
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.stop_circle,
                          color: Colors.white,
                          size: Responsive.isSmallScreen(context) ? 24 : 28,
                        ),
                        SizedBox(
                          width: Responsive.isSmallScreen(context) ? 8 : 12,
                        ),
                        Text(
                          '측정 중지',
                          style: TextStyle(
                            fontSize:
                                Responsive.isSmallScreen(context) ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 피로도 점수 카드 (게이지 위젯 사용)
  Widget _buildFatigueScoreCard(Map<String, dynamic> result) {
    final fatigueScore = result['fatigueScore'] ?? 1.0;
    final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);

    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: AppTheme.fatigueGradient(fatigueScore),
      ),
      padding: Responsive.cardPadding(context),
      child: Column(
        children: [
          // 피로도 레벨 배지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.isSmallScreen(context) ? 16 : 20,
              vertical: Responsive.isSmallScreen(context) ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFatigueLevelIcon(fatigueLevel),
                  color: Colors.white,
                  size: Responsive.isSmallScreen(context) ? 20 : 24,
                ),
                SizedBox(width: Responsive.isSmallScreen(context) ? 6 : 8),
                Text(
                  fatigueLevel,
                  style: TextStyle(
                    fontSize: Responsive.isSmallScreen(context) ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 게이지 위젯
          FatigueGaugeWidget(
            fatigueScore: fatigueScore,
            previousScore: null,
          ),
          const SizedBox(height: 16),
          // 점수 표시
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  fatigueScore.toStringAsFixed(2),
                  style: GoogleFonts.inter(
                    fontSize: Responsive.isSmallScreen(context) ? 36 : 44,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(width: Responsive.isSmallScreen(context) ? 6 : 8),
                Text(
                  '/ 3.0',
                  style: TextStyle(
                    fontSize: Responsive.isSmallScreen(context) ? 14 : 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // AppBar 아이콘 버튼 (통일된 스타일)
  Widget _buildAppBarIcon({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    final isSmall = Responsive.isSmallScreen(context);

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: isSmall ? 32 : 36,
        minHeight: isSmall ? 32 : 36,
      ),
      icon: Container(
        padding: EdgeInsets.all(isSmall ? 5 : 7),
        decoration: AppTheme.iconButtonDecoration(),
        child: Icon(
          icon,
          size: isSmall ? 16 : 18,
          color: AppTheme.primaryGreen,
        ),
      ),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }

  // 분석 상태 박스 (ML 모드별 색상 적용)
  Widget _buildAnalysisStatusBox() {
    final currentMode = BaselineManager.instance.getCurrentMLMode();
    final measurementCount = BaselineManager.instance.totalMeasurementCount + 1;

    // ML 모드별 색상 (명확하게 구분, profile_page와 동일)
    Color modeColor;
    IconData modeIcon;
    String statusMessage;

    switch (currentMode) {
      case MLMode.ema:
        modeColor = const Color(0xFF2196F3); // 파란색 (기본 학습)
        modeIcon = Icons.functions;
        statusMessage = '센서 데이터로 내 기준값 학습 중';
        break;
      case MLMode.hybrid:
        modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조)
        modeIcon = Icons.hub;
        statusMessage = 'AI가 보조하여 정확도 향상 중';
        break;
      case MLMode.endToEnd:
        modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 완전)
        modeIcon = Icons.psychology;
        statusMessage = 'AI가 직접 패턴을 분석 중';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            modeColor.withOpacity(0.15),
            modeColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: modeColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [modeColor, modeColor.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              modeIcon,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusMessage,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: modeColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${currentMode.displayName} • $measurementCount번째 측정',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: modeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${currentMode.phase}단계',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: modeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 피로도 레벨별 아이콘
  IconData _getFatigueLevelIcon(String level) {
    switch (level) {
      case '정상':
        return Icons.sentiment_very_satisfied;
      case '약간 피로':
        return Icons.sentiment_satisfied;
      case '피로 누적':
        return Icons.sentiment_dissatisfied;
      case '고피로':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.help_outline;
    }
  }

  // 주요 결과 카드 (RMS, Variance, Freq)
  Widget _buildMainResultCard(Map<String, dynamic> result) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: Responsive.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: AppTheme.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '측정 데이터',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // RMS
          _buildMetricRow(
            icon: Icons.graphic_eq,
            label: '근육 활동량',
            value: result['fatigueRMS'].toStringAsFixed(4),
            subtitle: '떨림 세기',
          ),
          const SizedBox(height: 16),

          // Variance
          _buildMetricRow(
            icon: Icons.show_chart,
            label: '신호 변동',
            value: result['fatigueVariance'].toStringAsFixed(4),
            subtitle: '불규칙성',
          ),
          const SizedBox(height: 16),

          // Peak Frequency
          _buildMetricRow(
            icon: Icons.multiline_chart,
            label: '진동 빈도',
            value: '${result['peakFreq'].toStringAsFixed(1)}회/초',
            subtitle: '주요 주파수',
          ),
          const SizedBox(height: 20),

          // 측정 시간
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: Colors.white.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(result['timestamp']),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 메트릭 행 위젯
  Widget _buildMetricRow({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    final isSmall = Responsive.isSmallScreen(context);

    return Container(
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isSmall ? 10 : 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryGreen,
              size: isSmall ? 20 : 24,
            ),
          ),
          SizedBox(width: isSmall ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isSmall ? 12 : 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: isSmall ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: isSmall ? 10 : 11,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 시간 포맷팅
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  // 설정 다이얼로그
  void _showSettingsDialog() {
    double tempWindowSeconds = SensorConfig.windowSeconds.toDouble();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '설정',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 측정 시간 설정
                    const Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 20,
                          color: AppTheme.primaryGreen,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '측정 시간 (초)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: AppTheme.primaryGreen,
                              thumbColor: AppTheme.primaryGreen,
                              inactiveTrackColor: Colors.white.withOpacity(0.2),
                              overlayColor:
                                  AppTheme.primaryGreen.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: tempWindowSeconds,
                              min: 0.5,
                              max: 30,
                              divisions: 59,
                              label: '${tempWindowSeconds.toStringAsFixed(1)}초',
                              onChanged: _isCollecting
                                  ? null
                                  : (value) {
                                      setDialogState(() {
                                        tempWindowSeconds = value;
                                      });
                                    },
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${tempWindowSeconds.toStringAsFixed(1)}초',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
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
                    const SizedBox(height: 16),

                    // 데이터 관리
                    const Row(
                      children: [
                        Icon(
                          Icons.storage_outlined,
                          size: 20,
                          color: AppTheme.highFatigueColor,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '데이터 관리',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 모든 측정 기록 삭제
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: !_isCollecting
                            ? () async {
                                Navigator.of(context).pop();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('확인'),
                                      ],
                                    ),
                                    content: const Text(
                                      '모든 측정 기록을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('취소'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('삭제'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && mounted) {
                                  await DatabaseHelper.instance
                                      .deleteAllFatigueLogs();
                                  await BaselineManager.instance
                                      .syncWithDatabase();

                                  // 센서 데이터도 초기화
                                  _sensorStreaming.clearData();

                                  setState(() {
                                    _analysisResult = null;
                                  });

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('모든 측정 기록이 삭제되었습니다.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('모든 측정 기록 삭제'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: !_isCollecting ? Colors.red : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Baseline 초기화
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: !_isCollecting
                            ? () async {
                                Navigator.of(context).pop();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.orange,
                                        ),
                                        SizedBox(width: 8),
                                        Text('개인 기준값 초기화'),
                                      ],
                                    ),
                                    content: const Text(
                                      '개인 기준값을 초기화하시겠습니까?\n\n'
                                      '일반인 평균값으로 리셋되며,\n'
                                      '학습된 내 기준값이 모두 삭제됩니다.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('취소'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                        ),
                                        child: const Text('초기화'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && mounted) {
                                  await BaselineManager.instance
                                      .clearBaseline();
                                  await _loadBaseline();

                                  // 센서 데이터도 초기화
                                  _sensorStreaming.clearData();

                                  setState(() {
                                    // 데이터 초기화
                                  });

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('개인 기준값이 초기화되었습니다.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.restore),
                        label: const Text('개인 기준값 초기화'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                          side: BorderSide(
                            color: !_isCollecting
                                ? Colors.deepOrange
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                            final customPreset = MeasurementPreset(
                              name: '커스텀 측정',
                              totalSeconds: tempWindowSeconds.round(),
                              windowSeconds:
                                  SensorConfig.currentPreset.windowSeconds,
                              hopSeconds: SensorConfig.currentPreset.hopSeconds,
                              expectedWindows: (tempWindowSeconds /
                                      SensorConfig.currentPreset.hopSeconds)
                                  .round(),
                            );
                            SensorConfig.setPreset(customPreset);
                          });
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '측정 시간이 ${tempWindowSeconds.toStringAsFixed(1)}초로 설정되었습니다.',
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

  // 측정 안내 카드
  Widget _buildInstructionCard() {
    final isSmall = Responsive.isSmallScreen(context);

    // 측정 완료 후
    if (_analysisResult != null && !_isCollecting) {
      final currentMode = BaselineManager.instance.getCurrentMLMode();

      // ML 모드별 색상 (명확하게 구분, profile_page와 동일)
      Color modeColor;
      IconData modeIcon;

      switch (currentMode) {
        case MLMode.ema:
          modeColor = const Color(0xFF2196F3); // 파란색 (기본 학습)
          modeIcon = Icons.functions;
          break;
        case MLMode.hybrid:
          modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조)
          modeIcon = Icons.hub;
          break;
        case MLMode.endToEnd:
          modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 완전)
          modeIcon = Icons.psychology;
          break;
      }

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              modeColor.withOpacity(0.15),
              const Color(0xFF1E1E1E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: modeColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(isSmall ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [modeColor, modeColor.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    modeIcon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '측정이 완료되었습니다',
                    style: GoogleFonts.inter(
                      fontSize: isSmall ? 15 : 17,
                      fontWeight: FontWeight.bold,
                      color: modeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '측정 환경을 일정하게 유지하면 더 정확한 결과를 얻을 수 있습니다.',
              style: TextStyle(
                fontSize: isSmall ? 13 : 14,
                color: Colors.white.withOpacity(0.8),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: modeColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: modeColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '정확도 향상 팁 보기',
                      style: TextStyle(
                        fontSize: isSmall ? 12 : 13,
                        color: modeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: modeColor,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 측정 중
    if (_isCollecting) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryGreen.withOpacity(0.2),
              const Color(0xFF1E1E1E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primaryGreen.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(isSmall ? 16 : 20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '측정 중',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '움직이지 말고 5초간 그대로 유지하세요.',
              style: TextStyle(
                fontSize: isSmall ? 14 : 15,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 측정 전
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A3E), Color(0xFF1E1E1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(isSmall ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '측정 전 안내',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 15 : 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionItem(
            '1',
            '의자에 앉은 상태에서, 팔을 책상 위에 편히 올려주세요.',
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '2',
            '스마트폰을 한 손으로 가볍게 쥐고, 움직이지 마세요.',
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '3',
            '화면이 위를 향하도록 평평하게 두세요.',
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '4',
            '준비가 되면 아래 시작 버튼을 눌러주세요.',
            isSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(String number, String text, bool isSmall) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isSmall ? 22 : 26,
          height: isSmall ? 22 : 26,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: isSmall ? 11 : 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryGreen,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: isSmall ? 12 : 13,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
