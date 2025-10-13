import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/measurement_provider.dart';
import '../providers/auth_provider.dart';
import 'result_screen.dart';

/// 측정 화면
class MeasurementScreen extends StatelessWidget {
  const MeasurementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('근피로도 측정'),
        centerTitle: true,
      ),
      body: Consumer<MeasurementProvider>(
        builder: (context, measurementProvider, child) {
          final state = measurementProvider.state;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 상태 아이콘
                  _buildStateIcon(state),
                  const SizedBox(height: 32),

                  // 상태 텍스트
                  Text(
                    _getStateText(state),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // 진행률 표시
                  if (state == MeasurementState.measuring) ...[
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: CircularProgressIndicator(
                              value: measurementProvider.progress,
                              strokeWidth: 8,
                            ),
                          ),
                          Text(
                            '${(measurementProvider.progress * 100).toInt()}%',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '휴대폰을 손에 쥐고 가만히 있어주세요',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],

                  // 분석 중 로딩
                  if (state == MeasurementState.analyzing) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      '데이터 분석 중...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],

                  // 완료 후 결과 화면으로 이동
                  if (state == MeasurementState.completed) ...[
                    const Icon(
                      Icons.check_circle,
                      size: 80,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ResultScreen(
                              result: measurementProvider.latestResult!,
                            ),
                          ),
                        ).then((_) => measurementProvider.reset());
                      },
                      child: const Text('결과 확인'),
                    ),
                  ],

                  // 에러 표시
                  if (state == MeasurementState.error) ...[
                    const Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      measurementProvider.errorMessage ?? '알 수 없는 오류',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.red,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 32),

                  // 측정 시작/취소 버튼
                  if (state == MeasurementState.idle ||
                      state == MeasurementState.error) ...[
                    ElevatedButton(
                      onPressed: () {
                        final authProvider = context.read<AuthProvider>();
                        measurementProvider.startMeasurement(
                          userId: authProvider.currentUser?.id,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                      ),
                      child: const Text('측정 시작'),
                    ),
                  ],

                  if (state == MeasurementState.measuring) ...[
                    OutlinedButton(
                      onPressed: measurementProvider.cancelMeasurement,
                      child: const Text('취소'),
                    ),
                  ],

                  // 안내 텍스트
                  if (state == MeasurementState.idle) ...[
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '측정 방법',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '1. 편안한 자세로 앉거나 서주세요\n'
                            '2. 휴대폰을 한 손으로 쥐어주세요\n'
                            '3. 측정 시작 버튼을 누르고 5초간 대기\n'
                            '4. 측정 중에는 움직이지 마세요',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStateIcon(MeasurementState state) {
    switch (state) {
      case MeasurementState.idle:
        return const Icon(
          Icons.touch_app,
          size: 100,
          color: Colors.blue,
        );
      case MeasurementState.measuring:
        return const Icon(
          Icons.sensors,
          size: 100,
          color: Colors.orange,
        );
      case MeasurementState.analyzing:
        return const Icon(
          Icons.analytics,
          size: 100,
          color: Colors.purple,
        );
      case MeasurementState.completed:
        return const Icon(
          Icons.check_circle,
          size: 100,
          color: Colors.green,
        );
      case MeasurementState.error:
        return const Icon(
          Icons.error,
          size: 100,
          color: Colors.red,
        );
    }
  }

  String _getStateText(MeasurementState state) {
    switch (state) {
      case MeasurementState.idle:
        return '측정 준비 완료';
      case MeasurementState.measuring:
        return '측정 중...';
      case MeasurementState.analyzing:
        return '분석 중...';
      case MeasurementState.completed:
        return '측정 완료!';
      case MeasurementState.error:
        return '측정 실패';
    }
  }
}

