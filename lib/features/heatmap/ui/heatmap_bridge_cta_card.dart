import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_localization/easy_localization.dart';

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
          colors: [
            AppTheme.surface2,
            AppTheme.surface1,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: 24,
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
                  borderRadius: AppTheme.buttonRadius,
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
                  'bridgeCta.title'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textHigh,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
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
                label: 'bridgeCta.score'.tr(
                  namedArgs: {
                    'score': payload.fatigueScore.toStringAsFixed(2),
                  },
                ),
              ),
              _buildChip(
                icon: Icons.schedule_outlined,
                label: measuredAtLabel,
              ),
              if (payload.peakFrequency != null)
                _buildChip(
                  icon: Icons.graphic_eq,
                  label: 'bridgeCta.frequency'.tr(
                    namedArgs: {
                      'value': payload.peakFrequency!.toStringAsFixed(1),
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 390;
              final firstButton = ElevatedButton.icon(
                key: const ValueKey('bridge_view_heatmap_button'),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onViewHeatmap();
                },
                icon: const Icon(Icons.visibility_outlined),
                label: Text(
                  'bridgeCta.view3d'.tr(),
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: AppTheme.ctaOnBrand,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppTheme.buttonRadius,
                  ),
                ),
              );
              final secondButton = OutlinedButton.icon(
                key: const ValueKey('bridge_quick_record_button'),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onQuickRecord();
                },
                icon: const Icon(Icons.fitness_center_outlined),
                label: Text(
                  'bridgeCta.applyToday'.tr(),
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textHigh,
                  side: BorderSide(
                    color: AppTheme.borderSubtle,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppTheme.buttonRadius,
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
          color: AppTheme.surface2,
          borderRadius: const BorderRadius.all(Radius.circular(30)),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: AppTheme.textMedium,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: AppTheme.textMedium,
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
