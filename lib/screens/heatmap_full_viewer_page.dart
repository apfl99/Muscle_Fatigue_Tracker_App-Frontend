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
        final score = _calculateFatigueScore(provider.heatmapEntries);

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: const Text('인터랙티브 3D 컨디션 맵'),
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
                        label: const Text('정밀 분석으로 이동'),
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

  _FatigueScore _calculateFatigueScore(List<MuscleHeatmapEntry> entries) {
    if (entries.isEmpty) {
      return const _FatigueScore(average: 1.0, peak: 1.0);
    }

    final values = entries.map((entry) {
      if (entry.fatigueScore > 0) {
        return entry.fatigueScore.clamp(0.0, 3.0);
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

    return _FatigueScore(average: average, peak: peak);
  }

  void _onMuscleTapped(HeatmapProvider provider, String muscleCode) {
    final normalizedCode = _normalizeMuscleCode(muscleCode);
    final tappedEntry = provider.heatmapEntryByMuscleCode[normalizedCode];

    final snapshot = provider.getRecoverySnapshot(normalizedCode);
    final displayName = snapshot?.displayName.isNotEmpty == true
        ? snapshot!.displayName
        : _displayNameForCode(normalizedCode);
    final englishName = _englishNameForCode(normalizedCode);
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
    final message =
        '$displayName($englishName) - 컨디션: $conditionLabel · 누적 컨디션 점수 $score';

    setState(() {
      _selectedMuscleCode = normalizedCode;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _normalizeMuscleCode(String code) {
    switch (code.trim().toLowerCase()) {
      case 'front_delts':
        return 'front_deltoid';
      case 'lateral_delts':
        return 'lateral_deltoid';
      case 'rear_delts':
        return 'rear_deltoid';
      case 'quads':
        return 'quadriceps';
      case 'lats':
      case 'latissimus_dorsi':
        return 'latissimus';
      case 'abs':
      case 'abdominals':
        return 'rectus_abdominis';
      case 'gastrocnemius':
      case 'soleus':
        return 'calves';
      default:
        return code.trim().toLowerCase();
    }
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

  String _englishNameForCode(String muscleCode) {
    switch (muscleCode) {
      case 'chest':
        return 'Chest';
      case 'front_deltoid':
        return 'Front Deltoid';
      case 'lateral_deltoid':
        return 'Lateral Deltoid';
      case 'rear_deltoid':
        return 'Rear Deltoid';
      case 'biceps':
        return 'Biceps';
      case 'triceps':
        return 'Triceps';
      case 'latissimus':
        return 'Latissimus';
      case 'trapezius':
        return 'Trapezius';
      case 'quadriceps':
        return 'Quadriceps';
      case 'hamstrings':
        return 'Hamstrings';
      case 'glutes':
        return 'Glutes';
      case 'calves':
        return 'Calves';
      default:
        return muscleCode;
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

  Widget _buildStatusBadge(_FatigueScore score) {
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
            '근육을 탭하면 대근육/소근육 기준 예상 회복 시간을 안내합니다.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((entry) {
              final snapshot = provider.getRecoverySnapshot(entry.muscleCode);
              final muscleSize =
                  snapshot?.muscleSize ?? _fallbackMuscleSize(entry.muscleCode);
              final displayName = snapshot?.displayName.isNotEmpty == true
                  ? snapshot!.displayName
                  : _displayNameForCode(entry.muscleCode);
              final selected = _selectedMuscleCode == entry.muscleCode;

              return ChoiceChip(
                label: Text(
                  '$displayName (${_muscleSizeLabel(muscleSize)})',
                ),
                selected: selected,
                selectedColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: selected ? AppTheme.primaryGreen : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: selected
                      ? AppTheme.primaryGreen.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.14),
                ),
                onSelected: (_) {
                  _onMuscleTapped(provider, entry.muscleCode);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  MuscleSize _fallbackMuscleSize(String muscleCode) {
    switch (muscleCode) {
      case 'chest':
      case 'latissimus':
      case 'trapezius':
      case 'quadriceps':
      case 'hamstrings':
      case 'glutes':
      case 'calves':
      case 'gastrocnemius':
        return MuscleSize.large;
      default:
        return MuscleSize.small;
    }
  }

  String _displayNameForCode(String muscleCode) {
    switch (muscleCode) {
      case 'chest':
        return '대흉근';
      case 'front_deltoid':
        return '전면 삼각근';
      case 'lateral_deltoid':
        return '측면 삼각근';
      case 'rear_deltoid':
        return '후면 삼각근';
      case 'biceps':
        return '이두근';
      case 'triceps':
        return '삼두근';
      case 'latissimus':
        return '광배근';
      case 'trapezius':
        return '승모근';
      case 'quadriceps':
        return '대퇴사두근';
      case 'hamstrings':
        return '햄스트링';
      case 'glutes':
        return '둔근';
      case 'gastrocnemius':
      case 'calves':
        return '비복근';
      case 'rectus_abdominis':
        return '복직근';
      case 'obliques':
        return '복사근';
      case 'forearm_flexor':
        return '전완근 굴곡';
      case 'forearm_extensor':
        return '전완근 신전';
      case 'erector_spinae':
      case 'lower_back':
        return '척추기립근';
      default:
        return muscleCode;
    }
  }

  String _muscleSizeLabel(MuscleSize size) {
    switch (size) {
      case MuscleSize.large:
        return '대근육';
      case MuscleSize.small:
        return '소근육';
      case MuscleSize.unknown:
        return '미분류';
    }
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

class _FatigueScore {
  const _FatigueScore({
    required this.average,
    required this.peak,
  });

  final double average;
  final double peak;
}
