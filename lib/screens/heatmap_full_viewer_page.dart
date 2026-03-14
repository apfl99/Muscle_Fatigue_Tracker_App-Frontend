import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../providers/heatmap_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_muscle_3d_viewer.dart';
import 'sensor_analysis_page.dart';

class HeatmapFullViewerPage extends StatefulWidget {
  const HeatmapFullViewerPage({super.key});

  @override
  State<HeatmapFullViewerPage> createState() => _HeatmapFullViewerPageState();
}

class _HeatmapFullViewerPageState extends State<HeatmapFullViewerPage> {
  String? _selectedMuscleCode;

  @override
  Widget build(BuildContext context) {
    return Consumer<HeatmapProvider>(
      builder: (context, provider, _) {
        final score = _calculateConditionScore(provider.heatmapEntries);

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: const Text('오늘의 컨디션 맵'),
            backgroundColor: AppTheme.darkBackground,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AppTheme.cardDark,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: InteractiveMuscle3DViewer(
                              entries: provider.heatmapEntries,
                              exposeBackgroundKey: true,
                              onMuscleTap: (muscleCode) =>
                                  _onMuscleTapped(provider, muscleCode),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            top: 14,
                            child: _buildStatusBadge(score),
                          ),
                          if (provider.isLoading)
                            const Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            provider.isLoading ? null : provider.refreshAll,
                        icon: const Icon(Icons.refresh),
                        label: const Text('상태 새로고침'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        key: const Key('go_sensor_analysis_button'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SensorAnalysisPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.analytics_outlined),
                        label: const Text('상세 분석 보기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildRecoveryInsightCard(provider),
              ),
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }

  _ConditionScore _calculateConditionScore(List<MuscleHeatmapEntry> entries) {
    if (entries.isEmpty) {
      return const _ConditionScore(average: 1.0, peak: 1.0);
    }

    final values = entries.map((entry) {
      if (entry.conditionScore > 0) {
        return entry.conditionScore.clamp(0.0, 3.0);
      }
      switch (entry.status) {
        case HeatmapStatus.red:
          return 3.0;
        case HeatmapStatus.yellow:
          return 2.0;
        case HeatmapStatus.green:
          return 1.0;
        case HeatmapStatus.unknown:
          return 1.5;
      }
    }).toList();

    final total = values.fold<double>(0, (sum, value) => sum + value);
    final average = total / values.length;
    final peak = values.reduce((a, b) => a > b ? a : b);

    return _ConditionScore(average: average, peak: peak);
  }

  void _onMuscleTapped(HeatmapProvider provider, String muscleCode) {
    final normalizedCode = _normalizeMuscleCode(muscleCode);
    final tappedEntry = provider.heatmapEntryByMuscleCode[normalizedCode];
    final snapshot = provider.getRecoverySnapshot(normalizedCode);
    final displayName = _resolvedDisplayName(
      muscleCode: normalizedCode,
      backendDisplayName: snapshot?.displayName,
    );
    final score =
        tappedEntry?.displayScore ?? _fallbackDisplayScore(tappedEntry?.status);
    final status = tappedEntry?.status ?? HeatmapStatus.unknown;
    final recoveryHours = provider.estimateRecoveryHours(
      muscleCode: normalizedCode,
      status: status,
    );
    final conditionLabel = _conditionLabel(
      status: status,
      recoveryHours: recoveryHours,
    );
    final message = '$displayName - 컨디션: $conditionLabel · 누적 컨디션 점수 $score';

    setState(() {
      _selectedMuscleCode = normalizedCode;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _normalizeMuscleCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) {
      return normalized;
    }
    return _muscleAliases[normalized] ?? normalized;
  }

  int _fallbackDisplayScore(HeatmapStatus? status) {
    switch (status ?? HeatmapStatus.unknown) {
      case HeatmapStatus.red:
        return 85;
      case HeatmapStatus.yellow:
        return 60;
      case HeatmapStatus.green:
        return 35;
      case HeatmapStatus.unknown:
        return 0;
    }
  }

  Color _colorForScore(double score) {
    final normalized = score.clamp(1.0, 3.0);
    if (normalized <= 2.0) {
      return Color.lerp(
            const Color(0xFF00E676),
            const Color(0xFFFFA726),
            normalized - 1.0,
          ) ??
          const Color(0xFF00E676);
    }
    return Color.lerp(
          const Color(0xFFFFA726),
          const Color(0xFFE53935),
          normalized - 2.0,
        ) ??
        const Color(0xFFFFA726);
  }

  Widget _buildStatusBadge(_ConditionScore score) {
    final label = _statusLabel(score.peak);
    final color = _colorForScore(score.peak);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Text(
        '$label · 평균 ${score.average.toStringAsFixed(1)} / 최고 ${score.peak.toStringAsFixed(1)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _statusLabel(double peakScore) {
    if (peakScore >= 2.6) {
      return '회복 필요';
    }
    if (peakScore >= 1.8) {
      return '회복 중';
    }
    return '회복 완료';
  }

  Widget _buildRecoveryInsightCard(HeatmapProvider provider) {
    final entries = provider.heatmapEntries;
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          '근육 컨디션 데이터를 수집하는 중입니다.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final rows = _buildRecoveryRows(provider, entries);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '근육 회복 예측',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '근육별 회복 상태와 예상 남은 시간을 그래프로 확인하세요.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: rows.length <= 4 ? rows.length * 58 : 232,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final selected = _selectedMuscleCode == row.muscleCode;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _onMuscleTapped(provider, row.muscleCode),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primaryGreen.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primaryGreen.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            row.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 9,
                              value: row.progress,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.10),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(row.color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 78,
                          child: Text(
                            row.remainingLabel,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: row.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_RecoveryBarRow> _buildRecoveryRows(
    HeatmapProvider provider,
    List<MuscleHeatmapEntry> entries,
  ) {
    final seenCodes = <String>{};
    final rows = <_RecoveryBarRow>[];

    for (final entry in entries) {
      final code = _normalizeMuscleCode(entry.muscleCode);
      if (!seenCodes.add(code)) {
        continue;
      }

      final resolvedEntry = provider.heatmapEntryByMuscleCode[code] ?? entry;
      final snapshot = provider.getRecoverySnapshot(code);
      final status = resolvedEntry.status;
      final muscleSize = _fallbackMuscleSize(code);
      final recoveryHours = provider.estimateRecoveryHours(
        muscleCode: code,
        status: status,
      );
      final maxHours = _maxRecoveryHours(muscleSize);
      final remainingHours =
          status == HeatmapStatus.green ? 0 : recoveryHours.clamp(0, maxHours);
      final rawProgress = maxHours == 0 ? 0.0 : remainingHours / maxHours;
      final progress =
          status == HeatmapStatus.green ? 0.08 : rawProgress.clamp(0.12, 1.0);

      rows.add(
        _RecoveryBarRow(
          muscleCode: code,
          displayName: _resolvedDisplayName(
            muscleCode: code,
            backendDisplayName: snapshot?.displayName,
          ),
          status: status,
          color: _statusColor(status),
          progress: progress,
          remainingLabel: _remainingLabel(status, remainingHours),
        ),
      );
    }

    rows.sort((a, b) {
      final byStatus = _statusRank(b.status).compareTo(_statusRank(a.status));
      if (byStatus != 0) {
        return byStatus;
      }
      return b.progress.compareTo(a.progress);
    });
    return rows;
  }

  int _maxRecoveryHours(MuscleSize size) {
    switch (size) {
      case MuscleSize.large:
        return 72;
      case MuscleSize.small:
        return 48;
      case MuscleSize.unknown:
        return 60;
    }
  }

  String _remainingLabel(HeatmapStatus status, int remainingHours) {
    if (status == HeatmapStatus.green) {
      return '회복 완료';
    }
    return '${remainingHours.clamp(1, 72)}시간 남음';
  }

  Color _statusColor(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return const Color(0xFFE53935);
      case HeatmapStatus.yellow:
        return const Color(0xFFFFA726);
      case HeatmapStatus.green:
        return AppTheme.primaryGreen;
      case HeatmapStatus.unknown:
        return const Color(0xFF60718F);
    }
  }

  int _statusRank(HeatmapStatus status) {
    switch (status) {
      case HeatmapStatus.red:
        return 4;
      case HeatmapStatus.yellow:
        return 3;
      case HeatmapStatus.green:
        return 2;
      case HeatmapStatus.unknown:
        return 1;
    }
  }

  MuscleSize _fallbackMuscleSize(String muscleCode) {
    final normalized = _normalizeMuscleCode(muscleCode);
    if (_largeMuscleCodes.contains(normalized)) {
      return MuscleSize.large;
    }
    return MuscleSize.small;
  }

  String _displayNameForCode(String muscleCode) {
    final normalized = _normalizeMuscleCode(muscleCode);
    return _muscleDisplayNameMap[normalized] ?? '근육 부위';
  }

  String _resolvedDisplayName({
    required String muscleCode,
    String? backendDisplayName,
  }) {
    final raw = (backendDisplayName ?? '').replaceAll('\n', ' ').trim();
    if (raw.isNotEmpty && !_containsAsciiLetter(raw)) {
      return raw;
    }
    return _displayNameForCode(muscleCode);
  }

  bool _containsAsciiLetter(String text) {
    return RegExp(r'[A-Za-z]').hasMatch(text);
  }

  String _conditionLabel({
    required HeatmapStatus status,
    required int recoveryHours,
  }) {
    switch (status) {
      case HeatmapStatus.red:
        return '회복 필요 (예상 ${recoveryHours.clamp(24, 72)}시간 남음)';
      case HeatmapStatus.yellow:
        return '회복 중 (예상 ${recoveryHours.clamp(12, 48)}시간 남음)';
      case HeatmapStatus.green:
        return '회복 완료';
      case HeatmapStatus.unknown:
        return '데이터 수집 중';
    }
  }
}

class _ConditionScore {
  const _ConditionScore({
    required this.average,
    required this.peak,
  });

  final double average;
  final double peak;
}

class _RecoveryBarRow {
  const _RecoveryBarRow({
    required this.muscleCode,
    required this.displayName,
    required this.status,
    required this.color,
    required this.progress,
    required this.remainingLabel,
  });

  final String muscleCode;
  final String displayName;
  final HeatmapStatus status;
  final Color color;
  final double progress;
  final String remainingLabel;
}

const Map<String, String> _muscleAliases = {
  'abs': 'rectus_abdominis',
  'abdominals': 'rectus_abdominis',
  'upper_abs': 'rectus_abdominis',
  'lower_abs': 'rectus_abdominis',
  'core': 'rectus_abdominis',
  'pectoralis_major': 'chest',
  'pecs': 'chest',
  'chest_major': 'chest',
  'anterior_deltoid': 'front_deltoid',
  'front_delts': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'side_deltoid': 'lateral_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'rear_delts': 'rear_deltoid',
  'quads': 'quadriceps',
  'rectus_femoris': 'rectus_femoris',
  'vastus_lateralis': 'vastus_lateralis',
  'vastus_medialis': 'vastus_medialis',
  'vastus_intermedius': 'vastus_intermedius',
  'hamstring': 'hamstrings',
  'biceps_femoris': 'biceps_femoris',
  'semitendinosus': 'semitendinosus',
  'semimembranosus': 'semimembranosus',
  'adductor_longus': 'adductor_longus',
  'adductor_brevis': 'adductor_brevis',
  'adductor_magnus': 'adductor_magnus',
  'hip_adductors': 'adductors',
  'hip_abductors': 'abductors',
  'abductor': 'abductors',
  'gluteus_maximus': 'gluteus_maximus',
  'gluteus_medius': 'gluteus_medius',
  'gluteus_minimus': 'gluteus_minimus',
  'lats': 'latissimus',
  'latissimus_dorsi': 'latissimus',
  'latissimus_lower': 'latissimus_lower',
  'latissimus_upper': 'latissimus_upper',
  'spinal_erectors': 'erector_spinae',
  'erectors': 'erector_spinae',
  'lumbar': 'lower_back',
  'biceps_brachii': 'biceps',
  'wrist_flexor': 'forearm_flexor',
  'wrist_extensor': 'forearm_extensor',
  'forearm': 'forearm_flexor',
  'forearms': 'forearm_flexor',
  'gastrocnemius_medial': 'gastrocnemius',
  'gastrocnemius_lateral': 'gastrocnemius',
  'calf': 'calves',
  'shin': 'tibialis_anterior',
  'upper_trap': 'trapezius',
  'middle_trap': 'trapezius',
  'lower_trap': 'trapezius',
  'cervical': 'neck',
};

const Set<String> _largeMuscleCodes = {
  'chest',
  'latissimus',
  'latissimus_lower',
  'latissimus_upper',
  'trapezius',
  'quadriceps',
  'rectus_femoris',
  'vastus_lateralis',
  'vastus_medialis',
  'vastus_intermedius',
  'hamstrings',
  'biceps_femoris',
  'semitendinosus',
  'semimembranosus',
  'glutes',
  'gluteus_maximus',
  'gluteus_medius',
  'gluteus_minimus',
  'calves',
  'gastrocnemius',
  'soleus',
  'erector_spinae',
  'lower_back',
  'adductors',
  'adductor_longus',
  'adductor_brevis',
  'adductor_magnus',
  'abductors',
  'hip_flexor',
};

const Map<String, String> _muscleDisplayNameMap = {
  'neck': '경부 근육',
  'chest': '대흉근',
  'pectoralis_minor': '소흉근',
  'serratus_anterior': '전거근',
  'front_deltoid': '전면 삼각근',
  'lateral_deltoid': '측면 삼각근',
  'rear_deltoid': '후면 삼각근',
  'trapezius': '승모근',
  'biceps': '상완이두근',
  'brachialis': '상완근',
  'triceps': '상완삼두근',
  'brachioradialis': '상완요골근',
  'forearm': '전완근',
  'forearm_flexor': '전완 굴근',
  'forearm_extensor': '전완 신근',
  'rectus_abdominis': '복직근',
  'obliques': '복사근',
  'hip_flexor': '장요근',
  'adductors': '내전근군',
  'adductor_longus': '장내전근',
  'adductor_brevis': '단내전근',
  'adductor_magnus': '대내전근',
  'abductors': '외전근군',
  'quadriceps': '대퇴사두근',
  'rectus_femoris': '대퇴직근',
  'vastus_lateralis': '외측광근',
  'vastus_medialis': '내측광근',
  'vastus_intermedius': '중간광근',
  'hamstrings': '햄스트링',
  'biceps_femoris': '대퇴이두근',
  'semitendinosus': '반건양근',
  'semimembranosus': '반막양근',
  'tibialis_anterior': '전경골근',
  'calves': '하퇴 삼두근',
  'gastrocnemius': '비복근',
  'soleus': '가자미근',
  'glutes': '둔근군',
  'gluteus_maximus': '대둔근',
  'gluteus_medius': '중둔근',
  'gluteus_minimus': '소둔근',
  'teres_major': '대원근',
  'teres_minor': '소원근',
  'latissimus': '광배근',
  'latissimus_lower': '광배근 하부',
  'latissimus_upper': '광배근 상부',
  'infraspinatus': '극하근',
  'supraspinatus': '극상근',
  'subscapularis': '견갑하근',
  'erector_spinae': '척추기립근',
  'lower_back': '요부 척추기립근',
};
