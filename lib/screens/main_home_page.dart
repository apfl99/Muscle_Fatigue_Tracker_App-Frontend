import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../features/heatmap/utils/muscle_label_localizer.dart';
import '../providers/heatmap_provider.dart';
import '../services/supabase_service.dart' show WorkoutLogRecord;
import '../theme/app_theme.dart';
import '../widgets/app_disclaimer_footer.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/interactive_muscle_3d_viewer.dart';
import '../widgets/workout_log_bottom_sheet.dart';
import 'heatmap_full_viewer_page.dart';
import 'measurement_history_page.dart';
import 'sensor_analysis_page.dart';

class MainHomePage extends StatefulWidget {
  const MainHomePage({
    super.key,
    this.openLogSheetOnStart = false,
    this.bridgePayload,
  });

  final bool openLogSheetOnStart;
  final MeasurementBridgePayload? bridgePayload;

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage>
    with SingleTickerProviderStateMixin {
  static const String _onboardingSeenKey = 'v2_onboarding_seen';

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  bool _isPulseRunning = false;
  bool _homeOrbitIntroConsumed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.35, end: 0.95).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await context.read<HeatmapProvider>().initialize();
      await _showOnboardingIfNeeded();

      if (widget.openLogSheetOnStart && mounted) {
        await _openWorkoutLogSheet(bridgePayload: widget.bridgePayload);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.stop();
    _pulseController.dispose();
    super.dispose();
  }

