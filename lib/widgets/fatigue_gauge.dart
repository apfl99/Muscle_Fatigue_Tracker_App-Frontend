import 'package:flutter/material.dart';
import '../model/log.dart';
import '../model/config.dart';

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

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 게이지 바
            Stack(
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
                  width: gaugeValue * 3, // 최대 300px
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
                      color: gaugeValue > 50 ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 피로도 점수
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fatigueScore.toStringAsFixed(3),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                // 트렌드 표시
                if (previousScore != null) ...[
                  Icon(
                    FatigueCalculator.getFatigueTrendIcon(
                        previousScore!, fatigueScore),
                    color: color,
                    size: 32,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // 레벨 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                level,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            // 트렌드 텍스트
            if (previousScore != null) ...[
              const SizedBox(height: 12),
              Text(
                FatigueCalculator.getFatigueTrend(previousScore!, fatigueScore),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // 상태별 안내 메시지
            _buildStatusMessage(fatigueScore),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage(double fatigue) {
    String message;
    IconData icon;
    Color messageColor;

    if (fatigue < FatigueConstants.normalThreshold) {
      message = '정상 상태입니다';
      icon = Icons.check_circle;
      messageColor = Colors.green;
    } else if (fatigue < FatigueConstants.lightThreshold) {
      message = '약간 피로한 상태입니다';
      icon = Icons.info;
      messageColor = Colors.yellow.shade700;
    } else if (fatigue < FatigueConstants.midThreshold) {
      message = '피로가 누적되고 있습니다';
      icon = Icons.warning;
      messageColor = Colors.orange;
    } else {
      message = '휴식이 필요합니다';
      icon = Icons.error;
      messageColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: messageColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: messageColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: messageColor, size: 20),
          const SizedBox(width: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: messageColor,
              fontWeight: FontWeight.w600,
            ),
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
            Colors.green, fatigueScore < FatigueConstants.normalThreshold),
        const SizedBox(width: 4),
        _buildLevelDot(
          Colors.yellow,
          fatigueScore >= FatigueConstants.normalThreshold &&
              fatigueScore < FatigueConstants.lightThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
          Colors.orange,
          fatigueScore >= FatigueConstants.lightThreshold &&
              fatigueScore < FatigueConstants.midThreshold,
        ),
        const SizedBox(width: 4),
        _buildLevelDot(
            Colors.red, fatigueScore >= FatigueConstants.midThreshold),
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
