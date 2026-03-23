import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:muscle_fatigue_tracker/utils/app_log.dart';
import '../model/baseline.dart';
import '../model/config.dart';
import '../model/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/banner_ad_widget.dart';

void print(Object? message) => appLog(message);

/// 내 정보 페이지 (Baseline, Phase, 개인 통계)
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  // Baseline 값
  double? _currentRmsBase;
  double? _currentFreqBase;
  int _totalMeasurementCount = 0;
  int _totalWindowCount = 0;
  MLMode _currentMLMode = MLMode.ema;
  bool _hasBaseline = false;

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
      final has = await DatabaseHelper.instance.hasBaseline();

      print('📊 ProfilePage Baseline 로드:');
      print(
        '   - totalMeasurementCount: ${baselineManager.totalMeasurementCount}',
      );
      print('   - totalWindowCount: ${baselineManager.totalWindowCount}');
      print('   - updateCount: ${baselineManager.updateCount}');

      if (mounted) {
        setState(() {
          _hasBaseline = has;
          _currentRmsBase = has ? baselineManager.rmsBase : null;
          _currentFreqBase = has ? baselineManager.freqBase : null;
          _totalMeasurementCount = baselineManager.totalMeasurementCount;
          _totalWindowCount = baselineManager.totalWindowCount;
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
      await DatabaseHelper.instance.clearBaseline();
      // DB → 메모리 동기화 (즉시 반영)
      await BaselineManager.instance.initialize();
      await BaselineManager.instance.syncWithDatabase();
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
        title: Text(
          'profile.title'.tr(),
          style: TextStyle(color: AppTheme.textHigh),
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
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadData();
            },
            tooltip: 'common.refresh'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: context.locale.languageCode == 'ko'
            ? SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: Responsive.responsivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 사용자 기록 요약
                    _buildProfileSummary(),
                    const SizedBox(height: 16),
                    _buildBannerSlot(key: const ValueKey('profile_banner_top')),
                    const SizedBox(height: 16),

                    // ML Phase 정보
                    _buildMLModeCard(),
                    const SizedBox(height: 16),

                    // Baseline 정보
                    _buildBaselineCard(),
                    const SizedBox(height: 16),

                    // 지수 통계
                    _buildStatisticsCard(),
                    const SizedBox(height: 16),
                    _buildBannerSlot(key: const ValueKey('profile_banner_mid')),
                    const SizedBox(height: 16),

                    // 기록 권장사항
                    _buildMeasurementTipsCard(),
                  ],
                ),
              )
            : _buildGlobalProfileFallback(),
      ),
    );
  }

  Widget _buildGlobalProfileFallback() {
    final avgFatigue = (_statistics['avg_fatigue'] ?? 1.0) as num;
    final avgRms = (_statistics['avg_rms'] ?? 0.0) as num;
    final avgFreq = (_statistics['avg_freq'] ?? 0.0) as num;
    final nextPhaseMeasurements =
        BaselineManager.instance.getMeasurementsUntilNextPhase();

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: Responsive.responsivePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBannerSlot(key: const ValueKey('profile_banner_global_top')),
          const SizedBox(height: 16),
          Container(
            padding: Responsive.cardPadding(context),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'profile.global.summary.title'.tr(),
                  style: TextStyle(
                    color: AppTheme.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                _buildGlobalProfileRow(
                  label: 'profile.global.summary.totalLogs'.tr(),
                  value: '$_totalMeasurementCount',
                ),
                _buildGlobalProfileRow(
                  label: 'profile.global.summary.avgScore'.tr(),
                  value: avgFatigue.toStringAsFixed(2),
                ),
                _buildGlobalProfileRow(
                  label: 'profile.global.summary.mlMode'.tr(),
                  value: _localizedMlModeName(_currentMLMode),
                ),
                _buildGlobalProfileRow(
                  label: 'profile.global.summary.nextPhase'.tr(),
                  value: 'profile.global.summary.remaining'.tr(
                    namedArgs: {
                      'count': nextPhaseMeasurements.toString(),
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: Responsive.cardPadding(context),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'profile.global.baseline.title'.tr(),
                  style: TextStyle(
                    color: AppTheme.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                _buildGlobalProfileRow(
                  label: 'profile.global.baseline.motion'.tr(),
                  value: _hasBaseline
                      ? _currentRmsBase?.toStringAsFixed(4) ?? '--'
                      : '--',
                ),
                _buildGlobalProfileRow(
                  label: 'profile.global.baseline.vibration'.tr(),
                  value: _hasBaseline
                      ? 'profile.global.baseline.vibrationValue'.tr(
                          namedArgs: {
                            'value': _currentFreqBase?.toStringAsFixed(1) ?? '--',
                          },
                        )
                      : '--',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: Responsive.cardPadding(context),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'profile.global.metrics.title'.tr(),
                  style: TextStyle(
                    color: AppTheme.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                _buildGlobalProfileRow(
                  label: 'profile.global.metrics.samples'.tr(),
                  value: '$_totalWindowCount',
                ),
                _buildGlobalProfileRow(
                  label: 'profile.global.metrics.avgMotion'.tr(),
                  value: avgRms.toStringAsFixed(4),
                ),
                _buildGlobalProfileRow(
                  label: 'profile.global.metrics.avgVibration'.tr(),
                  value: avgFreq.toStringAsFixed(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildWellnessDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildGlobalProfileRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textMedium,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textHigh,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _localizedMlModeName(MLMode mode) {
    switch (mode) {
      case MLMode.ema:
        return 'sensor.aiMode.ema'.tr();
      case MLMode.hybrid:
        return 'sensor.aiMode.hybrid'.tr();
      case MLMode.endToEnd:
        return 'sensor.aiMode.endToEnd'.tr();
    }
  }

  // 기록 요약
  Widget _buildProfileSummary() {
    // 측정 세션 수를 사용 (BaselineManager와 일치)
    final totalCount = _totalMeasurementCount;
    final avgFatigue = _statistics['avg_fatigue'] ?? 1.0;

    return Container(
      padding: Responsive.cardPadding(context),
      decoration: AppTheme.cardDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00E676).withValues(alpha: 0.2),
            const Color(0xFF4CAF50).withValues(alpha: 0.1),
          ],
        ),
        borderRadius: 20,
        borderColor: const Color(0xFF00E676).withValues(alpha: 0.3),
        borderWidth: 2,
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
            ),
            child: Icon(
              Icons.person,
              color: AppTheme.textHigh,
              size: Responsive.isSmallScreen(context) ? 32 : 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '나의 퍼포먼스 점수 기록',
            style: TextStyle(
              fontSize: Responsive.isSmallScreen(context) ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textHigh,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                '총 기록',
                '$totalCount회',
                Icons.fitness_center,
                Colors.blue,
              ),
              _buildSummaryItem(
                '평균 퍼포먼스 점수',
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

  Widget _buildBannerSlot({required Key key}) {
    return Container(
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface1,
        borderRadius: 20,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: BannerAdWidget(
        key: key,
        placeholderText: 'ads.slot',
        padding: const EdgeInsets.symmetric(vertical: 4),
      ),
    );
  }

  // 기록 권장사항 카드
  Widget _buildMeasurementTipsCard() {
    return Container(
      padding: Responsive.cardPadding(context),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.cardDark,
        borderRadius: 20,
        borderColor: AppTheme.primaryGreen.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: AppTheme.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '기록 권장사항',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textHigh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 권장사항 내용
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Colors.blue,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '하루 1~2회 모션 기록으로\n개인화 향상',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textHigh,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.repeat,
                      color: Colors.blue,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '같은 시간대에 기록하면\n개인화 예측이 더 안정적으로 동작합니다',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textHigh,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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

  // ML 모드 카드 (개인화 단계 안내)
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
        modeColor = const Color(0xFF2196F3); // 파란색 (기본 단계)
        modeIcon = Icons.functions;
        accuracyInfo = '기본 단계';
        benefit = '나만의 패턴을 학습하는 중';
        features = [
          '✓ 수식 기반 퍼포먼스 점수 생성',
          '✓ 내 기준 맞추기 진행 중',
          '→ 기록을 반복할수록 더 정확해집니다',
        ];
        break;
      case MLMode.hybrid:
        modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조 단계)
        modeIcon = Icons.hub;
        accuracyInfo = '개인화 ⬆️ 향상됨';
        benefit = 'AI 보정으로 더 정확한 지표 제공';
        features = [
          '✓ 개인 기준 맞추기 완료',
          '✓ AI 모델 보정 적용 (30%)',
          '✓ 이전 기록 활용',
          '→ 나에게 맞춘 퍼포먼스 점수',
        ];
        break;
      case MLMode.endToEnd:
        modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 집중 단계)
        modeIcon = Icons.psychology;
        accuracyInfo = '최적화된 모션 기록 ⭐️';
        benefit = 'AI가 개인 패턴을 더 정확하게 기록합니다';
        features = [
          '✓ AI가 직접 예측',
          '✓ 움직임 패턴을 학습',
          '✓ 개인별 최적화 완료',
          '✓ 개인화된 퍼포먼스 점수 안내',
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
                      modeColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(modeIcon, color: AppTheme.textHigh, size: 28),
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
              color: AppTheme.surface2.withValues(alpha: 0.55),
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
              _buildMLProgressItem('총 모션 기록', '$_totalMeasurementCount회'),
              _buildMLProgressItem('세부 샘플 수', '$_totalWindowCount개'),
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
                  Text(
                    '최고 단계 도달!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textHigh,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Phase 로드맵
          _buildPhaseRoadmap(),
          const SizedBox(height: 12),
          _buildWellnessDisclaimer(),
        ],
      ),
    );
  }

  // Phase 로드맵
  Widget _buildPhaseRoadmap() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface2.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '개인화 향상 로드맵',
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
            '향상 모션 기록',
            '${MLPhaseConstants.emaPhaseThreshold}~${MLPhaseConstants.hybridPhaseThreshold - 1}회',
            'AI 보조로 개인화 향상',
            const Color(0xFF00ACC1), // 청록색
            _currentMLMode == MLMode.hybrid,
            _currentMLMode.phase > 2,
          ),
          const SizedBox(height: 8),
          _buildPhaseStep(
            3,
            '완전 AI 모션 기록',
            '${MLPhaseConstants.hybridPhaseThreshold}+회',
            'AI 기반 최적화된 기록',
            const Color(0xFF9C27B0), // 진보라색
            _currentMLMode == MLMode.endToEnd,
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildWellnessDisclaimer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface2.withValues(alpha: 0.52),
        borderRadius: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            color: Colors.orangeAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'sensor.disclaimer.full'.tr(),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMedium,
                height: 1.45,
              ),
            ),
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
                ? Icon(Icons.check, color: AppTheme.textHigh, size: 16)
                : Text(
                    '$phase',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color:
                          isCurrent ? AppTheme.textHigh : Colors.grey.shade600,
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
                      child: Text(
                        '현재',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textHigh,
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
                    child: Icon(
                      Icons.balance,
                      color: AppTheme.textHigh,
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
                          color: AppTheme.textMedium,
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
              color: AppTheme.surface2.withValues(alpha: 0.55),
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
                            _hasBaseline
                                ? _currentRmsBase!.toStringAsFixed(4)
                                : '--',
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
                            _hasBaseline
                                ? '${_currentFreqBase!.toStringAsFixed(1)}회/초'
                                : '--',
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
                    color: (!_hasBaseline ? Colors.orange : Colors.green)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        !_hasBaseline ? Icons.info_outline : Icons.check_circle,
                        size: 16,
                        color: !_hasBaseline ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          !_hasBaseline
                              ? '미설정 • 메인 화면에서 기준값을 먼저 설정하세요'
                              : '개인 기준값 설정됨',
                          style: TextStyle(
                            fontSize: 12,
                            color: !_hasBaseline ? Colors.orange : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                // 초기값 안내 제거 (DB 값만 표시)
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_hasBaseline)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.settings_input_component),
                label: const Text('기준값 설정하러 가기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: baselineColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 지수 통계 카드
  Widget _buildStatisticsCard() {
    final count = _statistics['total_logs'] ?? 0;
    final avgRms = _statistics['avg_rms'] ?? 0.0;
    final avgFreq = _statistics['avg_freq'] ?? 0.0;
    final avgFatigue = _statistics['avg_fatigue'] ?? 1.0;
    final minFatigue = _statistics['min_fatigue'] ?? 1.0;
    final maxFatigue = _statistics['max_fatigue'] ?? 1.0;

    return Container(
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface1,
        borderRadius: 12,
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
              Text(
                '지수 통계',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textHigh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatRow('총 모션 기록 세션', '$count회', Colors.blue),
          const Divider(height: 24),
          Text(
            '퍼포먼스 점수',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMedium,
            ),
          ),
          const SizedBox(height: 8),
          _buildStatRow('평균', avgFatigue.toStringAsFixed(2), Colors.orange),
          const SizedBox(height: 8),
          _buildStatRow('최소', minFatigue.toStringAsFixed(2), Colors.green),
          const SizedBox(height: 8),
          _buildStatRow('최대', maxFatigue.toStringAsFixed(2), Colors.red),
          const Divider(height: 24),
          Text(
            '지수값 평균',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMedium,
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
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textMedium,
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

  // (정리됨) 상세 행 빌더 제거
}
