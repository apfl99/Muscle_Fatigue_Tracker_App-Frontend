import 'dart:io';
// import 'dart:convert';  // TODO: 서버 준비 후 활성화
// import 'package:http/http.dart' as http;  // TODO: 서버 준비 후 활성화
import 'package:path_provider/path_provider.dart';
// import 'package:tflite_flutter/tflite_flutter.dart'; // TODO: 모델 준비 후 활성화
import 'config.dart';
import 'measure_session.dart';

/// ========================================
/// ML 모델 관리자 (싱글톤)
/// - 서버 통신 (모델 학습 요청, 다운로드)
/// - 온디바이스 모델 추론 (Hybrid, End-to-End)
/// ========================================
class MLManager {
  static final MLManager instance = MLManager._internal();
  factory MLManager() => instance;
  MLManager._internal();

  // TFLite 인터프리터 (TODO: 모델 준비 후 활성화)
  // Interpreter? _hybridInterpreter;
  // Interpreter? _endToEndInterpreter;

  // 서버 설정 (개발자가 실제 서버 URL로 변경 필요)
  static const String serverBaseUrl = 'https://your-ml-server.com/api';
  static const String trainEndpoint = '/model/train';
  static const String downloadHybridEndpoint = '/model/hybrid/download';
  static const String downloadEndToEndEndpoint = '/model/endtoend/download';

  // 로컬 모델 파일 경로
  String? _hybridModelPath;
  String? _endToEndModelPath;

  // 초기화 상태
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// ========================================
  /// 초기화: 로컬 모델 파일 확인 및 로드
  /// ========================================
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🤖 ML Manager 초기화 시작...');

      final appDir = await getApplicationDocumentsDirectory();
      _hybridModelPath = '${appDir.path}/hybrid_model.tflite';
      _endToEndModelPath = '${appDir.path}/endtoend_model.tflite';

      // TODO: 모델 파일 준비 후 로드 로직 활성화
      // Hybrid 모델 로드 시도
      // if (await File(_hybridModelPath!).exists()) {
      //   await _loadHybridModel();
      // } else {
      //   print('⚠️ Hybrid 모델 파일 없음: $_hybridModelPath');
      // }

      // End-to-End 모델 로드 시도
      // if (await File(_endToEndModelPath!).exists()) {
      //   await _loadEndToEndModel();
      // } else {
      //   print('⚠️ End-to-End 모델 파일 없음: $_endToEndModelPath');
      // }

      print('⚠️ ML 모델 추론 기능은 추후 구현 예정');

