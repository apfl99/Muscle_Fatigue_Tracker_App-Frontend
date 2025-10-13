import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../models/fatigue_result.dart';
import 'package:intl/intl.dart';

/// 측정 결과 화면
class ResultScreen extends StatelessWidget {
  final FatigueResult result;

  const ResultScreen({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('측정 결과'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 측정 시간
            Text(
              DateFormat('yyyy년 MM월 dd일 HH:mm').format(result.timestamp),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 피로도 게이지
            SizedBox(
              height: 250,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: 0,
                    maximum: 10,
                    ranges: <GaugeRange>[
                      GaugeRange(
                        startValue: 0,
                        endValue: 3,
                        color: Colors.green,
                      ),
                      GaugeRange(
                        startValue: 3,
                        endValue: 6,
                        color: Colors.yellow,
                      ),
                      GaugeRange(
                        startValue: 6,
                        endValue: 8,
                        color: Colors.orange,
                      ),
                      GaugeRange(
                        startValue: 8,
                        endValue: 10,
                        color: Colors.red,
                      ),
                    ],
                    pointers: <GaugePointer>[
                      NeedlePointer(
                        value: result.fatigueIndex,
                        enableAnimation: true,
                      ),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        widget: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              result.fatigueIndex.toStringAsFixed(1),
                              style: Theme.of(context)
                                  .textTheme
                                  .displayMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              result.fatigueLevel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        angle: 90,
                        positionFactor: 0.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 상세 정보 카드
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '상세 분석 결과',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('RMS', result.rms.toStringAsFixed(3)),
                    _buildDetailRow(
                      'Variance',
                      result.variance.toStringAsFixed(3),
                    ),
                    _buildDetailRow(
                      'Dominant Frequency',
                      '${result.dominantFrequency.toStringAsFixed(2)} Hz',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 조언 카드
            Card(
              color: _getAdviceColor(result.fatigueIndex),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getAdviceIcon(result.fatigueIndex),
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '조언',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getAdviceText(result.fatigueIndex),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 확인 버튼
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Color _getAdviceColor(double fatigueIndex) {
    if (fatigueIndex < 3) return Colors.green;
    if (fatigueIndex < 6) return Colors.orange;
    if (fatigueIndex < 8) return Colors.deepOrange;
    return Colors.red;
  }

  IconData _getAdviceIcon(double fatigueIndex) {
    if (fatigueIndex < 3) return Icons.sentiment_satisfied;
    if (fatigueIndex < 6) return Icons.sentiment_neutral;
    return Icons.sentiment_dissatisfied;
  }

  String _getAdviceText(double fatigueIndex) {
    if (fatigueIndex < 3) {
      return '근피로도가 낮습니다. 현재 상태를 유지하세요!';
    } else if (fatigueIndex < 6) {
      return '보통 수준의 피로도입니다. 적절한 휴식을 취하세요.';
    } else if (fatigueIndex < 8) {
      return '피로도가 높습니다. 충분한 휴식이 필요합니다.';
    } else {
      return '매우 높은 피로도입니다. 즉시 휴식을 취하고, 지속되면 전문가와 상담하세요.';
    }
  }
}

