import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../model/database_helper.dart';
import '../model/measure_session.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad_widget.dart';

enum _DashboardMode {
  trend,
  calendar,
}

enum _TimelineEntryType {
  manual,
  analysis,
}

enum _TimelineFilter {
  manual,
  analysis,
}

class MeasurementHistoryPage extends StatefulWidget {
  const MeasurementHistoryPage({super.key});

  @override
  State<MeasurementHistoryPage> createState() => _MeasurementHistoryPageState();
}

class _MeasurementHistoryPageState extends State<MeasurementHistoryPage>
    with WidgetsBindingObserver {
  final SupabaseService _supabaseService = SupabaseService();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  List<WorkoutLogRecord> _manualLogs = const [];
  List<MeasureSession> _analysisReports = const [];
  List<_TimelineEntry> _filteredTimeline = const [];
  int _visibleCount = 20;

  _DashboardMode _dashboardMode = _DashboardMode.trend;
  _TimelineFilter _timelineFilter = _TimelineFilter.manual;
  int? _trendRangeDays = 7;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _supabaseService.fetchWorkoutLogs(limit: 200),
        DatabaseHelper.instance.getAllFatigueLogs(),
      ]);

      final manualLogs = (results[0] as List<WorkoutLogRecord>)
        ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
      final analysisRows = results[1] as List<dynamic>;
      final analysisReports = analysisRows
          .whereType<Map>()
          .map((row) => MeasureSession.fromMap(Map<String, dynamic>.from(row)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (!mounted) {
        return;
      }

      setState(() {
        _manualLogs = manualLogs;
        _analysisReports = analysisReports;
        _isLoading = false;
      });
      _recomputeTimeline(resetVisible: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'history.errors.loadFailed'.tr(args: ['$error']);
      });
    }
  }

  void _onScroll() {
    if (_isLoadingMore) {
      return;
    }
    if (_visibleCount >= _filteredTimeline.length) {
      return;
    }
    if (_scrollController.position.extentAfter > 240) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _visibleCount =
            (_visibleCount + 20).clamp(0, _filteredTimeline.length).toInt();
        _isLoadingMore = false;
      });
    });
  }

  void _recomputeTimeline({required bool resetVisible}) {
    final merged = <_TimelineEntry>[
      ..._manualLogs.map(_toManualEntry),
      ..._analysisReports.map(_toAnalysisEntry),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final filtered = merged.where((entry) {
      if (_dashboardMode == _DashboardMode.trend) {
        if (_trendRangeDays == null) {
          return true;
        }
        final cutoff =
            DateTime.now().subtract(Duration(days: _trendRangeDays!));
        return entry.occurredAt.isAfter(cutoff);
      }

      if (_selectedDay != null) {
        return _isSameDate(entry.occurredAt, _selectedDay!);
      }
      return entry.occurredAt.year == _focusedDay.year &&
          entry.occurredAt.month == _focusedDay.month;
    }).toList();

    final separated = filtered.where((entry) {
      if (_timelineFilter == _TimelineFilter.manual) {
        return entry.type == _TimelineEntryType.manual;
      }
      return entry.type == _TimelineEntryType.analysis;
    }).toList();

    setState(() {
      _filteredTimeline = separated;
      if (resetVisible) {
        _visibleCount = separated.length < 20 ? separated.length : 20;
      } else {
        _visibleCount = _visibleCount.clamp(0, separated.length).toInt();
      }
    });
  }

  _TimelineEntry _toManualEntry(WorkoutLogRecord log) {
    return _TimelineEntry(
      type: _TimelineEntryType.manual,
      occurredAt: log.performedAt,
      title: log.exerciseName,
      subtitle: _manualSubtitle(log),
      icon: Icons.fitness_center,
      color: AppTheme.primaryGreen,
    );
  }

  _TimelineEntry _toAnalysisEntry(MeasureSession session) {
    final level = FatigueCalculator.getFatigueLevel(session.fatigue);
    final localizedLevel = _localizedFatigueLevel(level);
    final modeLabel = _analysisModeLabel(session.mode);
    return _TimelineEntry(
      type: _TimelineEntryType.analysis,
      occurredAt: session.timestamp,
      title: 'history.analysis.reportTitle'.tr(),
      subtitle:
          '$modeLabel · $localizedLevel (${session.fatigue.toStringAsFixed(2)})',
      icon: Icons.graphic_eq_rounded,
      color: _analysisModeColor(session.mode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        foregroundColor: AppTheme.textHigh,
        title: Text('history.title'.tr()),
        actions: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadHistory();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'common.refresh'.tr(),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final pagePadding = AppTheme.resolvedPagePadding(context);
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      );
    }

    if (_errorMessage != null &&
        _manualLogs.isEmpty &&
        _analysisReports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadHistory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: AppTheme.ctaOnBrand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            pagePadding.left,
            12,
            pagePadding.right,
            10,
          ),
          child: _buildTopDashboard(),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primaryGreen,
            onRefresh: _loadHistory,
            child: CustomScrollView(
              key: const Key('history_timeline_scroll'),
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding.left,
                      2,
                      pagePadding.right,
                      10,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _timelineTitle(),
                          style: TextStyle(
                            color: AppTheme.textHigh,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'history.totalCount'.tr(
                            namedArgs: {
                              'count': _filteredTimeline.length.toString(),
                            },
                          ),
                          style: TextStyle(
                            color: AppTheme.textLow,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding.left,
                      0,
                      pagePadding.right,
                      10,
                    ),
                    child: Container(
                      decoration: AppTheme.cardDecoration(
                        color: AppTheme.surface1,
                        borderRadius: 20,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: const BannerAdWidget(
                        key: ValueKey('history_page_banner'),
                        placeholderText: 'ads.slot',
                        padding: EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                ),
                if (_filteredTimeline.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyTimeline(),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding.left,
                      0,
                      pagePadding.right,
                      24,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = _filteredTimeline[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildTimelineCard(entry),
                          );
                        },
                        childCount: _visibleCount,
                      ),
                    ),
                  ),
                if (_isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopDashboard() {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _dashboardTab(
                key: const Key('history_mode_trend'),
                label: 'history.dashboard.trend'.tr(),
                selected: _dashboardMode == _DashboardMode.trend,
                onTap: () {
                  setState(() {
                    _dashboardMode = _DashboardMode.trend;
                  });
                  _recomputeTimeline(resetVisible: true);
                },
              ),
              const SizedBox(width: 8),
              _dashboardTab(
                key: const Key('history_mode_calendar'),
                label: 'history.dashboard.calendar'.tr(),
                selected: _dashboardMode == _DashboardMode.calendar,
                onTap: () {
                  setState(() {
                    _dashboardMode = _DashboardMode.calendar;
                    _selectedDay ??= DateTime.now();
                  });
                  _recomputeTimeline(resetVisible: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_dashboardMode == _DashboardMode.trend)
            _buildTrendPanel()
          else
            _buildCalendarPanel(),
          const SizedBox(height: 12),
          _buildTimelineTypeToggle(),
          const SizedBox(height: 6),
          Text(
            _filterSummary(),
            key: const Key('history_filter_label'),
            style: TextStyle(
              color: AppTheme.textMedium,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardTab({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        key: key,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: AppTheme.buttonRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                : AppTheme.surface2.withValues(alpha: 0.5),
            borderRadius: AppTheme.buttonRadius,
            border: Border.all(
              color: selected
                  ? AppTheme.primaryGreen.withValues(alpha: 0.7)
                  : AppTheme.borderSubtle,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppTheme.primaryGreen : AppTheme.textMedium,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineTypeToggle() {
    return CupertinoSlidingSegmentedControl<_TimelineFilter>(
      key: const Key('history_timeline_toggle'),
      backgroundColor: AppTheme.surface2,
      thumbColor: AppTheme.primaryGreen.withValues(alpha: 0.24),
      groupValue: _timelineFilter,
      children: <_TimelineFilter, Widget>{
        _TimelineFilter.manual: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            'history.timelineType.manual'.tr(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        _TimelineFilter.analysis: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            'history.timelineType.analysis'.tr(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      },
      onValueChanged: (value) {
        if (value == null) {
          return;
        }
        HapticFeedback.lightImpact();
        setState(() {
          _timelineFilter = value;
        });
        _recomputeTimeline(resetVisible: true);
      },
    );
  }

  Widget _buildTrendPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _rangeChip('history.range.7d'.tr(), 7),
            _rangeChip('history.range.30d'.tr(), 30),
            _rangeChip('history.range.all'.tr(), null),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: _buildTrendChart(),
        ),
      ],
    );
  }

  Widget _rangeChip(String label, int? value) {
    return ChoiceChip(
      label: Text(label),
      selected: _trendRangeDays == value,
      selectedColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: _trendRangeDays == value
            ? AppTheme.primaryGreen
            : AppTheme.textMedium,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: AppTheme.surface2,
      side: BorderSide(
        color: _trendRangeDays == value
            ? AppTheme.primaryGreen.withValues(alpha: 0.65)
            : AppTheme.borderSubtle,
      ),
      onSelected: (_) {
        HapticFeedback.lightImpact();
        setState(() {
          _trendRangeDays = value;
        });
        _recomputeTimeline(resetVisible: true);
      },
    );
  }

  Widget _buildTrendChart() {
    final spots = _analysisSpots();
    if (spots.isEmpty) {
      return Center(
        child: Text(
          'history.analysis.empty'.tr(),
          style: TextStyle(color: AppTheme.textLow, fontSize: 12),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: 0.8,
        maxY: 3.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppTheme.textHigh.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(1),
                style: TextStyle(color: AppTheme.textLow, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (items) => items
                .map(
                  (item) => LineTooltipItem(
                    item.y.toStringAsFixed(2),
                    TextStyle(
                      color: AppTheme.textHigh,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            gradient: LinearGradient(
              colors: [
                AppTheme.accentBrand,
                AppTheme.accentBrand.withValues(alpha: 0.65),
              ],
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: AppTheme.chartGlowGradient(AppTheme.accentBrand),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3.5,
                color: AppTheme.surface1,
                strokeWidth: 1.4,
                strokeColor: AppTheme.accentBrand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _analysisSpots() {
    final sessions = List<MeasureSession>.from(_analysisReports)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final filtered = sessions.where((session) {
      if (_trendRangeDays == null) {
        return true;
      }
      final cutoff = DateTime.now().subtract(Duration(days: _trendRangeDays!));
      return session.timestamp.isAfter(cutoff);
    }).toList();

    final display = filtered.length > 30
        ? filtered.sublist(filtered.length - 30)
        : filtered;

    return display
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.fatigue))
        .toList();
  }

  Widget _buildCalendarPanel() {
    return Column(
      children: [
        TableCalendar<_TimelineEntry>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2035, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) =>
              _selectedDay != null && _isSameDate(day, _selectedDay!),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              color: AppTheme.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            leftChevronIcon:
                Icon(Icons.chevron_left, color: AppTheme.textMedium),
            rightChevronIcon:
                Icon(Icons.chevron_right, color: AppTheme.textMedium),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: AppTheme.textMedium),
            weekendStyle: TextStyle(color: AppTheme.textMedium),
          ),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: AppTheme.primaryGreen,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: Color(0xFF42A5F5),
              shape: BoxShape.circle,
            ),
            defaultTextStyle: TextStyle(color: AppTheme.textHigh),
            outsideTextStyle: TextStyle(color: AppTheme.textLow),
          ),
          eventLoader: (day) {
            return _filteredTimeline
                .where((entry) => _isSameDate(entry.occurredAt, day))
                .toList();
          },
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
            _recomputeTimeline(resetVisible: true);
          },
          onPageChanged: (focusedDay) {
            setState(() {
              _focusedDay = focusedDay;
            });
            if (_selectedDay == null) {
              _recomputeTimeline(resetVisible: true);
            }
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('history_select_today'),
            onPressed: () {
              setState(() {
                _selectedDay = DateTime.now();
                _focusedDay = DateTime.now();
              });
              _recomputeTimeline(resetVisible: true);
            },
            child: Text(
              'history.calendar.filterToday'.tr(),
              style: const TextStyle(color: AppTheme.primaryGreen),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard(_TimelineEntry entry) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: entry.color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(entry.icon, color: entry.color),
        ),
        title: Text(
          entry.title,
          style: TextStyle(
            color: AppTheme.textHigh,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          entry.subtitle,
          style: TextStyle(
            color: AppTheme.textMedium,
            fontSize: 12,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              entry.type == _TimelineEntryType.manual
                  ? 'history.timelineType.manual'.tr()
                  : 'history.timelineType.analysis'.tr(),
              style: TextStyle(
                color: entry.color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _formatDateTime(entry.occurredAt),
              style: TextStyle(color: AppTheme.textLow, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTimeline() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 54,
              color: AppTheme.textLow,
            ),
            const SizedBox(height: 10),
            Text(
              'history.empty.title'.tr(),
              style: TextStyle(
                color: AppTheme.textMedium,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'history.empty.description'.tr(),
              style: TextStyle(
                color: AppTheme.textLow,
                fontSize: 12,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _manualSubtitle(WorkoutLogRecord log) {
    if (log.exerciseType == ExerciseType.cardio) {
      final duration =
          log.durationMinutes == null
              ? '-'
              : 'history.unit.minute'.tr(
                  namedArgs: {'value': '${log.durationMinutes}'},
                );
      final distance = log.distanceKm == null
          ? ''
          : ' · ${log.distanceKm!.toStringAsFixed(1)}km';
      return 'history.subtitle.cardio'.tr(
        namedArgs: {'duration': duration, 'distance': distance},
      );
    }

    final sets = log.sets == null
        ? '-'
        : 'history.unit.set'.tr(namedArgs: {'value': '${log.sets}'});
    final reps = log.reps == null
        ? '-'
        : 'history.unit.rep'.tr(namedArgs: {'value': '${log.reps}'});
    final weight =
        log.weightKg == null ? '' : ' · ${log.weightKg!.toStringAsFixed(1)}kg';
    return 'history.subtitle.weight'.tr(
      namedArgs: {
        'set': sets,
        'rep': reps,
        'weight': weight,
      },
    );
  }

  String _analysisModeLabel(String mode) {
    switch (mode) {
      case 'hybrid':
        return 'history.analysis.mode.hybrid'.tr();
      case 'endToEnd':
        return 'history.analysis.mode.endToEnd'.tr();
      default:
        return 'history.analysis.mode.ema'.tr();
    }
  }

  Color _analysisModeColor(String mode) {
    switch (mode) {
      case 'hybrid':
        return const Color(0xFFAB47BC);
      case 'endToEnd':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF42A5F5);
    }
  }

  String _filterSummary() {
    final typeLabel =
        _timelineFilter == _TimelineFilter.manual
            ? 'history.timelineType.manual'.tr()
            : 'history.timelineType.analysis'.tr();
    if (_dashboardMode == _DashboardMode.trend) {
      if (_trendRangeDays == null) {
        return 'history.filter.trendAll'.tr(args: [typeLabel]);
      }
      return 'history.filter.trendRecent'.tr(
        namedArgs: {
          'type': typeLabel,
          'days': '$_trendRangeDays',
        },
      );
    }

    if (_selectedDay != null) {
      return 'history.filter.selectedDate'.tr(
        namedArgs: {
          'type': typeLabel,
          'date': _dateLabel(_selectedDay!),
        },
      );
    }
    return 'history.filter.month'.tr(
      namedArgs: {
        'type': typeLabel,
        'year': '${_focusedDay.year}',
        'month': '${_focusedDay.month}',
      },
    );
  }

  String _timelineTitle() {
    return _timelineFilter == _TimelineFilter.manual
        ? 'history.timelineTitle.manual'.tr()
        : 'history.timelineTitle.analysis'.tr();
  }

  String _localizedFatigueLevel(String level) {
    switch (_fatigueLevelCode(level)) {
      case 'recovered':
        return 'heatmap.status.recovered'.tr();
      case 'recovering':
        return 'heatmap.status.recovering'.tr();
      case 'delayed':
        return 'sensor.fatigue.delayed'.tr();
      case 'need_recovery':
        return 'heatmap.status.needRecovery'.tr();
      default:
        return 'sensor.fatigue.unknown'.tr();
    }
  }

  String _fatigueLevelCode(String level) {
    final raw = level.trim().toLowerCase();
    if (raw == '회복 완료' ||
        raw == 'recovered' ||
        raw == '부하 안정' ||
        raw == 'load stable') {
      return 'recovered';
    }
    if (raw == '회복 중' ||
        raw == 'recovering' ||
        raw == '휴식 권장' ||
        raw == 'rest recommended') {
      return 'recovering';
    }
    if (raw == '회복 지연' ||
        raw == 'delayed recovery' ||
        raw == '강도 조절 필요' ||
        raw == 'adjust intensity needed' ||
        raw == 'adjust intensity') {
      return 'delayed';
    }
    if (raw == 'needs recovery' || raw == 'recovery needed') {
      return 'need_recovery';
    }
    return 'unknown';
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.type,
    required this.occurredAt,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final _TimelineEntryType type;
  final DateTime occurredAt;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
