/// 윈도우 피처 모델 (window_features 테이블)
/// ML 학습용 윈도우 단위 데이터
class WindowFeature {
  final int? id;
  final int sessionId;
  final int windowIndex;
  final double rms;
  final double freq;
  final double? fatiguePrev; // 이전 윈도우의 피로도
  final double? fatiguePred; // 예측된 피로도
  final double? label; // Ground truth 레이블 (학습용)

  WindowFeature({
    this.id,
    required this.sessionId,
    required this.windowIndex,
    required this.rms,
    required this.freq,
    this.fatiguePrev,
    this.fatiguePred,
    this.label,
  });

  /// DB에서 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'window_index': windowIndex,
      'rms': rms,
      'freq': freq,
      'fatigue_prev': fatiguePrev,
      'fatigue_pred': fatiguePred,
      'label': label,
    };
  }

  /// Map에서 생성
  factory WindowFeature.fromMap(Map<String, dynamic> map) {
    return WindowFeature(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      windowIndex: map['window_index'] as int,
      rms: map['rms'] as double,
      freq: map['freq'] as double,
      fatiguePrev: map['fatigue_prev'] as double?,
      fatiguePred: map['fatigue_pred'] as double?,
      label: map['label'] as double?,
    );
  }

  @override
  String toString() {
    return 'WindowFeature{id: $id, sessionId: $sessionId, windowIndex: $windowIndex, rms: $rms, freq: $freq}';
  }
}
