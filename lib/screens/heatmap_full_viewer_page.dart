import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../features/heatmap/model/muscle_taxonomy.dart';
import '../providers/heatmap_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_disclaimer_footer.dart';
import '../widgets/interactive_muscle_3d_viewer.dart';
import 'sensor_analysis_page.dart';

class HeatmapFullViewerPage extends StatefulWidget {
  const HeatmapFullViewerPage({super.key});

  @override
  State<HeatmapFullViewerPage> createState() => _HeatmapFullViewerPageState();
}

class _HeatmapFullViewerPageState extends State<HeatmapFullViewerPage> {
  String? _selectedMuscleCode;
  bool _isMuscleSheetOpen = false;
  bool _autoFocusIntroConsumed = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<HeatmapProvider>(
      builder: (context, provider, _) {
        final score = _calculateConditionScore(provider.heatmapEntries);
        final suggestion = provider.nextWorkoutSuggestion;
        final targetMuscleCode = _normalizeMuscleCode(
          suggestion.targetMuscleCode,
        );
        final ssotCompleteEntries = _buildSsotCompleteEntries(provider);
        final shouldPlayAutoFocusIntro =
            !_autoFocusIntroConsumed && targetMuscleCode.isNotEmpty;
        if (shouldPlayAutoFocusIntro) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _autoFocusIntroConsumed) {
              return;
            }
            setState(() {
              _autoFocusIntroConsumed = true;
            });
          });
        }
        final pagePadding = AppTheme.resolvedPagePadding(context);
        final viewerHeight = (MediaQuery.sizeOf(context).height * 0.44).clamp(
          280.0,
          520.0,
        );

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            title: Text('heatmap.title'.tr()),
            backgroundColor: AppTheme.darkBackground,
            foregroundColor: AppTheme.textHigh,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: pagePadding.copyWith(top: 12, bottom: 14),
              child: Column(
                children: [
                  SizedBox(
                    height: viewerHeight.toDouble(),
                    child: Container(
                      decoration: AppTheme.cardDecoration(
                        color: AppTheme.cardDark,
                        borderRadius: 24,
                      ),
                      child: ClipRRect(
                        borderRadius: AppTheme.cardRadius,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: InteractiveMuscle3DViewer(
                                key: const ValueKey(
                                  'heatmap_full_interactive_muscle_3d_viewer',
                                ),
                                entries: ssotCompleteEntries,
                                exposeBackgroundKey: true,
                                showHotspots: false,
                                highlightedMuscleCode: _selectedMuscleCode,
                                recommendedMuscleCode: targetMuscleCode,
                                autoFocusTargetMuscleCode: targetMuscleCode,
                                enableAutoFocusIntro: shouldPlayAutoFocusIntro,
                                onMuscleTap: (muscleCode) =>
                                    _onMuscleTapped(provider, muscleCode),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              top: 14,
                              child: _buildStatusBadge(score),
                            ),
                            Positioned(
                              right: 14,
                              top: 14,
                              child: _buildTargetBadge(targetMuscleCode),
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
                  AppTheme.gap16,
                  _buildTargetSuggestionCard(
                    provider: provider,
                    suggestion: suggestion,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: provider.isLoading
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  provider.refreshAll();
                                },
                          icon: const Icon(Icons.refresh),
                          label: Text('common.refresh'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('go_sensor_analysis_button'),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SensorAnalysisPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.analytics_outlined),
                          label: Text('common.viewDetailAnalysis'.tr()),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRecoveryInsightCard(provider, ssotCompleteEntries),
                  const SizedBox(height: 12),
                  const AppDisclaimerFooter(compact: true),
                ],
              ),
            ),
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
    HapticFeedback.lightImpact();
    final normalizedCode = _normalizeMuscleCode(muscleCode);
    final tappedEntry = provider.heatmapEntryByMuscleCode[normalizedCode];
    final snapshot = provider.getRecoverySnapshot(normalizedCode);
    final displayName = _resolvedDisplayName(
      muscleCode: normalizedCode,
      heatmapDisplayNameKo: tappedEntry?.displayNameKo,
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
    final message = 'heatmap.muscleTapMessage'.tr(
      namedArgs: {
        'muscle': displayName,
        'condition': conditionLabel,
        'score': score.toString(),
      },
    );

    setState(() {
      _selectedMuscleCode = normalizedCode;
    });

    _showMusclePerformanceSheet(
      muscleCode: normalizedCode,
      displayName: displayName,
      status: status,
      conditionLabel: conditionLabel,
      score: score,
      recoveryHours: recoveryHours,
      relatedMuscles: '',
      summaryMessage: message,
    );
  }

  String _normalizeMuscleCode(String code) {
    return normalizeCanonicalMuscleCode(code);
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
        color: AppTheme.surface1.withValues(alpha: 0.72),
        borderRadius: AppTheme.buttonRadius,
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Text(
        'heatmap.statusBadge'.tr(
          namedArgs: {
            'label': label,
            'average': score.average.toStringAsFixed(1),
            'peak': score.peak.toStringAsFixed(1),
          },
        ),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTargetBadge(String targetMuscleCode) {
    if (targetMuscleCode.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('next_workout_target_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface1.withValues(alpha: 0.78),
        borderRadius: AppTheme.buttonRadius,
        border:
            Border.all(color: const Color(0xFF4BB9E6).withValues(alpha: 0.64)),
      ),
      child: Text(
        'heatmap.nextWorkout.badge'.tr(
          namedArgs: {'muscle': _displayNameForCode(targetMuscleCode)},
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF77D3FF),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildTargetSuggestionCard({
    required HeatmapProvider provider,
    required NextWorkoutSuggestion suggestion,
  }) {
    final targetCode = _normalizeMuscleCode(suggestion.targetMuscleCode);
    final targetName = _displayNameForCode(targetCode);
    final overloaded = suggestion.overloadedMuscleCodes
        .take(2)
        .map(_displayNameForCode)
        .join(', ');
    final copy = overloaded.isEmpty
        ? 'heatmap.nextWorkout.copyFallback'.tr(
            namedArgs: {'target': targetName},
          )
        : 'heatmap.nextWorkout.copy'.tr(
            namedArgs: {
              'overloaded': overloaded,
              'target': targetName,
            },
          );
    final confidencePercent =
        (suggestion.confidence * 100).round().clamp(0, 100);
    return Container(
      key: const Key('next_workout_suggestion_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface1,
        borderRadius: 18,
        borderColor: const Color(0xFF2D6F8C).withValues(alpha: 0.55),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF3EA9DE).withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.track_changes_rounded,
                  color: Color(0xFF66C9F8),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'heatmap.nextWorkout.title'.tr(),
                  style: TextStyle(
                    color: AppTheme.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'heatmap.nextWorkout.confidence'.tr(
                  namedArgs: {'value': '$confidencePercent'},
                ),
                style: const TextStyle(
                  color: Color(0xFF77D3FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            copy,
            style: TextStyle(
              color: AppTheme.textMedium,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetricPill(
                icon: Icons.bolt_rounded,
                label: 'heatmap.metrics.performance'.tr(),
                value: provider.performanceScore.toString(),
              ),
              const SizedBox(width: 8),
              _buildMetricPill(
                icon: Icons.fitness_center_rounded,
                label: 'heatmap.metrics.volume'.tr(),
                value: provider.todayWorkoutVolume.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface2.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.textMedium),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$label · $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(double peakScore) {
    if (peakScore >= 2.6) {
      return 'heatmap.status.needRecovery'.tr();
    }
    if (peakScore >= 1.8) {
      return 'heatmap.status.recovering'.tr();
    }
    return 'heatmap.status.recovered'.tr();
  }

  Widget _buildRecoveryInsightCard(
    HeatmapProvider provider,
    List<MuscleHeatmapEntry> entries,
  ) {
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(),
        child: Text(
          'heatmap.collectingMuscleData'.tr(),
          style: TextStyle(color: AppTheme.textMedium),
        ),
      );
    }

    final rows = _buildRecoveryRows(provider, entries);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'heatmap.recoveryPrediction.title'.tr(),
            style: TextStyle(
              color: AppTheme.textHigh,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'heatmap.recoveryPrediction.description'.tr(),
            style: TextStyle(color: AppTheme.textMedium, fontSize: 12),
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
                  key: Key('recovery_row_${row.muscleCode}'),
                  borderRadius: AppTheme.buttonRadius,
                  onTap: () => _onRecoveryRowTapped(row),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primaryGreen.withValues(alpha: 0.10)
                          : AppTheme.surface2.withValues(alpha: 0.45),
                      borderRadius: AppTheme.buttonRadius,
                      border: Border.all(
                        color: selected
                            ? AppTheme.primaryGreen.withValues(alpha: 0.5)
                            : AppTheme.borderSubtle,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.textHigh,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (row.relatedMuscles.isNotEmpty)
                                Text(
                                  row.relatedMuscles,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textMedium,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 9,
                              value: row.progress,
                              backgroundColor:
                                  AppTheme.surface1.withValues(alpha: 0.60),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(row.color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
    final grouped = <String, _RecoveryGroupAccumulator>{};
    final resolvedByCode = provider.heatmapEntryByMuscleCode;

    for (final entry in entries) {
      final code = _normalizeMuscleCode(entry.muscleCode);
      if (code.isEmpty) {
        continue;
      }
      final renderCode = _normalizeMuscleCode(code);
      final resolvedEntry = resolvedByCode[code] ?? entry;
      final snapshot = provider.getRecoverySnapshot(code);
      final status = resolvedEntry.status;
      final muscleSize = _fallbackMuscleSize(code);
      final maxHoursForMuscle = _maxRecoveryHours(muscleSize);
      final estimatedHours = provider.estimateRecoveryHours(
        muscleCode: code,
        status: status,
      );
      final remainingHours = status == HeatmapStatus.green
          ? 0
          : estimatedHours.clamp(0, maxHoursForMuscle);
      final resolvedName = _resolvedDisplayName(
        muscleCode: code,
        heatmapDisplayNameKo: resolvedEntry.displayNameKo,
        backendDisplayName: snapshot?.displayName,
      );

      final accumulator = grouped.putIfAbsent(
        renderCode,
        () => _RecoveryGroupAccumulator(renderCode: renderCode),
      );
      accumulator.absorb(
        status: status,
        maxHours: maxHoursForMuscle,
        remainingHours: remainingHours,
        relatedMuscleName: resolvedName,
      );
    }

    final rows = grouped.values.map(
      (group) {
        return _RecoveryBarRow(
          muscleCode: group.renderCode,
          displayName: _displayNameForCode(group.renderCode),
          relatedMuscles: _compactMuscleNames(group.relatedMuscles),
          status: group.status,
          color: _statusColor(group.status),
          progress: group.progress,
          remainingHours: group.remainingHours,
          remainingLabel: _remainingLabel(group.status, group.remainingHours),
        );
      },
    ).toList();

    rows.sort((a, b) {
      final byStatus = _statusRank(b.status).compareTo(_statusRank(a.status));
      if (byStatus != 0) {
        return byStatus;
      }
      return b.progress.compareTo(a.progress);
    });
    return rows;
  }

  List<MuscleHeatmapEntry> _buildSsotCompleteEntries(HeatmapProvider provider) {
    final byCode = provider.heatmapEntryByMuscleCode;
    final complete = <MuscleHeatmapEntry>[];
    for (final code in canonicalDetailedMuscleCodes) {
      final existing = byCode[code];
      if (existing != null) {
        complete.add(existing);
        continue;
      }
      complete.add(
        MuscleHeatmapEntry(
          muscleCode: code,
          status: HeatmapStatus.unknown,
        ),
      );
    }
    return complete;
  }

  void _onRecoveryRowTapped(_RecoveryBarRow row) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMuscleCode = row.muscleCode;
    });
    final detail = row.relatedMuscles.isEmpty
        ? ''
        : 'heatmap.relatedMusclesSuffix'.tr(args: [row.relatedMuscles]);
    final statusLabel = _conditionLabel(
      status: row.status,
      recoveryHours: row.remainingHours,
    );
    final summaryMessage = 'heatmap.recoveryTapMessage'.tr(
      namedArgs: {
        'muscle': row.displayName,
        'detail': detail,
        'condition': statusLabel,
      },
    );
    _showMusclePerformanceSheet(
      muscleCode: row.muscleCode,
      displayName: row.displayName,
      status: row.status,
      conditionLabel: statusLabel,
      score: _fallbackDisplayScore(row.status),
      recoveryHours: row.remainingHours,
      relatedMuscles: row.relatedMuscles,
      summaryMessage: summaryMessage,
    );
  }

  Future<void> _showMusclePerformanceSheet({
    required String muscleCode,
    required String displayName,
    required HeatmapStatus status,
    required String conditionLabel,
    required int score,
    required int recoveryHours,
    required String relatedMuscles,
    required String summaryMessage,
  }) async {
    if (!mounted || _isMuscleSheetOpen) {
      return;
    }
    _isMuscleSheetOpen = true;
    final statusColor = _statusColor(status);
    final normalizedProgress = (score / 100.0).clamp(0.0, 1.0);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: false,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            key: const Key('muscle_performance_sheet'),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: AppTheme.surface1,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.34),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderSubtle,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.bolt_rounded,
                        size: 20,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              color: AppTheme.textHigh,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conditionLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppTheme.textMedium,
                      ),
                    ),
                  ],
                ),
                if (relatedMuscles.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    relatedMuscles,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textMedium,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.cardDecoration(
                    color: AppTheme.surface2.withValues(alpha: 0.64),
                    borderRadius: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$score',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '/100',
                            style: TextStyle(
                              color: AppTheme.textMedium,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surface1.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.borderSubtle),
                            ),
                            child: Text(
                              muscleCode,
                              style: TextStyle(
                                color: AppTheme.textMedium,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: normalizedProgress,
                          minHeight: 9,
                          backgroundColor: AppTheme.surface1.withValues(
                            alpha: 0.70,
                          ),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(statusColor),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        summaryMessage,
                        style: TextStyle(
                          color: AppTheme.textMedium,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface2.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Text(
                    'heatmap.recoveryPrediction.estimatedHours'.tr(
                      namedArgs: {
                        'hours': recoveryHours.clamp(0, 72).toString(),
                      },
                    ),
                    style: TextStyle(
                      color: AppTheme.textHigh,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _isMuscleSheetOpen = false;
    }
  }

  String _compactMuscleNames(Set<String> names) {
    if (names.isEmpty) {
      return '';
    }
    final sorted = names.toList()..sort();
    final picked = sorted.take(2).toList();
    if (sorted.length > 2) {
      return 'common.andMore'.tr(args: [picked.join(', ')]);
    }
    return picked.join(', ');
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
      return 'heatmap.status.recovered'.tr();
    }
    return 'heatmap.remainingHours'.tr(
      namedArgs: {'hours': remainingHours.clamp(1, 72).toString()},
    );
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
        return const Color(0xFF42A5F5);
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
    if (normalized.isEmpty) {
      return 'muscle.unknown'.tr();
    }

    final displayKey = _muscleDisplayNameMap[normalized];
    if (displayKey != null) {
      return displayKey.tr();
    }

    final dynamicKey = 'muscle.${_snakeToCamelCase(normalized)}';
    final translated = dynamicKey.tr();
    if (translated != dynamicKey) {
      return translated;
    }

    return 'muscle.unknown'.tr();
  }

  String _snakeToCamelCase(String value) {
    final tokens = value.split('_').where((token) => token.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return value;
    }
    return tokens.first +
        tokens
            .skip(1)
            .map((token) => '${token[0].toUpperCase()}${token.substring(1)}')
            .join();
  }

  String _resolvedDisplayName({
    required String muscleCode,
    String? heatmapDisplayNameKo,
    String? backendDisplayName,
  }) {
    if (context.locale.languageCode != 'ko') {
      return _displayNameForCode(muscleCode);
    }
    final heatmapName = _sanitizeMuscleDisplayName(heatmapDisplayNameKo);
    if (heatmapName != null) {
      return heatmapName;
    }
    final backendName = _sanitizeMuscleDisplayName(backendDisplayName);
    if (backendName != null) {
      return backendName;
    }
    if (kDebugMode) {
      debugPrint(
        '[HeatmapContract] display_name_ko 누락/placeholder 감지: muscle_code=$muscleCode',
      );
    }
    return _displayNameForCode(muscleCode);
  }

  String? _sanitizeMuscleDisplayName(String? raw) {
    final value = (raw ?? '').replaceAll('\n', ' ').trim();
    if (value.isEmpty) {
      return null;
    }
    final compact = value.toLowerCase().replaceAll(RegExp(r'[\s_\-./]'), '');
    const placeholders = <String>{
      '근육부위',
      '기타근육',
      '알수없음',
      '알수없는근육',
      'unknown',
      'other',
      'muscle',
      'muscles',
      'na',
      'none',
      'null',
    };
    if (placeholders.contains(compact)) {
      return null;
    }
    if (RegExp(r'[A-Za-z]').hasMatch(value)) {
      return null;
    }
    return value;
  }

  String _conditionLabel({
    required HeatmapStatus status,
    required int recoveryHours,
  }) {
    switch (status) {
      case HeatmapStatus.red:
        return 'heatmap.condition.needRecovery'.tr(
          namedArgs: {'hours': recoveryHours.clamp(24, 72).toString()},
        );
      case HeatmapStatus.yellow:
        return 'heatmap.condition.recovering'.tr(
          namedArgs: {'hours': recoveryHours.clamp(12, 48).toString()},
        );
      case HeatmapStatus.green:
        return 'heatmap.status.recovered'.tr();
      case HeatmapStatus.unknown:
        return 'heatmap.status.collecting'.tr();
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
    required this.relatedMuscles,
    required this.status,
    required this.color,
    required this.progress,
    required this.remainingHours,
    required this.remainingLabel,
  });

  final String muscleCode;
  final String displayName;
  final String relatedMuscles;
  final HeatmapStatus status;
  final Color color;
  final double progress;
  final int remainingHours;
  final String remainingLabel;
}

class _RecoveryGroupAccumulator {
  _RecoveryGroupAccumulator({required this.renderCode});

  final String renderCode;
  final Set<String> relatedMuscles = <String>{};
  HeatmapStatus status = HeatmapStatus.unknown;
  int maxHours = 0;
  int remainingHours = 0;

  void absorb({
    required HeatmapStatus status,
    required int maxHours,
    required int remainingHours,
    required String relatedMuscleName,
  }) {
    if (_statusRank(status) > _statusRank(this.status)) {
      this.status = status;
    }
    this.maxHours = math.max(this.maxHours, maxHours);
    this.remainingHours = math.max(this.remainingHours, remainingHours);
    if (relatedMuscleName.trim().isNotEmpty) {
      relatedMuscles.add(relatedMuscleName.trim());
    }
  }

  double get progress {
    final safeMaxHours = maxHours == 0 ? 1 : maxHours;
    final raw = remainingHours / safeMaxHours;
    if (status == HeatmapStatus.green) {
      return 0.08;
    }
    return raw.clamp(0.12, 1.0);
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
}

const Set<String> _largeMuscleCodes = {
  'pectoralis_major_upper',
  'pectoralis_major_sternal',
  'pectoralis_major_lower',
  'pectoralis_minor',
  'deltoid_anterior',
  'deltoid_lateral',
  'deltoid_posterior',
  'rotator_cuff',
  'latissimus_dorsi',
  'rhomboids',
  'teres_major',
  'trapezius_upper',
  'trapezius_middle',
  'trapezius_lower',
  'biceps_long_head',
  'biceps_short_head',
  'brachialis',
  'triceps_long_head',
  'triceps_lateral_head',
  'triceps_medial_head',
  'forearm_flexors',
  'forearm_extensors',
  'rectus_abdominis',
  'external_obliques',
  'serratus_anterior',
  'rectus_femoris',
  'vastus_lateralis',
  'vastus_medialis',
  'biceps_femoris',
  'semitendinosus',
  'gluteus_maximus',
  'gluteus_medius',
  'gastrocnemius',
  'soleus',
  'erector_spinae',
};

const Map<String, String> _muscleDisplayNameMap = {
  'pectoralis_major_upper': 'muscle.pectoralisMajorUpper',
  'pectoralis_major_sternal': 'muscle.pectoralisMajorSternal',
  'pectoralis_major_lower': 'muscle.pectoralisMajorLower',
  'pectoralis_minor': 'muscle.pectoralisMinor',
  'serratus_anterior': 'muscle.serratusAnterior',
  'deltoid_anterior': 'muscle.frontDeltoid',
  'deltoid_lateral': 'muscle.lateralDeltoid',
  'deltoid_posterior': 'muscle.rearDeltoid',
  'rotator_cuff': 'muscle.rotatorCuff',
  'trapezius_upper': 'muscle.trapeziusUpper',
  'trapezius_middle': 'muscle.trapeziusMiddle',
  'trapezius_lower': 'muscle.trapeziusLower',
  'biceps_long_head': 'muscle.bicepsLongHead',
  'biceps_short_head': 'muscle.bicepsShortHead',
  'brachialis': 'muscle.brachialis',
  'triceps_long_head': 'muscle.tricepsLongHead',
  'triceps_lateral_head': 'muscle.tricepsLateralHead',
  'triceps_medial_head': 'muscle.tricepsMedialHead',
  'forearm_flexors': 'muscle.forearmFlexors',
  'forearm_extensors': 'muscle.forearmExtensors',
  'rectus_abdominis': 'muscle.rectusAbdominis',
  'external_obliques': 'muscle.externalObliques',
  'rectus_femoris': 'muscle.rectusFemoris',
  'vastus_lateralis': 'muscle.vastusLateralis',
  'vastus_medialis': 'muscle.vastusMedialis',
  'biceps_femoris': 'muscle.bicepsFemoris',
  'semitendinosus': 'muscle.semitendinosus',
  'tibialis_anterior': 'muscle.tibialisAnterior',
  'gastrocnemius': 'muscle.gastrocnemius',
  'soleus': 'muscle.soleus',
  'gluteus_maximus': 'muscle.gluteusMaximus',
  'gluteus_medius': 'muscle.gluteusMedius',
  'teres_major': 'muscle.teresMajor',
  'latissimus_dorsi': 'muscle.latissimus',
  'erector_spinae': 'muscle.erectorSpinae',
  'rhomboids': 'muscle.rhomboids',
};
