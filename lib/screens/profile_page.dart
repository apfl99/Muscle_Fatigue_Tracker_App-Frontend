import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../model/baseline.dart';
import '../model/config.dart';
import '../model/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// 내 정보 페이지 (Baseline, Phase, 개인 통계)
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  // Baseline 값
  double _currentRmsBase = 0.02;
  double _currentFreqBase = 1.5;
  int _baselineUpdateCount = 0;
  int _totalMeasurementCount = 0;
  int _totalWindowCount = 0;
  bool _isCalibrating = true;
  MLMode _currentMLMode = MLMode.ema;

  // 통계
  Map<String, dynamic> _statistics = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 화면이 다시 활성화되면 데이터 새로고침
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    // DB와 Baseline 카운트 동기화
    await BaselineManager.instance.syncWithDatabase();
    await _loadBaseline();
    await _loadStatistics();
  }

  Future<void> _loadBaseline() async {
    try {
      final baselineManager = BaselineManager.instance;

      print('📊 ProfilePage Baseline 로드:');
      print(
        '   - totalMeasurementCount: ${baselineManager.totalMeasurementCount}',
      );
      print('   - totalWindowCount: ${baselineManager.totalWindowCount}');
      print('   - updateCount: ${baselineManager.updateCount}');

      if (mounted) {
        setState(() {
          _currentRmsBase = baselineManager.rmsBase;
          _currentFreqBase = baselineManager.freqBase;
          _baselineUpdateCount = baselineManager.updateCount;
          _totalMeasurementCount = baselineManager.totalMeasurementCount;
          _totalWindowCount = baselineManager.totalWindowCount;
          _isCalibrating = baselineManager.isCalibrating;
          _currentMLMode = baselineManager.getCurrentMLMode();
        });

        print('📊 ProfilePage 상태 업데이트 완료:');
        print('   - _totalMeasurementCount: $_totalMeasurementCount');
        print('   - _totalWindowCount: $_totalWindowCount');
      }
    } catch (e) {
      print('❌ Baseline 로드 실패: $e');
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final stats = await DatabaseHelper.instance.getOverallStats();
      if (mounted) {
        setState(() {
          _statistics = stats;
        });
      }
    } catch (e) {
      print('❌ 통계 로드 실패: $e');
    }
  }

  Future<void> _resetBaseline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('초기화'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await BaselineManager.instance.clearBaseline();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('개인 기준값이 초기화되었습니다.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        title: const Text(
          '내 정보',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: AppTheme.iconButtonDecoration(),
              child: const Icon(
                Icons.refresh,
                color: AppTheme.primaryGreen,
                size: 20,
              ),
            ),
            onPressed: _loadData,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: Responsive.responsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 사용자 프로필 요약
            _buildProfileSummary(),
            const SizedBox(height: 16),

            // ML Phase 정보
            _buildMLModeCard(),
            const SizedBox(height: 16),

            // Baseline 정보
            _buildBaselineCard(),
            const SizedBox(height: 16),

            // 측정 통계
            _buildStatisticsCard(),
          ],
        ),
      ),
    );
  }

  // 프로필 요약
  Widget _buildProfileSummary() {
    // 측정 세션 수를 사용 (BaselineManager와 일치)
    final totalCount = _totalMeasurementCount;
    final avgFatigue = _statistics['avg_fatigue'] ?? 1.0;

    return Container(
      padding: Responsive.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00E676).withOpacity(0.2),
            const Color(0xFF4CAF50).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00E676).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: Responsive.isSmallScreen(context) ? 70 : 80,
            height: Responsive.isSmallScreen(context) ? 70 : 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF00E676), Color(0xFF4CAF50)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.person,
              color: Colors.white,
              size: Responsive.isSmallScreen(context) ? 32 : 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '나의 근피로도 프로필',
            style: TextStyle(
              fontSize: Responsive.isSmallScreen(context) ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                '총 측정',
                '$totalCount회',
                Icons.fitness_center,
                Colors.blue,
              ),
              _buildSummaryItem(
                '평균 피로도',
                avgFatigue.toStringAsFixed(2),
                Icons.trending_flat,
                Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // ML 모드 카드 (정확도 향상 단계)
  Widget _buildMLModeCard() {
    final nextPhaseMeasurements =
        BaselineManager.instance.getMeasurementsUntilNextPhase();

    Color modeColor;
    IconData modeIcon;
    String accuracyInfo;
    String benefit;
    List<String> features;

    switch (_currentMLMode) {
      case MLMode.ema:
        modeColor = const Color(0xFF2196F3); // 파란색 (기본 학습)
        modeIcon = Icons.functions;
        accuracyInfo = '기본 정확도';
        benefit = '일반인 평균 대비 개인화 시작';
        features = [
          '✓ 수식 기반 피로도 계산',
          '✓ 내 기준값 학습 중',
          '→ 더 많은 측정으로 정확도 향상',
        ];
        break;
      case MLMode.hybrid:
        modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조)
        modeIcon = Icons.hub;
        accuracyInfo = '정확도 ⬆️ 향상됨';
        benefit = 'AI가 보조하여 더 정확한 예측';
        features = [
          '✓ 개인 기준값 완성',
          '✓ AI 모델 보정 적용 (30%)',
          '✓ 이전 측정값 활용',
          '→ 더 정확한 피로도 예측',
        ];
        break;
      case MLMode.endToEnd:
        modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 완전)
        modeIcon = Icons.psychology;
        accuracyInfo = '최고 정확도 ⭐️';
        benefit = '완전 AI 기반 개인화 예측';
        features = [
          '✓ AI가 직접 예측',
          '✓ 센서 데이터 패턴 학습',
          '✓ 개인별 최적화 완료',
          '✓ 가장 정확한 피로도 측정',
        ];
        break;
    }

    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: LinearGradient(
          colors: [
            modeColor.withOpacity(0.3),
            modeColor.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      modeColor,
                      modeColor.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: modeColor.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(modeIcon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_currentMLMode.phase}단계',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _currentMLMode.displayName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: modeColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: modeColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        accuracyInfo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: modeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 혜택 설명
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: modeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.star, color: modeColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    benefit,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade300,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 기능 설명
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: features
                  .map(
                    (feature) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),

          // 진행 상황
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMLProgressItem('총 측정', '$_totalMeasurementCount회'),
              _buildMLProgressItem('분석 횟수', '$_totalWindowCount회'),
            ],
          ),
          if (_currentMLMode != MLMode.endToEnd) ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '다음 단계까지',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '$nextPhaseMeasurements회 남음',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: modeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _currentMLMode == MLMode.ema
                        ? _totalMeasurementCount /
                            MLPhaseConstants.emaPhaseThreshold
                        : (_totalMeasurementCount -
                                MLPhaseConstants.emaPhaseThreshold) /
                            (MLPhaseConstants.hybridPhaseThreshold -
                                MLPhaseConstants.emaPhaseThreshold),
                    backgroundColor: Colors.grey.shade800,
                    valueColor: AlwaysStoppedAnimation<Color>(modeColor),
                    minHeight: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentMLMode == MLMode.ema
                      ? '2단계 전환까지 ${((_totalMeasurementCount / MLPhaseConstants.emaPhaseThreshold) * 100).toStringAsFixed(0)}%'
                      : '3단계 전환까지 ${(((_totalMeasurementCount - MLPhaseConstants.emaPhaseThreshold) / (MLPhaseConstants.hybridPhaseThreshold - MLPhaseConstants.emaPhaseThreshold)) * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: modeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.workspace_premium,
                    color: modeColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '최고 단계 도달!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Phase 로드맵
          _buildPhaseRoadmap(),

          // ML 구현 안내
          if (_currentMLMode != MLMode.ema) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.shade700,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.construction,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ML 모델 기능은 추후 구현 예정',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '현재는 모든 단계에서 기본 학습 방식 사용',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Phase 로드맵
  Widget _buildPhaseRoadmap() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📚 정확도 향상 로드맵',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 12),
          _buildPhaseStep(
            1,
            '기본 학습',
            '0~${MLPhaseConstants.emaPhaseThreshold - 1}회',
            '내 기준값 학습',
            const Color(0xFF2196F3), // 파란색
            _currentMLMode == MLMode.ema,
            _currentMLMode.phase > 1,
          ),
          const SizedBox(height: 8),
          _buildPhaseStep(
            2,
            '향상 분석',
            '${MLPhaseConstants.emaPhaseThreshold}~${MLPhaseConstants.hybridPhaseThreshold - 1}회',
            'AI 보조로 정확도 향상',
            const Color(0xFF00ACC1), // 청록색
            _currentMLMode == MLMode.hybrid,
            _currentMLMode.phase > 2,
          ),
          const SizedBox(height: 8),
          _buildPhaseStep(
            3,
            '완전 AI 분석',
            '${MLPhaseConstants.hybridPhaseThreshold}+회',
            'AI 기반 최고 정확도',
            const Color(0xFF9C27B0), // 진보라색
            _currentMLMode == MLMode.endToEnd,
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseStep(
    int phase,
    String name,
    String windowRange,
    String description,
    Color color,
    bool isCurrent,
    bool isCompleted,
  ) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isCurrent
                ? color
                : isCompleted
                    ? color.withOpacity(0.3)
                    : Colors.grey.shade800,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCurrent || isCompleted ? color : Colors.grey.shade700,
              width: 2,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$phase',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isCurrent
                          ? color
                          : isCompleted
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '현재',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                windowRange,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMLProgressItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  // Baseline 정보 카드
  Widget _buildBaselineCard() {
    const baselineColor = Color(0xFF00BCD4);

    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00BCD4), Color(0xFF00ACC1)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.balance,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '내 기준값',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00BCD4),
                        ),
                      ),
                      Text(
                        '개인별 맞춤 기준',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: baselineColor),
                    onPressed: _loadBaseline,
                    tooltip: '새로고침',
                  ),
                  IconButton(
                    icon: const Icon(Icons.restore, color: Colors.orange),
                    onPressed: _resetBaseline,
                    tooltip: '개인 기준값 초기화',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: baselineColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '근육 활동 기준',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _currentRmsBase.toStringAsFixed(4),
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF00BCD4),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            baselineColor.withOpacity(0.1),
                            baselineColor.withOpacity(0.3),
                            baselineColor.withOpacity(0.1),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '진동 기준',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_currentFreqBase.toStringAsFixed(1)}회/초',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF00BCD4),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isCalibrating ? Colors.orange : Colors.green)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isCalibrating ? Icons.settings : Icons.check_circle,
                        size: 16,
                        color: _isCalibrating ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _isCalibrating
                              ? '초기 조정 중... ($_baselineUpdateCount/${BaselineConstants.calibrationWindows}회)'
                              : '개인화 완료 (업데이트 $_baselineUpdateCount회)',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                _isCalibrating ? Colors.orange : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '초기값: 근육 활동 0.02, 진동 1.5회/초 (일반인 평균)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: ExpansionTile(
              title: const Text(
                '기준값 상세 정보',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              leading: const Icon(
                Icons.info_outline,
                color: baselineColor,
                size: 20,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(
                        '업데이트 횟수',
                        '$_baselineUpdateCount회',
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        '적응 속도 (근육)',
                        '${BaselineConstants.alphaRms}',
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        '적응 속도 (진동)',
                        '${BaselineConstants.alphaFreq}',
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        '학습 방식:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '새 기준 = 적응속도 × 측정값 + (1-적응속도) × 이전 기준',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 측정 통계 카드
  Widget _buildStatisticsCard() {
    final count = _statistics['total_sessions'] ?? 0;
    final avgRms = _statistics['avg_rms'] ?? 0.0;
    final avgFreq = _statistics['avg_freq'] ?? 0.0;
    final avgFatigue = _statistics['avg_fatigue'] ?? 1.0;
    final minFatigue = _statistics['min_fatigue'] ?? 1.0;
    final maxFatigue = _statistics['max_fatigue'] ?? 1.0;

    return Card(
      elevation: 3,
      color: const Color(0xFF1E1E1E),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bar_chart,
                    color: Color(0xFFFF9800),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '측정 통계',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow('총 측정 횟수', '$count회', Colors.blue),
            const Divider(height: 24),
            const Text(
              '피로도 점수',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            _buildStatRow('평균', avgFatigue.toStringAsFixed(2), Colors.orange),
            const SizedBox(height: 8),
            _buildStatRow('최소', minFatigue.toStringAsFixed(2), Colors.green),
            const SizedBox(height: 8),
            _buildStatRow('최대', maxFatigue.toStringAsFixed(2), Colors.red),
            const Divider(height: 24),
            const Text(
              '측정값 평균',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              '평균 근육 활동량',
              avgRms.toStringAsFixed(4),
              Colors.purple,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              '평균 진동수',
              '${avgFreq.toStringAsFixed(1)}회/초',
              Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
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
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
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
}
