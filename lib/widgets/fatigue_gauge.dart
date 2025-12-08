import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../model/measure_session.dart';
import '../model/config.dart';
import '../utils/responsive.dart';

/// 피로도 게이지 위젯
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
    final color = FatigueCalculator.getFatigueColor(fatigueScore);
    final gaugeValue = FatigueCalculator.fatigueToGauge(fatigueScore);
    final isSmall = Responsive.isSmallScreen(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final gaugeWidth = (maxWidth - 40).clamp(200.0, 300.0);

        return Card(
          elevation: 4,
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
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      // 피로도 바
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        height: 30,
                        width: (gaugeValue / 100) * gaugeWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withOpacity(0.7),
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
                            color:
                                gaugeValue > 50 ? Colors.white : Colors.black87,
                            fontSize: isSmall ? 12 : 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 피로도 점수
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      level,
                      style: TextStyle(
                        fontSize: isSmall ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // 트렌드 텍스트
                if (previousScore != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    FatigueCalculator.getFatigueTrend(
                      previousScore!,
                      fatigueScore,
                    ),
                    style: TextStyle(
                      fontSize: isSmall ? 12 : 14,
                      color: Colors.grey.shade700,
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
      message = '정상 상태입니다';
      icon = Icons.check_circle;
      messageColor = const Color(0xFF4CAF50); // 초록 (정상)
    } else if (fatigue < FatigueConstants.lightThreshold) {
      message = '약간 피로한 상태입니다';
      icon = Icons.info;
      messageColor = const Color(0xFFFFA726); // 주황 (약간 피로)
    } else if (fatigue < FatigueConstants.midThreshold) {
      message = '피로가 누적되는 경향이 보입니다';
      icon = Icons.warning;
      messageColor = const Color(0xFFFF7043); // 진한 주황 (피로 누적)
    } else {
      message = '휴식이 필요합니다';
      icon = Icons.error;
      messageColor = const Color(0xFFE53935); // 빨강 (고피로)
    }

    return Container(
      padding: EdgeInsets.all(isSmall ? 10 : 12),
      decoration: BoxDecoration(
        color: messageColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: messageColor.withOpacity(0.3)),
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
            '이 지수는 웰니스 참고용이며 의료 진단이나 치료 목적으로 사용할 수 없습니다.',
            style: TextStyle(
              fontSize: isSmall ? 10 : 11,
              color: messageColor.withOpacity(0.7),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 피로도 레벨 인디케이터 (간단한 버전)
class FatigueLevelIndicator extends StatelessWidget {
  final double fatigueScore;

  const FatigueLevelIndicator({
    super.key,
    required this.fatigueScore,
  });

  @override
  Widget build(BuildContext context) {
    final level = FatigueCalculator.getFatigueLevel(fatigueScore);
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
          const Color(0xFFFFA726), // 주황 (약간 피로)
          fatigueScore >= FatigueConstants.normalThreshold &&
              fatigueScore < FatigueConstants.lightThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
          const Color(0xFFFF7043), // 진한 주황 (피로 누적)
          fatigueScore >= FatigueConstants.lightThreshold &&
              fatigueScore < FatigueConstants.midThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
          const Color(0xFFE53935), // 빨강 (고피로)
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

  Widget _buildLevelDot(Color color, bool isActive) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isActive ? color : Colors.grey.shade300,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? color : Colors.grey.shade400,
          width: 2,
        ),
      ),
    );
  }
}