      _isInitialized = true;
      print('✅ ML Manager 초기화 완료');
    } catch (e) {
      print('❌ ML Manager 초기화 오류: $e');
    }
  }

  // Hybrid 모델 로드 (TODO: 모델 준비 후 활성화)
  // Future<void> _loadHybridModel() async {
  //   print('⚠️ Hybrid 모델 로드는 추후 구현 예정');
  //   // TODO: 모델 파일 준비 후 아래 코드 활성화
  //   // try {
  //   //   _hybridInterpreter?.close();
  //   //   _hybridInterpreter = Interpreter.fromFile(File(_hybridModelPath!));
  //   //   print('✅ Hybrid 모델 로드 성공: $_hybridModelPath');
  //   // } catch (e) {
  //   //   print('❌ Hybrid 모델 로드 실패: $e');
  //   //   _hybridInterpreter = null;
  //   // }
  // }

  // End-to-End 모델 로드 (TODO: 모델 준비 후 활성화)
  // Future<void> _loadEndToEndModel() async {
  //   print('⚠️ End-to-End 모델 로드는 추후 구현 예정');
  //   // TODO: 모델 파일 준비 후 아래 코드 활성화
  //   // try {
  //   //   _endToEndInterpreter?.close();
  //   //   _endToEndInterpreter = Interpreter.fromFile(File(_endToEndModelPath!));
  //   //   print('✅ End-to-End 모델 로드 성공: $_endToEndModelPath');
  //   // } catch (e) {
  //   //   print('❌ End-to-End 모델 로드 실패: $e');
  //   //   _endToEndInterpreter = null;
  //   // }
  // }

  /// ========================================
  /// 서버에 모델 학습 요청 (TODO: 서버 준비 후 활성화)
  /// - 로컬 SQLite에 저장된 fatigue 로그 전송
  /// - 서버는 학습 후 모델 파일 생성
  /// ========================================
  Future<bool> requestModelTraining({
    required String userId,
    required MLMode targetMode,
  }) async {
    print('⚠️ 서버 통신 기능은 추후 구현 예정');
    print('   - 사용자 ID: $userId');
    print('   - 타겟 모드: ${targetMode.displayName}');

    // TODO: 서버 준비 후 아래 코드 활성화
    return false; // 서버 없음

    // TODO: 서버 구축 후 아래 코드 활성화
    // try {
    //   print('📡 서버에 모델 학습 요청 시작...');
    //   print('   - 사용자 ID: $userId');
    //   print('   - 타겟 모드: ${targetMode.displayName}');
    //
    //   // SQLite에서 최근 N개 측정 데이터 가져오기
    //   final db = FatigueDatabase.instance;
    //   final recentResults = await db.getRecentResults(1000); // 최근 1000개
    //
    //   if (recentResults.isEmpty) {
    //     print('⚠️ 학습할 데이터가 없습니다.');
    //     return false;
    //   }
    //
    //   // 서버 전송용 JSON 구성
    //   final requestData = {
    //     'user_id': userId,
    //     'target_mode': targetMode.name,
    //     'data_count': recentResults.length,
    //     'training_data': recentResults.map((result) {
    //       return {
    //         'timestamp': result.timestamp.toIso8601String(),
    //         'rms': result.rms,
    //         'variance': result.variance,
    //         'peak_freq': result.peakFreq,
    //         'mean_power_freq': result.meanPowerFreq,
    //         'median_freq': result.medianFreq,
    //         'fatigue': result.fatigue,
    //         'sample_count': result.sampleCount,
    //         'sampling_rate': result.samplingRate,
    //       };
    //     }).toList(),
    //   };
    //
    //   // 서버 요청
    //   final response = await http
    //       .post(
    //         Uri.parse('$serverBaseUrl$trainEndpoint'),
    //         headers: {'Content-Type': 'application/json'},
    //         body: jsonEncode(requestData),
    //       )
    //       .timeout(const Duration(seconds: 60));
    //
    //   if (response.statusCode == 200) {
    //     final responseData = jsonDecode(response.body);
    //     print('✅ 모델 학습 요청 성공');
    //     print('   - 서버 응답: ${responseData['message']}');
    //     print('   - 학습 ID: ${responseData['training_id']}');
    //     return true;
    //   } else {
    //     print('❌ 모델 학습 요청 실패: ${response.statusCode}');
    //     print('   - 응답: ${response.body}');
    //     return false;
    //   }
    // } catch (e) {
    //   print('❌ 모델 학습 요청 오류: $e');
    //   return false;
    // }
  }

  /// ========================================
  /// 서버에서 Hybrid 모델 다운로드 (TODO: 서버 준비 후 활성화)
  /// ========================================
  Future<bool> downloadHybridModel({required String userId}) async {
    print('⚠️ 서버 통신 기능은 추후 구현 예정 (Hybrid 모델 다운로드)');
    print('   - 사용자 ID: $userId');

    // TODO: 서버 준비 후 아래 코드 활성화
    return false; // 서버 없음

    // TODO: 서버 구축 후 아래 코드 활성화
    // try {
    //   print('📥 Hybrid 모델 다운로드 시작...');
    //
    //   final response = await http
    //       .get(
    //         Uri.parse('$serverBaseUrl$downloadHybridEndpoint?user_id=$userId'),
    //       )
    //       .timeout(const Duration(seconds: 30));
    //
    //   if (response.statusCode == 200) {
    //     // 모델 파일 저장
    //     await File(_hybridModelPath!).writeAsBytes(response.bodyBytes);
    //     print('✅ Hybrid 모델 다운로드 완료: $_hybridModelPath');
    //
    //     // 모델 로드
    //     await _loadHybridModel();
    //     return true;
    //   } else {
    //     print('❌ Hybrid 모델 다운로드 실패: ${response.statusCode}');
    //     return false;
    //   }
    // } catch (e) {
    //   print('❌ Hybrid 모델 다운로드 오류: $e');
    //   return false;
    // }
  }

  /// ========================================
  /// 서버에서 End-to-End 모델 다운로드 (TODO: 서버 준비 후 활성화)
  /// ========================================
  Future<bool> downloadEndToEndModel({required String userId}) async {
    print('⚠️ 서버 통신 기능은 추후 구현 예정 (End-to-End 모델 다운로드)');
    print('   - 사용자 ID: $userId');

    // TODO: 서버 준비 후 아래 코드 활성화
    return false; // 서버 없음

    // TODO: 서버 구축 후 아래 코드 활성화
    // try {
    //   print('📥 End-to-End 모델 다운로드 시작...');
    //
    //   final response = await http
    //       .get(
    //         Uri.parse(
    //           '$serverBaseUrl$downloadEndToEndEndpoint?user_id=$userId',
    //         ),
    //       )
    //       .timeout(const Duration(seconds: 30));
    //
    //   if (response.statusCode == 200) {
    //     // 모델 파일 저장
    //     await File(_endToEndModelPath!).writeAsBytes(response.bodyBytes);
    //     print('✅ End-to-End 모델 다운로드 완료: $_endToEndModelPath');
    //
    //     // 모델 로드
    //     await _loadEndToEndModel();
    //     return true;
    //   } else {
    //     print('❌ End-to-End 모델 다운로드 실패: ${response.statusCode}');
    //     return false;
    //   }
    // } catch (e) {
    //   print('❌ End-to-End 모델 다운로드 오류: $e');
    //   return false;
    // }
  }

  /// ========================================
  /// Hybrid 모드: ML 기반 baseline 보정값 예측
  /// 입력: [rms, freq, prevFatigue]
  /// 출력: baseline 보정값 (adjRMS_base)
  /// TODO: 모델 준비 후 활성화
  /// ========================================
  double? predictHybridCorrection({
    required double rms,
    required double freq,
    required double prevFatigue,
  }) {
    print('⚠️ Hybrid 모델 추론은 추후 구현 예정 (현재는 null 반환)');
    return null; // TODO: 모델 준비 후 실제 추론 결과 반환

    // TODO: 모델 파일 준비 후 아래 코드 활성화
    // if (_hybridInterpreter == null) {
    //   print('⚠️ Hybrid 모델이 로드되지 않음');
    //   return null;
    // }
    //
    // try {
    //   // 입력 데이터 정규화 (0~1 범위)
    //   final input = [
    //     [
    //       rms / 10.0, // RMS 정규화 (예: 최대 10 가정)
    //       freq / 30.0, // Freq 정규화 (예: 최대 30Hz)
    //       (prevFatigue - 1.0) / 1.0, // Fatigue 정규화 (1.0~2.0 → 0~1)
    //     ]
    //   ];
    //
    //   // 출력 버퍼
    //   final output = List.filled(1, 0.0).reshape([1, 1]);
    //
    //   // 추론 실행
    //   _hybridInterpreter!.run(input, output);
    //
    //   // 보정값 역정규화
    //   final correction = output[0][0] * 10.0;
    //
    //   print('🤖 Hybrid 보정값 예측: $correction');
    //   return correction;
    // } catch (e) {
    //   print('❌ Hybrid 추론 오류: $e');
    //   return null;
    // }
  }

  /// ========================================
  /// End-to-End 모드: ML이 직접 피로도 예측
  /// 입력: 5초 윈도우 센서 데이터 (예: 250 샘플)
  /// 출력: Fatigue 지수 (1.0~2.0)
  /// TODO: 모델 준비 후 활성화
  /// ========================================
  double? predictEndToEndFatigue({
    required List<double> windowData,
  }) {
    print('⚠️ End-to-End 모델 추론은 추후 구현 예정 (현재는 null 반환)');
    return null; // TODO: 모델 준비 후 실제 추론 결과 반환

    // TODO: 모델 파일 준비 후 아래 코드 활성화
    // if (_endToEndInterpreter == null) {
    //   print('⚠️ End-to-End 모델이 로드되지 않음');
    //   return null;
    // }
    //
    // try {
    //   // 입력 데이터 정규화 및 리쉐이핑
    //   // 예: 250 샘플 → [1, 250, 1] (batch, timesteps, features)
    //   final normalizedData = windowData.map((v) => v / 10.0).toList(); // 정규화
    //   final input = [
    //     normalizedData.map((v) => [v]).toList(),
    //   ];
    //
    //   // 출력 버퍼
    //   final output = List.filled(1, 0.0).reshape([1, 1]);
    //
    //   // 추론 실행
    //   _endToEndInterpreter!.run(input, output);
    //
    //   // Fatigue 역정규화
    //   final fatigue = 1.0 + output[0][0]; // 0~1 → 1~2
    //
    //   print('🤖 End-to-End 피로도 예측: $fatigue');
    //   return fatigue;
    // } catch (e) {
    //   print('❌ End-to-End 추론 오류: $e');
    //   return null;
    // }
  }

  /// ========================================
  /// 모델 상태 확인 (TODO: 모델 준비 후 실제 상태 반환)
  /// ========================================
  bool get hasHybridModel => false; // TODO: _hybridInterpreter != null;
  bool get hasEndToEndModel => false; // TODO: _endToEndInterpreter != null;

  /// ========================================
  /// 모델 삭제 (재학습 시)
  /// TODO: 모델 준비 후 활성화
  /// ========================================
  Future<void> deleteModels() async {
    try {
      // TODO: 모델 파일 준비 후 아래 코드 활성화
      // _hybridInterpreter?.close();
      // _endToEndInterpreter?.close();

      if (_hybridModelPath != null && await File(_hybridModelPath!).exists()) {
        await File(_hybridModelPath!).delete();
        print('🗑️ Hybrid 모델 삭제 완료');
      }

      if (_endToEndModelPath != null &&
          await File(_endToEndModelPath!).exists()) {
        await File(_endToEndModelPath!).delete();
        print('🗑️ End-to-End 모델 삭제 완료');
      }

      // TODO: 모델 파일 준비 후 아래 코드 활성화
      // _hybridInterpreter = null;
      // _endToEndInterpreter = null;

      print('⚠️ 모델 삭제 기능은 추후 구현 예정');
    } catch (e) {
      print('❌ 모델 삭제 오류: $e');
    }
  }

  /// ========================================
  /// 리소스 정리 (TODO: 모델 준비 후 활성화)
  /// ========================================
  void dispose() {
    // TODO: 모델 파일 준비 후 아래 코드 활성화
    // _hybridInterpreter?.close();
    // _endToEndInterpreter?.close();
    _isInitialized = false;
    print('🧹 ML Manager 리소스 정리 완료');
  }
}