  void _syncPulseAnimation(bool shouldRun) {
    if (shouldRun == _isPulseRunning) {
      return;
    }
    _isPulseRunning = shouldRun;
    if (shouldRun) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  Future<void> _showOnboardingIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_onboardingSeenKey) ?? false;
    if (seen || !mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: AppTheme.cardDecoration(
            color: AppTheme.surface1,
            borderRadius: 28,
            borderColor: AppTheme.primaryGreen.withValues(alpha: 0.24),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'home.onboarding.title'.tr(),
                style: const TextStyle(
                  color: AppTheme.primaryGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'home.onboarding.headline'.tr(),
                style: TextStyle(
                  color: AppTheme.textHigh,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'home.onboarding.description'.tr(),
                style: TextStyle(
                  color: AppTheme.textMedium,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: AppTheme.ctaOnBrand,
                    minimumSize: const Size.fromHeight(50),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppTheme.buttonRadius,
                    ),
                  ),
                  child: Text(
                    'common.start'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    await prefs.setBool(_onboardingSeenKey, true);
  }

  Future<void> _openWorkoutLogSheet({
    MeasurementBridgePayload? bridgePayload,
  }) async {
    await HapticFeedback.lightImpact();
    if (!mounted) {
      return;
    }
    if (kDebugMode) {
      debugPrint('[funnel] on_fab_clicked {"source":"main_home_fab"}');
    }
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkoutLogBottomSheet(bridgePayload: bridgePayload),
    );
    if (!mounted) {
      return;
    }

    if (result == true) {
      final provider = context.read<HeatmapProvider>();
      if (provider.lastSaveQueuedOffline) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('home.logSaved'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pagePadding = AppTheme.resolvedPagePadding(context);
    final streakDays = context.select<HeatmapProvider, int>(
      (provider) => provider.streakDays,
    );
    final workoutLogs = context.select<HeatmapProvider, List<WorkoutLogRecord>>(
      (provider) => provider.workoutLogs,
    );
    final isLoading = context.select<HeatmapProvider, bool>(
      (provider) => provider.isLoading,
    );
    final errorMessage = context.select<HeatmapProvider, String?>(
      (provider) => provider.errorMessage,
    );
    final heatmapEntries =
        context.select<HeatmapProvider, List<MuscleHeatmapEntry>>(
      (provider) => provider.heatmapEntries,
    );
    final targetMuscleCode = context.select<HeatmapProvider, String>(
      (provider) => provider.nextWorkoutSuggestion.targetMuscleCode,
    );

    final timelineItems = _buildTimelineItems(workoutLogs: workoutLogs);
    final showPulseGuide = timelineItems.isEmpty;
    _syncPulseAnimation(showPulseGuide);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        foregroundColor: AppTheme.textHigh,
        titleSpacing: 8,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = MediaQuery.sizeOf(context).width < 360;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: isSmall ? 26 : 32,
                    height: isSmall ? 26 : 32,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(width: isSmall ? 6 : 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isSmall ? 'M Care' : 'Muscle Care',
                      style: GoogleFonts.poppins(
                        fontSize: isSmall ? 16 : 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textHigh,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          _buildAppBarIcon(
            icon: Icons.analytics_outlined,
            tooltip: 'home.tooltips.analysis'.tr(),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SensorAnalysisPage(),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          _buildAppBarIcon(
            icon: Icons.history,
            tooltip: 'home.tooltips.history'.tr(),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MeasurementHistoryPage(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('main_home_fab'),
        onPressed: () => _openWorkoutLogSheet(),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: AppTheme.ctaOnBrand,
        icon: const Icon(Icons.add),
        label: Text(
          'home.fab.label'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppTheme.primaryGreen,
              onRefresh: () => context.read<HeatmapProvider>().refreshAll(),
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: pagePadding.copyWith(top: 8, bottom: 120),
                children: [
                  _buildStreakCard(streakDays),
                  AppTheme.gap16,
                  _buildHeroCard(
                    heatmapEntries: heatmapEntries,
                    isLoading: isLoading,
                    targetMuscleCode: targetMuscleCode,
                  ),
                  AppTheme.gap16,
                  _buildTimelineCard(
                    timelineItems: timelineItems,
                    isLoading: isLoading,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    _buildFallbackCard(errorMessage),
                  ],
                  const SizedBox(height: 12),
                  _buildNaturalBannerSlot(),
                  const SizedBox(height: 12),
                  const AppDisclaimerFooter(compact: true),
                ],
              ),
            ),
            if (showPulseGuide) _buildPulseFabGuide(),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakCard(int streakDays) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: Colors.orangeAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'home.streak.day'.tr(
                    namedArgs: {'day': streakDays.toString().padLeft(2, '0')},
                  ),
                  style: TextStyle(
                    color: AppTheme.textHigh,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'home.streak.subtitle'.tr(),
                  style: TextStyle(color: AppTheme.textMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required List<MuscleHeatmapEntry> heatmapEntries,
    required bool isLoading,
    required String targetMuscleCode,
  }) {
    final targetDisplayName = _displayMuscleName(targetMuscleCode);
    final shouldPlayAutoFocusIntro =
        !_homeOrbitIntroConsumed && targetMuscleCode.trim().isNotEmpty;
    if (shouldPlayAutoFocusIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _homeOrbitIntroConsumed) {
          return;
        }
        _homeOrbitIntroConsumed = true;
      });
    }
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: InkWell(
        key: const Key('hero_preview_card'),
        borderRadius: AppTheme.cardRadius,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const HeatmapFullViewerPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'home.hero.title'.tr(),
                style: TextStyle(
                  color: AppTheme.textHigh,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'home.hero.subtitle'.tr(),
                style: TextStyle(color: AppTheme.textMedium),
              ),
              if (targetMuscleCode.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'home.hero.nextTarget'.tr(
                    namedArgs: {'muscle': targetDisplayName},
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7CD0FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: AppTheme.cardRadius,
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: ClipRRect(
                  borderRadius: AppTheme.cardRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Container(
                          key: const Key('home_preview_background'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: InteractiveMuscle3DViewer(
                            entries: heatmapEntries,
                            borderRadius: 16,
                            interactive: true,
                            autoRotate: true,
                            showHotspots: false,
                            recommendedMuscleCode: targetMuscleCode,
                            autoFocusTargetMuscleCode: targetMuscleCode,
                            enableAutoFocusIntro: shouldPlayAutoFocusIntro,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surface1.withValues(alpha: 0.72),
                            borderRadius: AppTheme.buttonRadius,
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          child: Text(
                            'home.hero.tapDetail'.tr(),
                            style: TextStyle(
                              color: AppTheme.textHigh,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      if (isLoading)
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineCard({
    required List<_TimelineItem> timelineItems,
    required bool isLoading,
  }) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'home.timeline.title'.tr(),
            style: TextStyle(
              color: AppTheme.textHigh,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGreen),
              ),
            )
          else if (timelineItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'home.timeline.empty'.tr(),
                style: TextStyle(color: AppTheme.textMedium, height: 1.4),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final item = timelineItems[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.icon, color: item.color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              color: AppTheme.textHigh,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: TextStyle(
                              color: AppTheme.textMedium,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(item.occurredAt),
                      style: TextStyle(color: AppTheme.textLow, fontSize: 11),
                    ),
                  ],
                );
              },
              separatorBuilder: (_, __) => Divider(
                color: AppTheme.borderSubtle,
                height: 16,
              ),
              itemCount: timelineItems.length,
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.accentDanger.withValues(alpha: 0.10),
        borderRadius: 16,
        borderColor: AppTheme.accentDanger.withValues(alpha: 0.30),
      ),
      child: Text(
        message.tr(),
        style: const TextStyle(color: AppTheme.accentDanger),
      ),
    );
  }

  Widget _buildNaturalBannerSlot() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surface1,
        borderRadius: 24,
      ),
      child: const BannerAdWidget(
        placeholderText: 'ads.slot',
        padding: EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }

  Widget _buildPulseFabGuide() {
    return Positioned(
      right: 12,
      bottom: 92,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, child) {
          return Opacity(
            opacity: _pulseOpacity.value,
            child: Transform.scale(scale: _pulseScale.value, child: child),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: AppTheme.cardDecoration(
                color: AppTheme.surface2.withValues(alpha: 0.96),
                borderRadius: 16,
              ),
              child: Text(
                'home.guide.startRecord'.tr(),
                style: TextStyle(color: AppTheme.textHigh, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_downward_rounded,
              color: AppTheme.primaryGreen,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  List<_TimelineItem> _buildTimelineItems({
    required List<WorkoutLogRecord> workoutLogs,
  }) {
    final manualItems = workoutLogs.map(
      (log) => _TimelineItem(
        occurredAt: log.performedAt,
        title: log.exerciseName,
        subtitle: 'home.timeline.manualLog'.tr(args: [_formatSetRep(log)]),
        icon: Icons.fitness_center,
        color: AppTheme.primaryGreen,
      ),
    );
    final timeline = manualItems.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return timeline.take(12).toList();
  }

  String _formatSetRep(WorkoutLogRecord log) {
    if (log.exerciseType == ExerciseType.cardio) {
      final durationText = log.durationMinutes == null
          ? '-'
          : 'home.timeline.unit.minute'.tr(
              namedArgs: {'value': '${log.durationMinutes}'},
            );
      final distanceText = log.distanceKm == null
          ? ''
          : ' · ${log.distanceKm!.toStringAsFixed(1)}km';
      return 'home.timeline.cardio'.tr(
        namedArgs: {'duration': durationText, 'distance': distanceText},
      );
    }

    final setText = log.sets == null
        ? '-'
        : 'home.timeline.unit.set'.tr(namedArgs: {'value': '${log.sets}'});
    final repText = log.reps == null
        ? '-'
        : 'home.timeline.unit.rep'.tr(namedArgs: {'value': '${log.reps}'});
    final weightText =
        log.weightKg == null ? '' : ' · ${log.weightKg!.toStringAsFixed(1)}kg';
    return 'home.timeline.weight'.tr(
      namedArgs: {
        'set': setText,
        'rep': repText,
        'weight': weightText,
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  String _displayMuscleName(String muscleCode) {
    return MuscleLabelLocalizer.homeHeroDisplayName(muscleCode);
  }

  Widget _buildAppBarIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: AppTheme.iconButtonDecoration(),
        child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
      ),
    );
  }
}

class _TimelineItem {
  const _TimelineItem({
    required this.occurredAt,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final DateTime occurredAt;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
