import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../providers/heatmap_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/heatmap_2d_viewer.dart';
import '../widgets/interactive_muscle_3d_viewer.dart';
import 'sensor_analysis_page.dart';

class HeatmapFullViewerPage extends StatefulWidget {
  const HeatmapFullViewerPage({super.key});

  @override
  State<HeatmapFullViewerPage> createState() => _HeatmapFullViewerPageState();
}

class _HeatmapFullViewerPageState extends State<HeatmapFullViewerPage> {
  String? _selectedMuscleCode;
  bool _use2DFallback = false;
  bool _fallbackSnackbarShown = false;
  bool _isMuscleSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<HeatmapProvider>(
      builder: (context, provider, _) {
        final score = _calculateConditionScore(provider.heatmapEntries);
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
                              child: _use2DFallback
                                  ? Heatmap2DViewer(
                                      entries: provider.heatmapEntries,
                                      exposeTestKey: true,
                                      onMuscleTap: (muscleCode) =>
                                          _onMuscleTapped(provider, muscleCode),
                                    )
                                  : InteractiveMuscle3DViewer(
                                      key: ValueKey(
                                        provider.hashCode.toString(),
                                      ),
                                      entries: provider.heatmapEntries,
                                      exposeBackgroundKey: true,
                                      showHotspots: false,
                                      highlightedMuscleCode:
                                          _selectedMuscleCode,
                                      onMuscleTap: (muscleCode) =>
                                          _onMuscleTapped(provider, muscleCode),
                                      onFallbackTo2D: _switchTo2DViewer,
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
                  AppTheme.gap16,
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
                  Container(
                    decoration: AppTheme.cardDecoration(
                      color: AppTheme.surface1,
                      borderRadius: 20,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const BannerAdWidget(
                      key: ValueKey('heatmap_full_viewer_banner'),
                      placeholderText: 'ads.slot',
                      padding: EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRecoveryInsightCard(provider),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _switchTo2DViewer() {
    if (!mounted || _use2DFallback) {
      return;
    }
    setState(() {
      _use2DFallback = true;
    });
    if (_fallbackSnackbarShown) {
      return;
    }
    _fallbackSnackbarShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('offline.viewerFallback2D'.tr())),
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
    var normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    normalized = normalized.replaceAll(RegExp(r'[\s\-./]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.endsWith('_muscle')) {
      normalized =
          normalized.substring(0, normalized.length - '_muscle'.length);
    }
    final tokens = normalized
        .split('_')
        .where((token) => token.trim().isNotEmpty)
        .toList();
    if (tokens.length > 1 && _muscleSideTokens.contains(tokens.first)) {
      tokens.removeAt(0);
    }
    if (tokens.length > 1 && _muscleSideTokens.contains(tokens.last)) {
      tokens.removeLast();
    }
    final compact = tokens.join('_');
    if (compact.isEmpty) {
      return '';
    }
    return _muscleAliases[compact] ?? compact;
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

  String _statusLabel(double peakScore) {
    if (peakScore >= 2.6) {
      return 'heatmap.status.needRecovery'.tr();
    }
    if (peakScore >= 1.8) {
      return 'heatmap.status.recovering'.tr();
    }
    return 'heatmap.status.recovered'.tr();
  }

  Widget _buildRecoveryInsightCard(HeatmapProvider provider) {
    final entries = provider.heatmapEntries;
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
      final renderCode = _renderGroupCodeFor(code);
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
        final displayNameKey = _renderGroupDisplayName[group.renderCode];
        return _RecoveryBarRow(
          muscleCode: group.renderCode,
          displayName: displayNameKey == null
              ? _displayNameForCode(group.renderCode)
              : displayNameKey.tr(),
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
                          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
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
                    '예상 회복 시간: ${recoveryHours.clamp(0, 72)}시간',
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

  String _renderGroupCodeFor(String code) {
    final normalized = _normalizeMuscleCode(code);
    return _renderGroupByMuscleCode[normalized] ?? normalized;
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
    if (normalized.isEmpty) {
      return context.locale.languageCode == 'ko' ? '근육' : 'Muscle';
    }
    final displayKey = _muscleDisplayNameMap[normalized];
    if (displayKey != null) {
      return displayKey.tr();
    }
    return _humanizeMuscleCode(normalized);
  }

  String _humanizeMuscleCode(String code) {
    final words = code
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return context.locale.languageCode == 'ko' ? '근육' : 'Muscle';
    }
    return words
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
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

const Set<String> _muscleSideTokens = {
  'left',
  'right',
  'l',
  'r',
  'lt',
  'rt',
  'lhs',
  'rhs',
};

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
  'deltoid_anterior': 'front_deltoid',
  'lateral_delts': 'lateral_deltoid',
  'side_deltoid': 'lateral_deltoid',
  'deltoid_lateral': 'lateral_deltoid',
  'posterior_deltoid': 'rear_deltoid',
  'rear_delts': 'rear_deltoid',
  'deltoid_posterior': 'rear_deltoid',
  'quads': 'quadriceps',
  'rectus_femoris': 'rectus_femoris',
  'vastus_lateralis': 'vastus_lateralis',
  'vastus_medialis': 'vastus_medialis',
  'vastus_intermedius': 'vastus_intermedius',
  'hamstring': 'hamstrings',
  'biceps_femoris': 'biceps_femoris',
  'semitendinosus': 'semitendinosus',
  'semimembranosus': 'semimembranosus',
  'adductor': 'adductors',
  'adductor_longus': 'adductor_longus',
  'adductor_brevis': 'adductor_brevis',
  'adductor_magnus': 'adductor_magnus',
  'hip_adductors': 'adductors',
  'hip_abductors': 'abductors',
  'abductor': 'abductors',
  'gluteus_maximus': 'gluteus_maximus',
  'gluteus_medius': 'gluteus_medius',
  'gluteus_minimus': 'gluteus_minimus',
  'glute_maximus': 'gluteus_maximus',
  'glute_medius': 'gluteus_medius',
  'glute_minimus': 'gluteus_minimus',
  'lats': 'latissimus',
  'latissimus_dorsi': 'latissimus',
  'latissimus_dorsi_lower': 'latissimus_lower',
  'latissimus_dorsi_upper': 'latissimus_upper',
  'latissimus_lower': 'latissimus_lower',
  'latissimus_upper': 'latissimus_upper',
  'spinal_erectors': 'erector_spinae',
  'erectors': 'erector_spinae',
  'lumbar': 'lower_back',
  'biceps_brachii': 'biceps',
  'triceps_brachii': 'triceps',
  'triceps_surae': 'calves',
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

const Map<String, String> _renderGroupByMuscleCode = {
  'chest': 'chest',
  'pectoralis_minor': 'chest',
  'serratus_anterior': 'chest',
  'front_deltoid': 'shoulders',
  'lateral_deltoid': 'shoulders',
  'rear_deltoid': 'shoulders',
  'biceps': 'upper_arms',
  'triceps': 'upper_arms',
  'brachialis': 'upper_arms',
  'brachioradialis': 'upper_arms',
  'forearm_flexor': 'upper_arms',
  'forearm_extensor': 'upper_arms',
  'rectus_abdominis': 'abs',
  'obliques': 'obliques',
  'quadriceps': 'quads',
  'rectus_femoris': 'quads',
  'vastus_lateralis': 'quads',
  'vastus_medialis': 'quads',
  'vastus_intermedius': 'quads',
  'adductors': 'quads',
  'adductor_longus': 'quads',
  'adductor_brevis': 'quads',
  'adductor_magnus': 'quads',
  'abductors': 'quads',
  'hip_flexor': 'quads',
  'hamstrings': 'posterior_chain',
  'biceps_femoris': 'posterior_chain',
  'semitendinosus': 'posterior_chain',
  'semimembranosus': 'posterior_chain',
  'glutes': 'posterior_chain',
  'gluteus_maximus': 'posterior_chain',
  'gluteus_medius': 'posterior_chain',
  'gluteus_minimus': 'posterior_chain',
  'calves': 'calves',
  'gastrocnemius': 'calves',
  'soleus': 'calves',
  'tibialis_anterior': 'calves',
  'latissimus': 'back',
  'latissimus_lower': 'back',
  'latissimus_upper': 'back',
  'teres_major': 'back',
  'infraspinatus': 'back',
  'supraspinatus': 'back',
  'teres_minor': 'back',
  'subscapularis': 'back',
  'erector_spinae': 'lower_posterior',
  'lower_back': 'lower_posterior',
  'trapezius': 'upper_posterior',
  'neck': 'upper_posterior',
};

const Map<String, String> _renderGroupDisplayName = {
  'chest': 'muscleGroup.chest',
  'shoulders': 'muscleGroup.shoulders',
  'upper_arms': 'muscleGroup.upperArms',
  'abs': 'muscleGroup.abs',
  'obliques': 'muscleGroup.obliques',
  'quads': 'muscleGroup.quads',
  'posterior_chain': 'muscleGroup.posteriorChain',
  'calves': 'muscleGroup.calves',
  'back': 'muscleGroup.back',
  'lower_posterior': 'muscleGroup.lowerPosterior',
  'upper_posterior': 'muscleGroup.upperPosterior',
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
  'neck': 'muscle.neck',
  'chest': 'muscle.chest',
  'pectoralis_minor': 'muscle.pectoralisMinor',
  'serratus_anterior': 'muscle.serratusAnterior',
  'front_deltoid': 'muscle.frontDeltoid',
  'lateral_deltoid': 'muscle.lateralDeltoid',
  'rear_deltoid': 'muscle.rearDeltoid',
  'trapezius': 'muscle.trapezius',
  'biceps': 'muscle.biceps',
  'brachialis': 'muscle.brachialis',
  'triceps': 'muscle.triceps',
  'brachioradialis': 'muscle.brachioradialis',
  'forearm': 'muscle.forearm',
  'forearm_flexor': 'muscle.forearmFlexor',
  'forearm_extensor': 'muscle.forearmExtensor',
  'rectus_abdominis': 'muscle.rectusAbdominis',
  'obliques': 'muscle.obliques',
  'hip_flexor': 'muscle.hipFlexor',
  'adductors': 'muscle.adductors',
  'adductor_longus': 'muscle.adductorLongus',
  'adductor_brevis': 'muscle.adductorBrevis',
  'adductor_magnus': 'muscle.adductorMagnus',
  'abductors': 'muscle.abductors',
  'quadriceps': 'muscle.quadriceps',
  'rectus_femoris': 'muscle.rectusFemoris',
  'vastus_lateralis': 'muscle.vastusLateralis',
  'vastus_medialis': 'muscle.vastusMedialis',
  'vastus_intermedius': 'muscle.vastusIntermedius',
  'hamstrings': 'muscle.hamstrings',
  'biceps_femoris': 'muscle.bicepsFemoris',
  'semitendinosus': 'muscle.semitendinosus',
  'semimembranosus': 'muscle.semimembranosus',
  'tibialis_anterior': 'muscle.tibialisAnterior',
  'calves': 'muscle.calves',
  'gastrocnemius': 'muscle.gastrocnemius',
  'soleus': 'muscle.soleus',
  'glutes': 'muscle.glutes',
  'gluteus_maximus': 'muscle.gluteusMaximus',
  'gluteus_medius': 'muscle.gluteusMedius',
  'gluteus_minimus': 'muscle.gluteusMinimus',
  'teres_major': 'muscle.teresMajor',
  'teres_minor': 'muscle.teresMinor',
  'latissimus': 'muscle.latissimus',
  'latissimus_lower': 'muscle.latissimusLower',
  'latissimus_upper': 'muscle.latissimusUpper',
  'infraspinatus': 'muscle.infraspinatus',
  'supraspinatus': 'muscle.supraspinatus',
  'subscapularis': 'muscle.subscapularis',
  'erector_spinae': 'muscle.erectorSpinae',
  'lower_back': 'muscle.lowerBack',
};
