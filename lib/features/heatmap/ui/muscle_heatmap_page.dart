import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../data/heatmap_repository.dart';
import '../hook/heatmap_sync_hook.dart';
import '../model/heatmap_models.dart';
import 'heatmap_palette.dart';
import 'muscle_heatmap_container.dart';
import 'quick_workout_record_sheet.dart';

class MuscleHeatmapPage extends StatefulWidget {
  const MuscleHeatmapPage({
    super.key,
    this.bridgePayload,
    this.openQuickRecordOnStart = false,
    this.repository,
  });

  final MeasurementBridgePayload? bridgePayload;
  final bool openQuickRecordOnStart;
  final HeatmapRepositoryContract? repository;

  @override
  State<MuscleHeatmapPage> createState() => _MuscleHeatmapPageState();
}

class _MuscleHeatmapPageState extends State<MuscleHeatmapPage> {
  late final HeatmapSyncHook _hook;
  late final HeatmapRepositoryContract _repository;
  bool _isRecordSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? HeatmapRepository.fromEnvironment();
    _hook = HeatmapSyncHook(repository: _repository);
    _hook.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openQuickRecordOnStart && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 80), () async {
          if (!mounted) {
            return;
          }
          await _openQuickRecordSheet();
        });
      }
    });
  }

  @override
  void dispose() {
    _hook.dispose();
    super.dispose();
  }

  Future<void> _openQuickRecordSheet() async {
    if (_isRecordSheetOpen) {
      return;
    }

    _isRecordSheetOpen = true;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111317),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return QuickWorkoutRecordSheet(
          hook: _hook,
          onSaved: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('운동 기록 저장 완료 • 히트맵을 갱신했습니다.'),
              ),
            );
          },
        );
      },
    );
    _isRecordSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        title: Text(
          '컨디션 히트맵',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () => _hook.refreshHeatmap(),
            icon: const Icon(
              Icons.refresh,
              color: AppTheme.primaryGreen,
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _hook,
        builder: (context, child) {
          if (_hook.isLoading && _hook.entries.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (_hook.errorMessage != null && _hook.entries.isEmpty) {
            return _buildFatalFallback(
              message: _hook.errorMessage!,
            );
          }

          return RefreshIndicator(
            onRefresh: () => _hook.refreshHeatmap(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                if (widget.bridgePayload != null) ...[
                  _buildBridgeContext(widget.bridgePayload!),
                  const SizedBox(height: 14),
                ],
                if (_hook.errorMessage != null && _hook.entries.isNotEmpty) ...[
                  _buildNonBlockingErrorBanner(_hook.errorMessage!),
                  const SizedBox(height: 10),
                ],
                MuscleHeatmapContainer(
                  entries: _hook.entries,
                ),
                const SizedBox(height: 12),
                _buildStatusSummary(),
                const SizedBox(height: 8),
                _buildLegend(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('open_quick_record_button'),
                    onPressed: _hook.isMutating ? null : _openQuickRecordSheet,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(
                      _hook.isMutating ? '저장 중...' : '운동 기록하기',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _buildLastUpdatedLabel(_hook.lastSyncedAt),
                  style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBridgeContext(MeasurementBridgePayload payload) {
    final measuredAt = payload.measuredAt;
    final measuredAtLabel =
        '${measuredAt.month.toString().padLeft(2, '0')}/${measuredAt.day.toString().padLeft(2, '0')} '
        '${measuredAt.hour.toString().padLeft(2, '0')}:${measuredAt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '최근 정밀 분석 결과 연동됨',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _metricPill(
                icon: Icons.speed_outlined,
                text: '컨디션 점수 ${payload.fatigueScore.toStringAsFixed(2)}',
              ),
              _metricPill(
                icon: Icons.schedule_outlined,
                text: measuredAtLabel,
              ),
              if (payload.peakFrequency != null)
                _metricPill(
                  icon: Icons.graphic_eq,
                  text: '${payload.peakFrequency!.toStringAsFixed(1)}Hz',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNonBlockingErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                color: Colors.orange.shade100,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSummary() {
    final entries = _hook.entries;
    final redCount =
        entries.where((entry) => entry.status == HeatmapStatus.red).length;
    final yellowCount =
        entries.where((entry) => entry.status == HeatmapStatus.yellow).length;
    final greenCount =
        entries.where((entry) => entry.status == HeatmapStatus.green).length;

    return Row(
      children: [
        Expanded(
          child: _statusTile(
            label: '회복 필요',
            count: redCount,
            color: HeatmapPalette.red,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statusTile(
            label: '회복 중',
            count: yellowCount,
            color: HeatmapPalette.yellow,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statusTile(
            label: '회복 완료',
            count: greenCount,
            color: HeatmapPalette.green,
          ),
        ),
      ],
    );
  }

  Widget _statusTile({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '상태 범례',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        _legendRow(HeatmapStatus.red),
        const SizedBox(height: 4),
        _legendRow(HeatmapStatus.yellow),
        const SizedBox(height: 4),
        _legendRow(HeatmapStatus.green),
      ],
    );
  }

  Widget _legendRow(HeatmapStatus status) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: HeatmapPalette.colorForStatus(status),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            HeatmapPalette.labelForStatus(status),
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricPill({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _buildLastUpdatedLabel(DateTime? syncedAt) {
    if (syncedAt == null) {
      return '동기화 정보 없음';
    }

    final now = DateTime.now();
    final diff = now.difference(syncedAt);
    if (diff.inSeconds < 10) {
      return '업데이트: 방금';
    }
    if (diff.inMinutes < 1) {
      return '업데이트: ${diff.inSeconds}초 전';
    }
    if (diff.inHours < 1) {
      return '업데이트: ${diff.inMinutes}분 전';
    }
    return '업데이트: ${diff.inHours}시간 전';
  }

  Widget _buildFatalFallback({required String message}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: Colors.orangeAccent,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                '히트맵 데이터를 불러오지 못했습니다.',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _hook.refreshHeatmap(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('다시 시도'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '필요 dart-define: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY',
                style: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
