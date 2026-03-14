import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../providers/heatmap_provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
    _pulseController.dispose();
    super.dispose();
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
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: AppTheme.primaryGreen.withValues(alpha: 0.25),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MuscleCare v2.0',
                style: TextStyle(
                  color: AppTheme.primaryGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '매일 운동을 기록하고 오늘의 신체 컨디션을 확인하세요.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '홈의 + 버튼으로 컨디션 로그를 남기면 히트맵이 즉시 갱신됩니다.',
                style: TextStyle(
                  color: Colors.white70,
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
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    '시작하기',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
    debugPrint('[funnel] on_fab_clicked {"source":"main_home_fab"}');
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkoutLogBottomSheet(bridgePayload: bridgePayload),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('컨디션 로그 저장이 완료되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HeatmapProvider>(
      builder: (context, provider, _) {
        final timelineItems = _buildTimelineItems(
          workoutLogs: provider.workoutLogs,
        );

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            backgroundColor: AppTheme.darkBackground,
            foregroundColor: Colors.white,
            title: const Text('오늘의 컨디션'),
            actions: [
              IconButton(
                tooltip: '상세 분석 보기',
                icon: const Icon(Icons.analytics_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SensorAnalysisPage(),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: '히스토리',
                icon: const Icon(Icons.history),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MeasurementHistoryPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('main_home_fab'),
            onPressed: () => _openWorkoutLogSheet(),
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add),
            label: const Text(
              '기록',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                color: AppTheme.primaryGreen,
                onRefresh: () async {
                  await provider.refreshAll();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    _buildStreakCard(provider.streakDays),
                    const SizedBox(height: 14),
                    _buildHeroCard(
                      provider: provider,
                    ),
                    const SizedBox(height: 16),
                    _buildTimelineCard(
                      timelineItems: timelineItems,
                      isLoading: provider.isLoading,
                    ),
                    if (provider.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      _buildFallbackCard(provider.errorMessage!),
                    ],
                    const SizedBox(height: 12),
                    _buildNaturalBannerSlot(),
                  ],
                ),
              ),
              if (timelineItems.isEmpty) _buildPulseFabGuide(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStreakCard(int streakDays) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
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
                  '🔥 ${streakDays.toString().padLeft(2, '0')}일차',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '연속 운동 기록을 이어가고 있어요',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required HeatmapProvider provider,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: InkWell(
        key: const Key('hero_preview_card'),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
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
              const Text(
                '나의 3D 바디 맵',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '오늘의 신체 컨디션을 확인하세요.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
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
                            entries: provider.heatmapEntries,
                            borderRadius: 16,
                            interactive: false,
                            autoRotate: true,
                            showHotspots: false,
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
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            '탭해서 상세 보기',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
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
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '운동 기록 타임라인',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '아직 기록이 없습니다. 오른쪽 아래 버튼으로 첫 컨디션 로그를 남겨보세요.',
                style: TextStyle(color: Colors.white70, height: 1.4),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(item.occurredAt),
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                );
              },
              separatorBuilder: (_, __) => Divider(
                color: Colors.white.withValues(alpha: 0.08),
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
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.redAccent),
      ),
    );
  }

  Widget _buildNaturalBannerSlot() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const BannerAdWidget(
        placeholderText: '광고 영역',
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
              decoration: BoxDecoration(
                color: AppTheme.cardDark.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '여기서 기록 시작',
                style: TextStyle(color: Colors.white, fontSize: 12),
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
        subtitle: '수기 컨디션 로그 · ${_formatSetRep(log)}',
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
      final durationText =
          log.durationMinutes == null ? '-' : '${log.durationMinutes}분';
      final distanceText = log.distanceKm == null
          ? ''
          : ' · ${log.distanceKm!.toStringAsFixed(1)}km';
      return '유산소 $durationText$distanceText';
    }

    final setText = log.sets == null ? '-' : '${log.sets}세트';
    final repText = log.reps == null ? '-' : '${log.reps}회';
    final weightText =
        log.weightKg == null ? '' : ' · ${log.weightKg!.toStringAsFixed(1)}kg';
    return '$setText / $repText$weightText';
  }

  String _formatDateTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
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
