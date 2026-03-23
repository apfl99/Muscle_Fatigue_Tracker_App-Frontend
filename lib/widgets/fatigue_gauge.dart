import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import '../model/measure_session.dart';
import '../model/config.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// 컨디션 게이지 위젯
class FatigueGaugeWidget extends StatelessWidget {
  final double fatigueScore;
  final double? previousScore; // 이전 측정값 (트렌드 표시)

  const FatigueGaugeWidget({
    super.key,
    required this.fatigueScore,
    this.previousScore,
  });

  @override
  Widget build(BuildContext context) {
    final level = FatigueCalculator.getFatigueLevel(fatigueScore);
    final localizedLevel = _localizedFatigueLevel(level);
    final color = FatigueCalculator.getFatigueColor(fatigueScore);
    final gaugeValue = FatigueCalculator.fatigueToGauge(fatigueScore);
    final isSmall = Responsive.isSmallScreen(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final gaugeWidth = (maxWidth - 40).clamp(200.0, 300.0);

        return Container(
          decoration: AppTheme.cardDecoration(),
          child: Padding(
            padding: EdgeInsets.all(isSmall ? 16 : 20),
            child: Column(
              children: [
                // 게이지 바
                SizedBox(
                  width: gaugeWidth,
                  child: Stack(
                    children: [
                      // 배경
                      Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppTheme.surface2,
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      // 컨디션 바
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        height: 30,
                        width: (gaugeValue / 100) * gaugeWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.7),
                              color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      // 게이지 값 표시
                      Container(
                        height: 30,
                        alignment: Alignment.center,
                        child: Text(
                          '${gaugeValue.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: gaugeValue > 50
                                ? AppTheme.textHigh
                                : AppTheme.textMedium,
                            fontSize: isSmall ? 12 : 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 컨디션 점수
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fatigueScore.toStringAsFixed(3),
                        style: GoogleFonts.poppins(
                          fontSize: isSmall ? 36 : 48,
                          fontWeight: FontWeight.bold,
                          color: color,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 트렌드 표시
                      if (previousScore != null) ...[
                        Icon(
                          FatigueCalculator.getFatigueTrendIcon(
                            previousScore!,
                            fatigueScore,
                          ),
                          color: color,
                          size: isSmall ? 28 : 32,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 레벨 배지
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmall ? 20 : 24,
                      vertical: isSmall ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: AppTheme.buttonRadius,
                    ),
                    child: Text(
                      localizedLevel,
                      style: TextStyle(
                        fontSize: isSmall ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textHigh,
                      ),
                    ),
                  ),
                ),

                // 트렌드 텍스트
                if (previousScore != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _localizedFatigueTrend(
                      FatigueCalculator.getFatigueTrend(
                        previousScore!,
                        fatigueScore,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: isSmall ? 12 : 14,
                      color: AppTheme.textMedium,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 16),

                // 상태별 안내 메시지
                _buildStatusMessage(fatigueScore, isSmall),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusMessage(double fatigue, bool isSmall) {
    String message;
    IconData icon;
    Color messageColor;

    if (fatigue < FatigueConstants.normalThreshold) {
      message = 'gauge.status.stable'.tr();
      icon = Icons.check_circle;
      messageColor = const Color(0xFF4CAF50); // 초록 (정상)
    } else if (fatigue < FatigueConstants.lightThreshold) {
      message = 'gauge.status.restRecommended'.tr();
      icon = Icons.info;
      messageColor = const Color(0xFFFFA726); // 주황 (회복 진행)
    } else if (fatigue < FatigueConstants.midThreshold) {
      message = 'gauge.status.adjustNeeded'.tr();
      icon = Icons.warning;
      messageColor = const Color(0xFFFF7043); // 진한 주황 (회복 지연)
    } else {
      message = 'gauge.status.adjustNeededStrong'.tr();
      icon = Icons.error;
      messageColor = const Color(0xFFE53935); // 빨강 (강도 조절 필요)
    }

    return Container(
      padding: EdgeInsets.all(isSmall ? 10 : 12),
      decoration: BoxDecoration(
        color: messageColor.withValues(alpha: 0.1),
        borderRadius: AppTheme.buttonRadius,
        border: Border.all(color: messageColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: messageColor, size: isSmall ? 18 : 20),
              SizedBox(width: isSmall ? 6 : 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: isSmall ? 12 : 14,
                    color: messageColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'sensor.disclaimer.compact'.tr(),
            style: TextStyle(
              fontSize: isSmall ? 10 : 11,
              color: messageColor.withValues(alpha: 0.7),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _localizedFatigueLevel(String level) {
    final raw = level.trim().toLowerCase();
    if (raw == '회복 완료' || raw == 'recovered' || raw == '부하 안정') {
      return 'heatmap.status.recovered'.tr();
    }
    if (raw == '회복 중' || raw == 'recovering' || raw == '휴식 권장') {
      return 'heatmap.status.recovering'.tr();
    }
    if (raw == '회복 지연' ||
        raw == 'delayed recovery' ||
        raw == '강도 조절 필요' ||
        raw == 'adjust intensity needed') {
      return 'sensor.fatigue.delayed'.tr();
    }
    return 'sensor.fatigue.unknown'.tr();
  }

  String _localizedFatigueTrend(String trend) {
    final raw = trend.trim().toLowerCase();
    if (raw == '변화 없음' || raw == 'no change') {
      return 'gauge.trend.noChange'.tr();
    }
    if (raw == '컨디션 급변' || raw == 'sudden change') {
      return 'gauge.trend.suddenChange'.tr();
    }
    if (raw == '컨디션 하락' || raw == 'decline') {
      return 'gauge.trend.decline'.tr();
    }
    if (raw == '부하 완화' || raw == 'relieved') {
      return 'gauge.trend.relieved'.tr();
    }
    if (raw == '유지' || raw == 'maintained') {
      return 'gauge.trend.maintained'.tr();
    }
    return trend;
  }
}

/// 컨디션 레벨 인디케이터 (간단한 버전)
class FatigueLevelIndicator extends StatelessWidget {
  final double fatigueScore;

  const FatigueLevelIndicator({
    super.key,
    required this.fatigueScore,
  });

  @override
  Widget build(BuildContext context) {
    final level = _localizedFatigueLevel(
      FatigueCalculator.getFatigueLevel(fatigueScore),
    );
    final color = FatigueCalculator.getFatigueColor(fatigueScore);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 색상 인디케이터
        _buildLevelDot(
          const Color(0xFF4CAF50), // 초록 (정상)
          fatigueScore < FatigueConstants.normalThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
          const Color(0xFFFFA726), // 주황 (회복 진행)
          fatigueScore >= FatigueConstants.normalThreshold &&
              fatigueScore < FatigueConstants.lightThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
          const Color(0xFFFF7043), // 진한 주황 (회복 지연)
          fatigueScore >= FatigueConstants.lightThreshold &&
              fatigueScore < FatigueConstants.midThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
          const Color(0xFFE53935), // 빨강 (강도 조절 필요)
          fatigueScore >= FatigueConstants.midThreshold,
        ),
        const SizedBox(width: 8),
        Text(
          level,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _localizedFatigueLevel(String level) {
    final raw = level.trim().toLowerCase();
    if (raw == '회복 완료' || raw == 'recovered' || raw == '부하 안정') {
      return 'heatmap.status.recovered'.tr();
    }
    if (raw == '회복 중' || raw == 'recovering' || raw == '휴식 권장') {
      return 'heatmap.status.recovering'.tr();
    }
    if (raw == '회복 지연' ||
        raw == 'delayed recovery' ||
        raw == '강도 조절 필요' ||
        raw == 'adjust intensity needed') {
      return 'sensor.fatigue.delayed'.tr();
    }
    return 'sensor.fatigue.unknown'.tr();
  }

  Widget _buildLevelDot(Color color, bool isActive) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isActive ? color : AppTheme.surface2,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? color : AppTheme.borderSubtle,
          width: 2,
        ),
      ),
    );
  }
}