/// ========================================
/// Hybrid 피로도 계산 (EMA + ML 결합)
/// ========================================
Future<double> calculateHybridFatigue({
  required double rms,
  required double freq,
  required double rmsBase,
  required double freqBase,
  required double prevFatigue,
}) async {
  // ML 보정값 가져오기
  final mlCorrection = MLManager.instance.predictHybridCorrection(
    rms: rms,
    freq: freq,
    prevFatigue: prevFatigue,
  );

  // ML 모델이 없거나 오류 시 EMA만 사용
  if (mlCorrection == null) {
    print('⚠️ ML 보정 실패, EMA만 사용');
    return FatigueCalculator.calculateFatigue(
      rms: rms,
      peakFreq: freq,
      rmsBase: rmsBase,
      freqBase: freqBase,
    );
  }

  // Hybrid 계산: EMA 70% + ML 30%
  final adjRmsBase = MLPhaseConstants.emaWeight * rmsBase +
      MLPhaseConstants.mlWeight * mlCorrection;

  // 피로도 계산
  final fatigue = FatigueCalculator.calculateFatigue(
    rms: rms,
    peakFreq: freq,
    rmsBase: adjRmsBase,
    freqBase: freqBase,
  );

  print('🔀 Hybrid 피로도 계산:');
  print('   - EMA RMS_base: $rmsBase');
  print('   - ML 보정값: $mlCorrection');
  print('   - 조정 RMS_base: $adjRmsBase');
  print('   - 최종 Fatigue: $fatigue');

  return fatigue;
}

/// ========================================
/// End-to-End 피로도 계산 (ML 직접 예측)
/// ========================================
Future<double?> calculateEndToEndFatigue({
  required List<double> windowData,
  required double rms,
  required double freq,
  required double rmsBase,
  required double freqBase,
}) async {
  // ML 예측
  final fatigue = MLManager.instance.predictEndToEndFatigue(
    windowData: windowData,
  );

  // ML 모델이 없거나 오류 시 EMA fallback
  if (fatigue == null) {
    print('⚠️ End-to-End 예측 실패, EMA로 복귀');
    return FatigueCalculator.calculateFatigue(
      rms: rms,
      peakFreq: freq,
      rmsBase: rmsBase,
      freqBase: freqBase,
    );
  }

  print('🎯 End-to-End 피로도 예측: $fatigue');
  return fatigue;
}
