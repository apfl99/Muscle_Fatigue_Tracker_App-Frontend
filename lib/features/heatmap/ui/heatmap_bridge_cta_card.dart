import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../model/heatmap_models.dart';

class HeatmapBridgeCtaCard extends StatelessWidget {
  const HeatmapBridgeCtaCard({
    super.key,
    required this.payload,
    required this.onViewHeatmap,
    required this.onQuickRecord,
  });

  final MeasurementBridgePayload payload;
  final VoidCallback onViewHeatmap;
  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final measuredAt = payload.measuredAt;
    final measuredAtLabel =
        '${measuredAt.month.toString().padLeft(2, '0')}/${measuredAt.day.toString().padLeft(2, '0')} '
        '${measuredAt.hour.toString().padLeft(2, '0')}:${measuredAt.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2F2A), Color(0xFF121A17)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: AppTheme.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '분석이 끝났어요 · 3D 바디 맵으로 바로 확인해보세요',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildChip(
                icon: Icons.speed_outlined,
                label: '컨디션 점수 ${payload.fatigueScore.toStringAsFixed(2)}',
              ),
              _buildChip(
                icon: Icons.schedule_outlined,
                label: measuredAtLabel,
              ),
              if (payload.peakFrequency != null)
                _buildChip(
                  icon: Icons.graphic_eq,
                  label: '진동 ${payload.peakFrequency!.toStringAsFixed(1)}Hz',
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 390;
              final firstButton = ElevatedButton.icon(
                key: const ValueKey('bridge_view_heatmap_button'),
                onPressed: onViewHeatmap,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text(
                  '3D 바디 맵 보기',
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B96B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              final secondButton = OutlinedButton.icon(
                key: const ValueKey('bridge_quick_record_button'),
                onPressed: onQuickRecord,
                icon: const Icon(Icons.fitness_center_outlined),
                label: const Text(
                  '오늘 기록에 반영',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9EF7C6),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: firstButton),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: secondButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: firstButton),
                  const SizedBox(width: 10),
                  Expanded(child: secondButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: Colors.white70,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
