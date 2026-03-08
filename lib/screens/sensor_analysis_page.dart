import 'package:flutter/material.dart';

import '../main.dart' show SensorDataPage;

/// 기존 SensorDataPage 로직을 정밀 분석 진입점으로 분리한 래퍼 페이지
class SensorAnalysisPage extends StatelessWidget {
  const SensorAnalysisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SensorDataPage();
  }
}
