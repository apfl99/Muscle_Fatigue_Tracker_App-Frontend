import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_fonts/google_fonts.dart';
import '../model/database_helper.dart';
import '../model/measure_session.dart';
import '../model/baseline.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// 그래프 정렬 옵션
enum ChartSortOrder { recent, date }

// MeasurementSession은 이제 model/measure_session.dart에서 가져옴

/// 측정 기록 히스토리 화면 (개선 버전)
class MeasurementHistoryPage extends StatefulWidget {
  const MeasurementHistoryPage({super.key});

  @override
  State<MeasurementHistoryPage> createState() => _MeasurementHistoryPageState();
}

class _MeasurementHistoryPageState extends State<MeasurementHistoryPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<MeasureSession> _allSessions = []; // DB에서 가져온 측정 세션
  List<MeasureSession> _filteredSessions = [];
  bool _isLoading = true;

  // 캘린더 관련
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<DateTime, List<MeasureSession>> _groupedSessions = {};

  // 탭 컨트롤러
  late TabController _tabController;

  // 필터 옵션
  String? _selectedLevel;
  DateTime? _startDate;
  DateTime? _endDate;

  // 그래프 정렬 옵션
  ChartSortOrder _chartSortOrder = ChartSortOrder.recent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadResults();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 다시 활성화되면 데이터 새로고침
    if (state == AppLifecycleState.resumed) {
      _loadResults();
    }
  }

  Future<void> _loadResults() async {
    setState(() => _isLoading = true);

    try {
      final logsData = await DatabaseHelper.instance.getAllFatigueLogs();
      print('🔍 로드된 피로도 로그 개수: ${logsData.length}');

      final sessions =
          logsData.map((data) => MeasureSession.fromMap(data)).toList();

      setState(() {
        _allSessions = sessions;
        _applyFiltersAndSort();
        _groupSessionsByDate();
        _isLoading = false;
      });

      print('🔍 필터된 세션 개수: ${_filteredSessions.length}');
      print('🔍 날짜별 그룹: ${_groupedSessions.length}개');
    } catch (e) {
      print('❌ 히스토리 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  // 이제 DB에서 세션 단위로 저장되므로 그룹핑 불필요

  void _groupSessionsByDate() {
    _groupedSessions.clear();
    for (var session in _allSessions) {
      final dateKey = DateTime(
        session.timestamp.year,
        session.timestamp.month,
        session.timestamp.day,
      );
      if (_groupedSessions[dateKey] == null) {
        _groupedSessions[dateKey] = [];
      }
      _groupedSessions[dateKey]!.add(session);
    }
  }

  void _applyFiltersAndSort() {
    var sessions = List<MeasureSession>.from(_allSessions);
    print('🔍 필터 전 세션: ${sessions.length}개');

    // 피로도 레벨 필터
    if (_selectedLevel != null) {
      sessions = sessions.where((s) {
        return FatigueCalculator.getFatigueLevel(s.fatigue) == _selectedLevel;
      }).toList();
      print('🔍 레벨 필터 후: ${sessions.length}개 (선택: $_selectedLevel)');
    }

    // 날짜 범위 필터
    if (_startDate != null) {
      sessions =
          sessions.where((s) => s.timestamp.isAfter(_startDate!)).toList();
      print('🔍 시작일 필터 후: ${sessions.length}개');
    }
    if (_endDate != null) {
      final endOfDay = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        23,
        59,
        59,
      );
      sessions = sessions.where((s) => s.timestamp.isBefore(endOfDay)).toList();
      print('🔍 종료일 필터 후: ${sessions.length}개');
    }

    // 최신순 정렬
    sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _filteredSessions = sessions;
    });
    print('🔍 최종 필터된 세션: ${_filteredSessions.length}개');
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.filter_list, color: Colors.blue),
            SizedBox(width: 8),
            Text('필터'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '피로도 레벨',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('전체'),
                    selected: _selectedLevel == null,
                    onSelected: (selected) {
                      setState(() => _selectedLevel = null);
                      _applyFiltersAndSort();
                    },
                  ),
                  FilterChip(
                    label: const Text('정상'),
                    selected: _selectedLevel == '정상',
                    onSelected: (selected) {
                      setState(() => _selectedLevel = selected ? '정상' : null);
                      _applyFiltersAndSort();
                    },
                  ),
                  FilterChip(
                    label: const Text('약간 피로'),
                    selected: _selectedLevel == '약간 피로',
                    onSelected: (selected) {
                      setState(
                        () => _selectedLevel = selected ? '약간 피로' : null,
                      );
                      _applyFiltersAndSort();
                    },
                  ),
                  FilterChip(
                    label: const Text('피로 누적'),
                    selected: _selectedLevel == '피로 누적',
                    onSelected: (selected) {
                      setState(
                        () => _selectedLevel = selected ? '피로 누적' : null,
                      );
                      _applyFiltersAndSort();
                    },
                  ),
                  FilterChip(
                    label: const Text('고피로'),
                    selected: _selectedLevel == '고피로',
                    onSelected: (selected) {
                      setState(() => _selectedLevel = selected ? '고피로' : null);
                      _applyFiltersAndSort();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedLevel = null;
                _startDate = null;
                _endDate = null;
              });
              _applyFiltersAndSort();
              Navigator.pop(context);
            },
            child: const Text('초기화'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('적용'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllResults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('전체 삭제'),
          ],
        ),
        content: Text(
          '모든 분석 기록(${_allSessions.length}회)을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteAllFatigueLogs();
      // Baseline Manager 카운트 동기화
      await BaselineManager.instance.syncWithDatabase();
      _loadResults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('모든 분석 기록이 삭제되었습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        title: Text(
          '분석 기록 (${_allSessions.length}회)',
          style: const TextStyle(color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryGreen,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          tabs: const [
            Tab(icon: Icon(Icons.show_chart), text: '추이'),
            Tab(icon: Icon(Icons.calendar_today), text: '캘린더'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: '필터',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadResults,
            tooltip: '새로고침',
          ),
          if (_allSessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: _deleteAllResults,
              tooltip: '전체 삭제',
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allSessions.isEmpty
                ? _buildEmptyState()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTrendView(),
                      _buildCalendarView(),
                    ],
                  ),
      ),
    );
  }

  // 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 80,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 16),
          Text(
            '저장된 분석 기록이 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '분석을 시작하면 자동으로 기록됩니다',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // 추이 뷰 (그래프 + 통계 + 리스트)
  Widget _buildTrendView() {
    if (_filteredSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox,
              size: 80,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 16),
            Text(
              '분석 기록이 없습니다',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // 통계 요약
              _buildStatisticsSummary(),
              const SizedBox(height: 16),

              // 피로도 추이 그래프
              _buildFatigueChart(),
              const SizedBox(height: 16),
            ],
          ),
        ),
        // 측정 기록 리스트
        _buildResultsSliverList(),
      ],
    );
  }

  // 통계 요약
  Widget _buildStatisticsSummary() {
    if (_filteredSessions.isEmpty) return const SizedBox.shrink();

    try {
      final avgFatigue =
          _filteredSessions.map((s) => s.fatigue).reduce((a, b) => a + b) /
              _filteredSessions.length;
      final maxFatigue = _filteredSessions
          .map((s) => s.fatigue)
          .reduce((a, b) => a > b ? a : b);
      final minFatigue = _filteredSessions
          .map((s) => s.fatigue)
          .reduce((a, b) => a < b ? a : b);

      // 오늘 측정 수
      final today = DateTime.now();
      final todayKey = DateTime(today.year, today.month, today.day);
      final todayCount = _groupedSessions[todayKey]?.length ?? 0;

      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00BCD4).withOpacity(0.15),
              const Color(0xFF00ACC1).withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00BCD4).withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00BCD4), Color(0xFF00ACC1)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.analytics,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '통계 요약',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '총 분석',
                  '${_filteredSessions.length}회',
                  Icons.assignment,
                  Colors.blue,
                ),
                _buildStatItem(
                  '오늘',
                  '$todayCount회',
                  Icons.today,
                  Colors.green,
                ),
                _buildStatItem(
                  '평균',
                  avgFatigue.toStringAsFixed(2),
                  Icons.trending_flat,
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '최소',
                  minFatigue.toStringAsFixed(2),
                  Icons.arrow_downward,
                  Colors.green,
                ),
                _buildStatItem(
                  '최대',
                  maxFatigue.toStringAsFixed(2),
                  Icons.arrow_upward,
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ 통계 요약 오류: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // 피로도 추이 그래프
  Widget _buildFatigueChart() {
    if (_filteredSessions.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.show_chart,
              size: 48,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 12),
            Text(
              '표시할 데이터가 없습니다',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    try {
      // 측정 세션 기준으로 데이터 준비
      List<MapEntry<DateTime, double>> chartData;

      if (_chartSortOrder == ChartSortOrder.date) {
        // 날짜별로 그룹핑하여 평균 계산
        final Map<DateTime, List<double>> dailyFatigue = {};
        for (var session in _filteredSessions) {
          final dateKey = DateTime(
            session.timestamp.year,
            session.timestamp.month,
            session.timestamp.day,
          );
          if (dailyFatigue[dateKey] == null) {
            dailyFatigue[dateKey] = [];
          }
          dailyFatigue[dateKey]!.add(session.fatigue);
        }

        // 날짜별 평균 계산 및 정렬
        chartData = dailyFatigue.entries.map((e) {
          final avg = e.value.reduce((a, b) => a + b) / e.value.length;
          return MapEntry(e.key, avg);
        }).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
      } else {
        // 최근 순 (측정 세션 순서대로)
        final sortedSessions = List<MeasureSession>.from(_filteredSessions)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        chartData = sortedSessions.map((session) {
          return MapEntry(session.timestamp, session.fatigue);
        }).toList();
      }

      // 최근 30개 데이터만 표시
      final displayData = chartData.length > 30
          ? chartData.sublist(chartData.length - 30)
          : chartData;

      // Y축 범위 동적 계산
      if (displayData.isEmpty) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text('데이터가 없습니다'),
          ),
        );
      }

      final fatigueValues = displayData.map((e) => e.value).toList();
      final minFatigue = fatigueValues.reduce((a, b) => a < b ? a : b);
      final maxFatigue = fatigueValues.reduce((a, b) => a > b ? a : b);

      // Y축 범위에 여유 공간 추가 (10%)
      final range = maxFatigue - minFatigue;
      final padding = range * 0.1;
      final dynamicMinY = (minFatigue - padding).clamp(0.5, 1.0);
      final dynamicMaxY = (maxFatigue + padding).clamp(2.0, 4.0);

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.show_chart,
                    color: Color(0xFF4CAF50),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '피로도 추이',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                // 정렬 옵션 선택 버튼
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<ChartSortOrder>(
                    value: _chartSortOrder,
                    dropdownColor: const Color(0xFF2A2A2A),
                    underline: const SizedBox(),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 18,
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ChartSortOrder.recent,
                        child: Text('최근 순'),
                      ),
                      DropdownMenuItem(
                        value: ChartSortOrder.date,
                        child: Text('날짜 기준'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _chartSortOrder = value;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${displayData.length}개',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        (dynamicMaxY - dynamicMinY) / 4, // 4개 구간으로 나누기
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.white.withOpacity(0.05),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: displayData.length > 10 ? 5 : 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= displayData.length) {
                            return const SizedBox();
                          }
                          final dateTime = displayData[index].key;
                          String label;

                          if (_chartSortOrder == ChartSortOrder.date) {
                            // 날짜 기준: 월/일 표시
                            label = '${dateTime.month}/${dateTime.day}';
                          } else {
                            // 최근 순: 시간 표시 (같은 날이면 시간만, 다른 날이면 날짜)
                            if (index > 0) {
                              final prevDateTime = displayData[index - 1].key;
                              final isSameDay =
                                  dateTime.year == prevDateTime.year &&
                                      dateTime.month == prevDateTime.month &&
                                      dateTime.day == prevDateTime.day;
                              if (isSameDay) {
                                label =
                                    '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
                              } else {
                                label = '${dateTime.month}/${dateTime.day}';
                              }
                            } else {
                              label = '${dateTime.month}/${dateTime.day}';
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 9,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: dynamicMinY,
                  maxY: dynamicMaxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: displayData
                          .asMap()
                          .entries
                          .map(
                            (e) => FlSpot(
                              e.key.toDouble(),
                              e.value.value,
                            ),
                          )
                          .toList(),
                      isCurved: true,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E676), Color(0xFF4CAF50)],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          final fatigue = displayData[index].value;
                          final color =
                              FatigueCalculator.getFatigueColor(fatigue);
                          return FlDotCirclePainter(
                            radius: 5,
                            color: color,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF00E676).withOpacity(0.2),
                            const Color(0xFF4CAF50).withOpacity(0.05),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final index = spot.x.toInt();
                          if (index < 0 || index >= displayData.length) {
                            return null;
                          }
                          final entry = displayData[index];
                          final dateTime = entry.key;
                          final fatigue = entry.value;
                          final level =
                              FatigueCalculator.getFatigueLevel(fatigue);

                          String dateLabel;
                          if (_chartSortOrder == ChartSortOrder.date) {
                            dateLabel = '${dateTime.month}/${dateTime.day}';
                          } else {
                            dateLabel =
                                '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
                          }

                          return LineTooltipItem(
                            '$dateLabel\n${fatigue.toStringAsFixed(2)} ($level)',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 범례
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(const Color(0xFF4CAF50), '정상'),
                const SizedBox(width: 16),
                _buildLegendItem(const Color(0xFFFFA726), '약간 피로'),
                const SizedBox(width: 16),
                _buildLegendItem(const Color(0xFFFF7043), '피로 누적'),
                const SizedBox(width: 16),
                _buildLegendItem(const Color(0xFFE53935), '고피로'),
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ 그래프 생성 오류: $e');
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              '그래프 생성 중 오류가 발생했습니다',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // 캘린더 뷰
  Widget _buildCalendarView() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1.5,
              ),
            ),
            child: TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                  color: const Color(0xFF00BCD4).withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: Color(0xFF00E676),
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: const TextStyle(color: Colors.red),
                defaultTextStyle: const TextStyle(color: Colors.white),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: Colors.grey.shade400),
                weekendStyle: TextStyle(color: Colors.red.shade300),
              ),
              eventLoader: (day) {
                final dateKey = DateTime(day.year, day.month, day.day);
                return _groupedSessions[dateKey] ?? [];
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
            ),
          ),
        ),
        // 선택한 날짜의 기록
        if (_selectedDay != null) _buildSelectedDayResults(),
      ],
    );
  }

  // 선택한 날짜의 결과 (Sliver 버전)
  Widget _buildSelectedDayResults() {
    final dateKey = DateTime(
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
    );
    final daySessions = _groupedSessions[dateKey] ?? [];

    if (daySessions.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              '이 날짜에는 분석 기록이 없습니다',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return _buildSessionCard(daySessions[index]);
          },
          childCount: daySessions.length,
        ),
      ),
    );
  }

  // 기록 리스트 (Sliver 버전)
  Widget _buildResultsSliverList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              // 리스트 헤더
              return Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.list_alt,
                        color: Color(0xFF4CAF50),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '분석 기록',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '총 ${_filteredSessions.length}회',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }

            // 세션 카드
            final sessionIndex = index - 1;
            if (sessionIndex >= _filteredSessions.length) {
              // 하단 여백
              return const SizedBox(height: 16);
            }

            return _buildSessionCard(_filteredSessions[sessionIndex]);
          },
          childCount: _filteredSessions.length + 2, // 헤더 + 세션들 + 하단여백
        ),
      ),
    );
  }

  // 개별 측정 세션 카드
  Widget _buildSessionCard(MeasureSession session) {
    final fatigueLevel = FatigueCalculator.getFatigueLevel(session.fatigue);
    final fatigueColor = FatigueCalculator.getFatigueColor(session.fatigue);

    return Container(
      margin: EdgeInsets.only(
        bottom: Responsive.isSmallScreen(context) ? 8 : 12,
      ),
      decoration: AppTheme.cardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetailDialog(session),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: Responsive.cardPadding(context),
            child: Row(
              children: [
                // 피로도 아이콘
                Container(
                  width: Responsive.isSmallScreen(context) ? 50 : 60,
                  height: Responsive.isSmallScreen(context) ? 50 : 60,
                  decoration: BoxDecoration(
                    gradient: AppTheme.fatigueGradient(session.fatigue),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: fatigueColor.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      session.fatigue.toStringAsFixed(1),
                      style: GoogleFonts.poppins(
                        fontSize: Responsive.isSmallScreen(context) ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 정보
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fatigueLevel,
                        style: TextStyle(
                          fontSize: Responsive.isSmallScreen(context) ? 14 : 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(session.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '근육: ${session.rms.toStringAsFixed(4)} | 진동: ${session.freq.toStringAsFixed(1)}회/초',
                              style: GoogleFonts.poppins(
                                fontSize:
                                    Responsive.isSmallScreen(context) ? 10 : 11,
                                color: Colors.white.withOpacity(0.5),
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${session.windowCount}회 분석',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.primaryGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 화살표
                Icon(
                  Icons.chevron_right,
                  color: AppTheme.primaryGreen.withOpacity(0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 상세 정보 다이얼로그
  void _showDetailDialog(MeasureSession session) {
    final fatigueLevel = FatigueCalculator.getFatigueLevel(session.fatigue);
    final fatigueColor = FatigueCalculator.getFatigueColor(session.fatigue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: fatigueColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  session.fatigue.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: fatigueColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fatigueLevel,
                    style: TextStyle(
                      fontSize: 18,
                      color: fatigueColor,
                    ),
                  ),
                  Text(
                    _formatDateTime(session.timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    '${session.windowCount}회 분석',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                '피로도 점수',
                session.fatigue.toStringAsFixed(2),
              ),
              _buildDetailRow('세부 샘플 수', '${session.windowCount}개'),
              _buildDetailRow('분석 모드', _getModeDisplayName(session.mode)),
              const Divider(),
              const Text(
                '분석 데이터',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('근육 활동량', session.rms.toStringAsFixed(4)),
              _buildDetailRow(
                '진동수',
                '${session.freq.toStringAsFixed(1)}회/초',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              // 피로도 로그 삭제 (session_id 필드 사용)
              if (session.id != null) {
                await DatabaseHelper.instance.deleteFatigueLog(
                  session.id.toString(),
                );
                // Baseline Manager 카운트 동기화
                await BaselineManager.instance.syncWithDatabase();
                _loadResults();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('분석 기록이 삭제되었습니다'),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete),
            label: const Text('삭제'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _getModeDisplayName(String mode) {
    switch (mode) {
      case 'ema':
        return '기본 학습';
      case 'hybrid':
        return '향상 분석';
      case 'endToEnd':
        return '완전 AI';
      default:
        return mode;
    }
  }
}
