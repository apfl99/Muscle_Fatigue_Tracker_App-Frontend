import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../features/heatmap/model/heatmap_models.dart';
import '../model/database_helper.dart';
import '../model/measure_session.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

enum _DashboardMode {
  trend,
  calendar,
}

enum _TimelineEntryType {
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
        _errorMessage = '히스토리 로딩 중 오류가 발생했습니다: $error';
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

    setState(() {
      _filteredTimeline = filtered;
      if (resetVisible) {
        _visibleCount = filtered.length < 20 ? filtered.length : 20;
      } else {
        _visibleCount = _visibleCount.clamp(0, filtered.length).toInt();
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
    final modeLabel = _analysisModeLabel(session.mode);
    return _TimelineEntry(
      type: _TimelineEntryType.analysis,
      occurredAt: session.timestamp,
      title: '정밀 분석 리포트',
      subtitle: '$modeLabel · $level (${session.fatigue.toStringAsFixed(2)})',
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
        foregroundColor: Colors.white,
        title: const Text('히스토리'),
        actions: [
          IconButton(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: _buildTopDashboard(),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primaryGreen,
            onRefresh: _loadHistory,
            child: CustomScrollView(
              key: const Key('history_timeline_scroll'),
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                    child: Row(
                      children: [
                        const Text(
                          '통합 타임라인',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '총 ${_filteredTimeline.length}건',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _dashboardTab(
                key: const Key('history_mode_trend'),
                label: '추이 그래프 보기',
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
                label: '캘린더 보기',
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
          const SizedBox(height: 6),
          Text(
            _filterSummary(),
            key: const Key('history_filter_label'),
            style: const TextStyle(
              color: Colors.white70,
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryGreen.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppTheme.primaryGreen : Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _rangeChip('7일', 7),
            _rangeChip('30일', 30),
            _rangeChip('전체', null),
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
        color:
            _trendRangeDays == value ? AppTheme.primaryGreen : Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      side: BorderSide(
        color: _trendRangeDays == value
            ? AppTheme.primaryGreen.withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.14),
      ),
      onSelected: (_) {
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
      return const Center(
        child: Text(
          '정밀 분석 리포트 데이터가 없습니다.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
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
            color: Colors.white.withValues(alpha: 0.08),
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
                style: const TextStyle(color: Colors.white54, fontSize: 10),
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
                    const TextStyle(
                      color: Colors.white,
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
            gradient: const LinearGradient(
              colors: [Color(0xFF42A5F5), Color(0xFFAB47BC)],
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3.5,
                color: Colors.white,
                strokeWidth: 1.4,
                strokeColor: const Color(0xFF42A5F5),
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
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white70),
            rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white70),
          ),
          daysOfWeekStyle: const DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: Colors.white54),
            weekendStyle: TextStyle(color: Colors.white54),
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
            defaultTextStyle: const TextStyle(color: Colors.white),
            outsideTextStyle: const TextStyle(color: Colors.white38),
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
            child: const Text(
              '오늘 날짜 필터',
              style: TextStyle(color: AppTheme.primaryGreen),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard(_TimelineEntry entry) {
    return Container(
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
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          entry.subtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              entry.type == _TimelineEntryType.manual ? '운동 일지' : '정밀 분석',
              style: TextStyle(
                color: entry.color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _formatDateTime(entry.occurredAt),
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTimeline() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 54,
              color: Colors.white38,
            ),
            SizedBox(height: 10),
            Text(
              '선택된 조건에 맞는 기록이 없습니다.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '상단 필터를 바꿔 다른 기간의 운동 일지와 정밀 분석 리포트를 확인해보세요.',
              style: TextStyle(
                color: Colors.white54,
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
          log.durationMinutes == null ? '-' : '${log.durationMinutes}분';
      final distance = log.distanceKm == null
          ? ''
          : ' · ${log.distanceKm!.toStringAsFixed(1)}km';
      return '컨디션 로그 · 유산소 · $duration$distance';
    }

    final sets = log.sets == null ? '-' : '${log.sets}세트';
    final reps = log.reps == null ? '-' : '${log.reps}회';
    final weight =
        log.weightKg == null ? '' : ' · ${log.weightKg!.toStringAsFixed(1)}kg';
    return '컨디션 로그 · $sets / $reps$weight';
  }

  String _analysisModeLabel(String mode) {
    switch (mode) {
      case 'hybrid':
        return 'Hybrid';
      case 'endToEnd':
        return 'E2E';
      default:
        return 'EMA';
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
    if (_dashboardMode == _DashboardMode.trend) {
      if (_trendRangeDays == null) {
        return '필터: 전체 기간 추이';
      }
      return '필터: 최근 $_trendRangeDays일 추이';
    }

    if (_selectedDay != null) {
      return '필터: ${_dateLabel(_selectedDay!)} 선택';
    }
    return '필터: ${_focusedDay.year}년 ${_focusedDay.month}월';
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
