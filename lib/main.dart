import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'sensor/streaming.dart';
import 'sensor/config.dart';
import 'model/database_helper.dart';
import 'model/baseline.dart';
import 'model/user_state_store.dart';
import 'model/measure_session.dart';
import 'model/config.dart';
import 'model/ml.dart';
import 'widgets/fatigue_gauge.dart';
import 'screens/measurement_history_page.dart';
import 'screens/profile_page.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'utils/responsive.dart';
import 'worker/worker_manager.dart'; // 워커 매니저를 위해 필요
import 'worker/model_update_scheduler.dart';
import 'model/personalization_manager.dart';
import 'utils/user_identity.dart';
import 'utils/ad_manager.dart';

void main() async {
  print('\n🚀 앱 시작...');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  WidgetsFlutterBinding.ensureInitialized();

  await UserIdentity.instance.ensureInitialized();
  final migratedFrom = UserIdentity.instance.lastMigratedFrom;
  if (migratedFrom != null) {
    final newId = await UserIdentity.instance.userId;
    await DatabaseHelper.instance.migrateUserId(
      oldUserId: migratedFrom,
      newUserId: newId,
    );
  }

  // 데이터베이스 초기화
  print('🗄️ 데이터베이스 초기화 중...');
  try {
    final db = await DatabaseHelper.instance.database;
    print('✅ 통합 DB 초기화 완료');
    print('   - DB 경로: ${db.path}');

    // Baseline Manager 초기화
    await BaselineManager.instance.initialize();
    print('✅ Baseline Manager 초기화 완료');

    // AdManager 초기화 및 배너 광고 로드
    await AdManager.instance.initialize();
    AdManager.instance.loadBannerAd();
    print('✅ AdManager 초기화 및 배너 광고 로드 완료');

    // ML Manager 초기화
    await MLManager.instance.initialize();
    print('✅ ML Manager 초기화 완료');

    // Worker Manager 초기화
    await initializeWorkerManager();
    print('✅ Worker Manager 초기화 완료');

    // User Embedding은 측정 시에만 계산됨
    print('✅ User Embedding은 측정 시에 자동 계산됩니다');

    await ModelUpdateScheduler.instance.start();
    print('✅ 모델 자동 다운로드 스케줄러 시작');

    await PersonalizationManager.instance.initialize();
    await PersonalizationManager.instance.ensurePersonalization();
    print('✅ 개인화 매니저 초기화 및 점검 완료');
  } catch (e, stackTrace) {
    print('❌ 초기화 실패: $e');
    print('스택 트레이스: $stackTrace');
  }

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muscle Care',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      // 오류 발생 시 빨간 화면 대신 에러 위젯 표시
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        );
      },
    );
  }
}

class SensorDataPage extends StatefulWidget {
  const SensorDataPage({super.key});

  @override
  State<SensorDataPage> createState() => _SensorDataPageState();
}

class _SensorDataPageState extends State<SensorDataPage>
    with WidgetsBindingObserver {
  final SensorStreaming _sensorStreaming = SensorStreaming();
  bool _isCollecting = false;

  // 윈도우 분석 결과
  Map<String, dynamic>? _analysisResult;
  bool _isAiProcessing = false;

  // 자동 종료 타이머
  Timer? _autoStopTimer;
  double _remainingSeconds = 0.0;

  // 동적 측정시간 설정
  double _customMeasurementSeconds = SensorConfig.totalSeconds;

  // Baseline 설정 상태
  bool _hasBaseline = false;
  bool _isCheckingBaseline = true;

  // 인라인 기준값 설정 상태
  bool _isBaselineSetting = false;
  double _baselineProgress = 0.0;
  // ignore: unused_field
  String _baselineStatus = '';
  Timer? _baselineTimer;
  bool _justCompletedBaseline = false;
  Map<String, dynamic>? _completedBaseline;
  String? _qualityWarningMessage;
  Timer? _qualityWarningTimer;

  // (실제 측정 상태를 고정 메시지로 표시)

  // Baseline 상태 확인
  Future<void> _checkBaselineStatus() async {
    try {
      // DB 상태 동기화: 첫 측정 여부 + 기준값 존재 여부 모두 확인
      final isFirstMeasurement =
          await DatabaseHelper.instance.isFirstMeasurement();
      final hasBaselineInDb = await DatabaseHelper.instance.hasBaseline();

      final needBaseline = isFirstMeasurement || !hasBaselineInDb;

      setState(() {
        _hasBaseline = !needBaseline; // 필요하면 false, 아니면 true
        _isCheckingBaseline = false;
      });

      if (needBaseline) {
        print(
          '⚠️ 기준값 설정 필요: (isFirst=$isFirstMeasurement, hasBaseline=$hasBaselineInDb)',
        );
      } else {
        print('✅ 기준값 사용 가능');
      }
    } catch (e) {
      print('❌ 기준값 상태 확인 실패: $e');
      setState(() {
        _isCheckingBaseline = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 첫 진입 시 이전 세션의 잔여 결과 표시 방지
    _analysisResult = null;
    UserStateStore.instance.state.addListener(_onUserStateChanged);
    UserStateStore.instance.refreshFromDb();
    _checkBaselineStatus();

    try {
      _loadBaseline();

      // 분석 결과 콜백 등록
      _sensorStreaming.onAnalysisResult = (result) async {
        final hasQualityWarning = result['qualityWarning'] == true;
        if (hasQualityWarning) {
          _showQualityWarning(result);
          if (result['fatigueScore'] == null) {
            if (mounted) {
              setState(() {
                _analysisResult = null;
                _qualityWarningMessage = null;
              });
            }
            return;
          }
        }
        if (mounted) {
          setState(() {
            _analysisResult = result;
          });
          await _loadBaseline();
        }
      };
      _sensorStreaming.onAiProcessingStart = () {
        if (!mounted) return;
        setState(() {
          _isAiProcessing = true;
        });
      };
      _sensorStreaming.onAiProcessingEnd = () {
        if (!mounted) return;
        setState(() {
          _isAiProcessing = false;
        });
      };
    } catch (e, stackTrace) {
      print('❌ initState 오류: $e');
      print('스택 트레이스: $stackTrace');
    }
  }

  void _showQualityWarning(Map<String, dynamic> data) {
    if (!mounted) return;
    final coverage = (data['coverage'] as double?) ?? 0.0;
    final accel = data['accel'] ?? 0;
    final gyro = data['gyro'] ?? 0;
    final message =
        '센서를 더 안정적으로 유지해주세요 • coverage ${coverage.toStringAsFixed(2)} • accel $accel / gyro $gyro';
    _qualityWarningTimer?.cancel();
    setState(() {
      _qualityWarningMessage = message;
    });
    _qualityWarningTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _qualityWarningMessage = null;
      });
    });
  }

  Widget _buildQualityWarningBanner() {
    final isSmall = Responsive.isSmallScreen(context);
    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B0F0F), Color(0xFF1B0707)],
        ),
      ),
      padding: Responsive.cardPadding(context),
      child: Row(
        children: [
          Container(
            width: isSmall ? 32 : 36,
            height: isSmall ? 32 : 36,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _qualityWarningMessage ?? '',
              style: TextStyle(
                fontSize: isSmall ? 12 : 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Baseline 불러오기 (내 정보 페이지용 - 메인에서는 사용 안 함)
  Future<void> _loadBaseline() async {
    try {
      // DB와 Baseline 카운트 동기화
      await BaselineManager.instance.syncWithDatabase();
    } catch (e, stackTrace) {
      print('❌ Baseline 로드 실패: $e');
      print('스택 트레이스: $stackTrace');
    }
  }

  @override
  void dispose() {
    UserStateStore.instance.state.removeListener(_onUserStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _autoStopTimer?.cancel();
    _baselineTimer?.cancel();
    _qualityWarningTimer?.cancel();
    // 비동기 작업이 완료되기를 기다리지 않고 즉시 정리
    _sensorStreaming.dispose();
    AdManager.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      // 앱 복귀 시 DB와 동기화하여 기준값 상태 재평가
      UserStateStore.instance.refreshFromDb();
      _checkBaselineStatus();
      _loadBaseline();
      setState(() {});
    }
  }

  void _onUserStateChanged() {
    final has = UserStateStore.instance.hasBaseline;
    if (mounted) {
      setState(() {
        _hasBaseline = has;
        _isCheckingBaseline = false;
      });
    }
  }

  // 데이터 수집 시작
  Future<void> _startCollection() async {
    // Baseline이 설정되지 않은 경우 먼저 설정하도록 안내
    if (!_hasBaseline) {
      _showBaselineSetupDialog();
      return;
    }

    // 새로운 측정 시작 시 이전 데이터 초기화
    setState(() {
      _analysisResult = null;
      _isAiProcessing = false;
    });

    final success = await _sensorStreaming.startSensor();

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('센서를 시작할 수 없습니다. 기기가 센서를 지원하는지 확인해주세요.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isCollecting = true;
      _remainingSeconds = _customMeasurementSeconds;
    });

    // 남은 시간 카운트다운
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isCollecting || _remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {
          _remainingSeconds -= 0.1;
          if (_remainingSeconds < 0) _remainingSeconds = 0.0;
        });
      }
    });

    // 설정된 시간 후 자동 종료
    _autoStopTimer = Timer(
      Duration(milliseconds: (_customMeasurementSeconds * 1000).round()),
      () async {
        if (_isCollecting) {
          await _stopCollection();
          // 측정 완료 SnackBar 제거 (피로도 결과 카드만 표시)
        }
      },
    );
  }

  // 데이터 수집 중지
  Future<void> _stopCollection() async {
    await _sensorStreaming.stopSensor();
    _autoStopTimer?.cancel();

    setState(() {
      _isCollecting = false;
      _remainingSeconds = 0.0;
      // _analysisResult는 유지 (측정 결과 표시를 위해)
    });

    // 배너 광고 해제 및 새로 로드
    AdManager.instance.disposeBannerAd();
    AdManager.instance.loadBannerAd();
  }

  // 완료 배너 값 표시용 (간단한 3줄 형태)
  Widget _buildBaselineSummaryValue(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white60,
          ),
        ),
      ],
    );
  }

  // 팝업 없이 메인에서 인라인 기준값 설정 진행
  Future<void> _startBaselineInline() async {
    if (_isBaselineSetting || _isCollecting) return;

    setState(() {
      _isBaselineSetting = true;
      _baselineProgress = 0.0;
      _baselineStatus = '기기를 움직이지 말고 10초간 그대로 유지하세요...';
      _justCompletedBaseline = false;
      _analysisResult = null; // 결과 카드 숨김 보장
    });

    // 기준값 측정은 로그/업로드에서 제외되도록 플래그 설정
    _sensorStreaming.setExcludeFromLogging(true);

    final success = await _sensorStreaming.startSensor();
    if (!success) {
      setState(() {
        _isBaselineSetting = false;
        _baselineStatus = '센서를 시작할 수 없습니다. 기기 지원을 확인해주세요.';
      });
      return;
    }

    int tick = 0; // 100ms 단위
    _baselineTimer?.cancel();
    _baselineTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      tick++;
      final progress = tick / 100.0; // 10초

      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _baselineProgress = progress.clamp(0.0, 1.0);
        final remain = (10 - tick * 0.1);
        _baselineStatus = '기기를 움직이지 마세요 • 남은 시간 ${remain.toStringAsFixed(1)}초';
      });

      if (tick >= 100) {
        timer.cancel();

        await _sensorStreaming.stopSensor();
        final result = _sensorStreaming.getLastWindowResult();

        if (result != null) {
          await UserStateStore.instance.saveBaseline(result);
          await _checkBaselineStatus();
          if (!mounted) return;
          setState(() {
            _hasBaseline = true;
            _isCheckingBaseline = false;
            _isBaselineSetting = false;
            _baselineStatus = '기준값 설정이 완료되었습니다!';
            _justCompletedBaseline = true;
            _analysisResult = null; // 이번 세션은 피로도 카드 미노출
          });
          // 자동 이동 대신 완료 배너로 선택 유도
          _completedBaseline = result;
        } else {
          if (!mounted) return;
          setState(() {
            _isBaselineSetting = false;
            _baselineStatus = '데이터 수집에 실패했습니다. 주변 진동을 줄이고 다시 시도해주세요.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('기준값 설정 실패. 다시 시도해주세요.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        titleSpacing: 8,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = Responsive.isSmallScreen(context);

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
                        color: Colors.white,
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
            icon: Icons.history_outlined,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MeasurementHistoryPage(),
                ),
              );
            },
            tooltip: '측정 기록',
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 2 : 6),
          _buildAppBarIcon(
            icon: Icons.person_outline,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfilePage(),
                ),
              );
              if (!mounted) return;
              await _checkBaselineStatus();
              await _loadBaseline();
              setState(() {});
            },
            tooltip: '내 정보',
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 2 : 6),
          _buildAppBarIcon(
            icon: Icons.settings_outlined,
            onPressed: _showSettingsDialog,
            tooltip: '설정',
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 4 : 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Responsive.responsivePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 측정 안내 카드
              _buildInstructionCard(),
              const SizedBox(height: 16),

              if (_isBaselineSetting) ...[
                Container(
                  width: double.infinity,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: LinearProgressIndicator(
                    value: _baselineProgress,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGreen,
                    ),
                  ),
                ),
              ],

              // 수집 상태 표시
              Container(
                decoration: AppTheme.cardDecoration(
                  gradient: _isCollecting
                      ? const LinearGradient(
                          colors: [
                            Color(0xFF1E1E1E),
                            Color(0xFF2A2A2A),
                          ],
                        )
                      : AppTheme.darkGradient,
                ),
                padding: Responsive.cardPadding(context),
                child: Column(
                  children: [
                    // 상태 아이콘
                    Container(
                      padding: EdgeInsets.all(
                        Responsive.isSmallScreen(context) ? 16 : 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isCollecting
                            ? Icons.monitor_heart
                            : _analysisResult != null
                                ? Icons.check_circle
                                : Icons.touch_app_outlined,
                        color: Colors.white,
                        size: Responsive.isSmallScreen(context) ? 40 : 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 상태 텍스트
                    Text(
                      _isCollecting
                          ? '측정 중...'
                          : _analysisResult != null
                              ? '측정 완료'
                              : (!_hasBaseline && !_isCheckingBaseline
                                  ? '기준값 설정 준비'
                                  : '측정 준비'),
                      style: TextStyle(
                        fontSize: Responsive.isSmallScreen(context) ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (_isCollecting) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_remainingSeconds.toStringAsFixed(1)}초 남음',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: 1 -
                              (_remainingSeconds / _customMeasurementSeconds),
                          backgroundColor: Colors.white.withOpacity(0.2),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                          minHeight: 8,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // 실시간 분석 상태 표시 (ML 모드별 색상)
                    _buildAnalysisStatusBox(),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_qualityWarningMessage != null) ...[
                _buildQualityWarningBanner(),
                const SizedBox(height: 16),
              ],

              // 기준값 설정 완료 배너 (값 + 선택지)
              if (_justCompletedBaseline && _completedBaseline != null) ...[
                Container(
                  decoration: AppTheme.cardDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3C34), Color(0xFF1E1E1E)],
                    ),
                  ),
                  padding: Responsive.cardPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '기준값 설정이 완료되었습니다',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildBaselineSummaryValue(
                            'RMS',
                            ((_completedBaseline?['fatigueRMS'] ?? 0.0)
                                    as double)
                                .toStringAsFixed(4),
                            'm/s²',
                          ),
                          _buildBaselineSummaryValue(
                            'Freq',
                            ((_completedBaseline?['peakFreq'] ?? 0.0) as double)
                                .toStringAsFixed(1),
                            'Hz',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _justCompletedBaseline = false;
                                _completedBaseline = null;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            child: const Text('나중에'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ProfilePage(),
                                ),
                              );
                              if (!mounted) return;
                              setState(() {
                                _justCompletedBaseline = false;
                                _completedBaseline = null;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                            ),
                            child: const Text('내 정보에서 보기'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_isAiProcessing) ...[
                _buildAiProcessingBanner(),
                const SizedBox(height: 16),
              ],

              // 측정 결과 카드 (기준값 설정 중/직후에는 숨김)
              if (_analysisResult != null &&
                  !_isCollecting &&
                  _hasBaseline &&
                  !_isBaselineSetting &&
                  !_justCompletedBaseline) ...[
                _buildFatigueScoreCard(_analysisResult!),
                const SizedBox(height: 16),
                _buildMainResultCard(_analysisResult!),
                const SizedBox(height: 16),
              ],

              // 컨트롤 버튼들
              if (!_isCollecting) ...[
                Container(
                  width: double.infinity,
                  height: Responsive.isSmallScreen(context) ? 56 : 60,
                  decoration: AppTheme.cardDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: 16,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isCheckingBaseline
                          ? null
                          : (!_hasBaseline
                              ? _startBaselineInline
                              : _startCollection),
                      borderRadius: BorderRadius.circular(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: Responsive.isSmallScreen(context) ? 24 : 28,
                          ),
                          SizedBox(
                            width: Responsive.isSmallScreen(context) ? 8 : 12,
                          ),
                          Flexible(
                            child: Text(
                              _isCheckingBaseline
                                  ? '기준값 확인 중...'
                                  : !_hasBaseline
                                      ? '기준값 설정 시작'
                                      : '${_customMeasurementSeconds.toStringAsFixed(1)}초 측정 시작',
                              style: TextStyle(
                                fontSize:
                                    Responsive.isSmallScreen(context) ? 16 : 18,
                                fontWeight: FontWeight.bold,
                                color: _isCheckingBaseline
                                    ? Colors.orange
                                    : Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  height: Responsive.isSmallScreen(context) ? 56 : 60,
                  decoration: AppTheme.cardDecoration(
                    color: AppTheme.highFatigueColor,
                    borderRadius: 16,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _stopCollection,
                      borderRadius: BorderRadius.circular(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.stop_circle,
                            color: Colors.white,
                            size: Responsive.isSmallScreen(context) ? 24 : 28,
                          ),
                          SizedBox(
                            width: Responsive.isSmallScreen(context) ? 8 : 12,
                          ),
                          Text(
                            '측정 중지',
                            style: TextStyle(
                              fontSize:
                                  Responsive.isSmallScreen(context) ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // 측정 중 배너 광고 (광고가 실제로 준비되었을 때만 표시)
              if (_isCollecting) ...[
                Builder(
                  builder: (context) {
                    // 광고 상태를 안전하게 확인
                    final adManager = AdManager.instance;
                    if (!adManager.isBannerAdReady) {
                      return const SizedBox.shrink();
                    }

                    final bannerAd = adManager.bannerAd;
                    if (bannerAd == null) {
                      return const SizedBox.shrink();
                    }

                    try {
                      // 광고 size 유효성 검사
                      final adSize = bannerAd.size;
                      if (adSize.width <= 0 || adSize.height <= 0) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        children: [
                          const SizedBox(height: 16),
                          Container(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: adSize.width.toDouble(),
                              height: adSize.height.toDouble(),
                              child: AdWidget(ad: bannerAd),
                            ),
                          ),
                        ],
                      );
                    } catch (e, stackTrace) {
                      // 에러 발생 시 로그 출력 및 빈 위젯 반환
                      debugPrint('❌ 배너 광고 표시 오류: $e');
                      debugPrint('스택 트레이스: $stackTrace');
                      return const SizedBox.shrink();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 피로도 점수 카드 (게이지 위젯 사용)
  Widget _buildFatigueScoreCard(Map<String, dynamic> result) {
    final fatigueScore = result['fatigueScore'] ?? 1.0;
    final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);

    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: AppTheme.fatigueGradient(fatigueScore),
      ),
      padding: Responsive.cardPadding(context),
      child: Column(
        children: [
          // 피로도 레벨 배지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.isSmallScreen(context) ? 16 : 20,
              vertical: Responsive.isSmallScreen(context) ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFatigueLevelIcon(fatigueLevel),
                  color: Colors.white,
                  size: Responsive.isSmallScreen(context) ? 20 : 24,
                ),
                SizedBox(width: Responsive.isSmallScreen(context) ? 6 : 8),
                Text(
                  fatigueLevel,
                  style: TextStyle(
                    fontSize: Responsive.isSmallScreen(context) ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 게이지 위젯
          FatigueGaugeWidget(
            fatigueScore: fatigueScore,
            previousScore: null,
          ),
          const SizedBox(height: 16),
          // 점수 표시
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  fatigueScore.toStringAsFixed(2),
                  style: GoogleFonts.inter(
                    fontSize: Responsive.isSmallScreen(context) ? 36 : 44,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(width: Responsive.isSmallScreen(context) ? 6 : 8),
                Text(
                  '/ 3.0',
                  style: TextStyle(
                    fontSize: Responsive.isSmallScreen(context) ? 14 : 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // AppBar 아이콘 버튼 (통일된 스타일)
  Widget _buildAppBarIcon({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    final isSmall = Responsive.isSmallScreen(context);

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: isSmall ? 32 : 36,
        minHeight: isSmall ? 32 : 36,
      ),
      icon: Container(
        padding: EdgeInsets.all(isSmall ? 5 : 7),
        decoration: AppTheme.iconButtonDecoration(),
        child: Icon(
          icon,
          size: isSmall ? 16 : 18,
          color: AppTheme.primaryGreen,
        ),
      ),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }

  // 분석 상태 박스 (ML 모드별 색상 적용)
  Widget _buildAnalysisStatusBox() {
    final currentMode = BaselineManager.instance.getCurrentMLMode();
    final totalMeasurements = BaselineManager.instance.totalMeasurementCount;
    final nextMeasurementIndex = totalMeasurements + 1;

    int phaseStart = 0;
    int phaseTarget = MLPhaseConstants.emaPhaseThreshold;
    switch (currentMode) {
      case MLMode.ema:
        phaseStart = 0;
        phaseTarget = MLPhaseConstants.emaPhaseThreshold;
        break;
      case MLMode.hybrid:
        phaseStart = MLPhaseConstants.emaPhaseThreshold;
        phaseTarget = MLPhaseConstants.hybridPhaseThreshold;
        break;
      case MLMode.endToEnd:
        phaseStart = MLPhaseConstants.hybridPhaseThreshold;
        phaseTarget = MLPhaseConstants.endToEndPhaseThreshold;
        break;
    }
    int phaseSpan = phaseTarget - phaseStart;
    if (phaseSpan <= 0) {
      phaseSpan = 1;
    }
    final phaseCount =
        ((totalMeasurements - phaseStart).clamp(0, phaseSpan).toDouble());
    final personalizationProgress = (phaseCount / phaseSpan).clamp(0.0, 1.0);
    final progressPercent = (personalizationProgress * 100).round();
    final showPhaseCounter = phaseSpan > 1;

    // ML 모드별 색상 (명확하게 구분, profile_page와 동일)
    Color modeColor;
    IconData modeIcon;
    String statusMessage;

    switch (currentMode) {
      case MLMode.ema:
        modeColor = const Color(0xFF2196F3); // 파란색 (기본 학습)
        modeIcon = Icons.functions;
        statusMessage = '센서 데이터로 내 기준값 학습 중';
        break;
      case MLMode.hybrid:
        modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조)
        modeIcon = Icons.hub;
        statusMessage = 'AI가 보조하여 정확도 향상 중';
        break;
      case MLMode.endToEnd:
        modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 완전)
        modeIcon = Icons.psychology;
        statusMessage = 'AI가 직접 패턴을 분석 중';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            modeColor.withOpacity(0.15),
            modeColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: modeColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [modeColor, modeColor.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              modeIcon,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusMessage,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: modeColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${currentMode.displayName} • $nextMeasurementIndex번째 측정',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  showPhaseCounter
                      ? '정확도 향상 진행도 $progressPercent% '
                          '(${phaseCount.toInt()}/$phaseSpan회)'
                      : '정확도 향상 진행도 $progressPercent%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: modeColor.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: personalizationProgress == 0.0
                        ? 0.05
                        : personalizationProgress,
                    minHeight: 6,
                    backgroundColor: modeColor.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(modeColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '규칙적인 측정이 개인화 모델의 예측력을 높여줘요.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: modeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${currentMode.phase}단계',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: modeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 피로도 레벨별 아이콘
  IconData _getFatigueLevelIcon(String level) {
    switch (level) {
      case '정상':
        return Icons.sentiment_very_satisfied;
      case '약간 피로':
        return Icons.sentiment_satisfied;
      case '피로 누적':
        return Icons.sentiment_dissatisfied;
      case '고피로':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.help_outline;
    }
  }

  // 주요 결과 카드 (RMS, Variance, Freq)
  Widget _buildMainResultCard(Map<String, dynamic> result) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: Responsive.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: AppTheme.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '측정 데이터',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // RMS
          _buildMetricRow(
            icon: Icons.graphic_eq,
            label: '근육 활동량',
            value: (result['fatigueRMS'] ?? 0.0).toStringAsFixed(4),
            subtitle: '떨림 세기',
          ),
          const SizedBox(height: 16),

          // Variance
          _buildMetricRow(
            icon: Icons.show_chart,
            label: '신호 변동',
            value: (result['fatigueVariance'] ?? 0.0).toStringAsFixed(4),
            subtitle: '불규칙성',
          ),
          const SizedBox(height: 16),

          // Peak Frequency
          _buildMetricRow(
            icon: Icons.multiline_chart,
            label: '진동 빈도',
            value: '${(result['peakFreq'] ?? 0.0).toStringAsFixed(1)}회/초',
            subtitle: '주요 주파수',
          ),
          const SizedBox(height: 20),

          // 측정 시간
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: Colors.white.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(result['timestamp']),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 메트릭 행 위젯
  Widget _buildMetricRow({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    final isSmall = Responsive.isSmallScreen(context);

    return Container(
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isSmall ? 10 : 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryGreen,
              size: isSmall ? 20 : 24,
            ),
          ),
          SizedBox(width: isSmall ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isSmall ? 12 : 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: isSmall ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: isSmall ? 10 : 11,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 시간 포맷팅
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  // Baseline 초기 설정 다이얼로그
  void _showBaselineSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.settings_input_component,
                color: AppTheme.primaryGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                '기준값 설정 필요',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 중요 안내
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '정확한 피로도 측정을 위해\n개인 기준값 설정이 필요합니다',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 설정 방법 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.touch_app,
                          color: AppTheme.primaryGreen,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '설정 방법 (한 번만 하면 됩니다)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 단계별 안내
                    _buildStepGuide(
                      '1',
                      '기기 준비',
                      '스마트폰을 책상 위에 평평하게 올려놓습니다',
                      Icons.phone_android,
                    ),
                    const SizedBox(height: 12),
                    _buildStepGuide(
                      '2',
                      '기준값 설정',
                      '기준값 설정 버튼을 누르면 10초간 자동 측정됩니다',
                      Icons.settings_input_component,
                    ),
                    const SizedBox(height: 12),
                    _buildStepGuide(
                      '3',
                      '완료',
                      '설정 완료 후 개인 기준값이 저장됩니다',
                      Icons.check_circle_outline,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 추가 정보
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '왜 기준값 설정이 필요한가요?\n• 기기별 센서 특성 차이 보정\n• 개인별 손떨림 특성 반영\n• 더 정확한 피로도 측정 가능',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.withOpacity(0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '나중에',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startBaselineSetup();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '기준값 설정',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // 단계별 안내 위젯
  Widget _buildStepGuide(
    String step,
    String title,
    String description,
    IconData icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppTheme.primaryGreen,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(
          icon,
          color: AppTheme.primaryGreen,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Baseline 설정 시작
  Future<void> _startBaselineSetup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _BaselineSetupDialog(
          onComplete: (success) {
            if (success) {
              setState(() {
                _hasBaseline = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('개인 기준값 설정이 완료되었습니다! 이제 측정을 시작할 수 있습니다.'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
        );
      },
    );
  }

  // 설정 다이얼로그
  void _showSettingsDialog() {
    double tempWindowSeconds = _customMeasurementSeconds;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '설정',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 측정 시간 설정
                    const Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 20,
                          color: AppTheme.primaryGreen,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '측정 시간 (초)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: AppTheme.primaryGreen,
                              thumbColor: AppTheme.primaryGreen,
                              inactiveTrackColor: Colors.white.withOpacity(0.2),
                              overlayColor:
                                  AppTheme.primaryGreen.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: tempWindowSeconds,
                              min: 0.5,
                              max: 30,
                              divisions: 59,
                              label: '${tempWindowSeconds.toStringAsFixed(1)}초',
                              onChanged: _isCollecting
                                  ? null
                                  : (value) {
                                      setDialogState(() {
                                        tempWindowSeconds = value;
                                      });
                                    },
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '${tempWindowSeconds.toStringAsFixed(1)}초',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    if (_isCollecting)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          '⚠️ 측정 중에는 설정을 변경할 수 없습니다.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // 데이터 관리
                    const Row(
                      children: [
                        Icon(
                          Icons.storage_outlined,
                          size: 20,
                          color: AppTheme.highFatigueColor,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '데이터 관리',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 모든 측정 기록 삭제
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: !_isCollecting
                            ? () async {
                                Navigator.of(context).pop();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('확인'),
                                      ],
                                    ),
                                    content: const Text(
                                      '모든 측정 기록을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('취소'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('삭제'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && mounted) {
                                  await DatabaseHelper.instance
                                      .deleteAllFatigueLogs();
                                  await BaselineManager.instance
                                      .syncWithDatabase();

                                  // 센서 데이터도 초기화
                                  _sensorStreaming.clearData();

                                  setState(() {
                                    _analysisResult = null;
                                  });

                                  // 기준값 필요 여부 재평가
                                  await _checkBaselineStatus();

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('모든 측정 기록이 삭제되었습니다.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('모든 측정 기록 삭제'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: !_isCollecting ? Colors.red : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Baseline 초기화
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: !_isCollecting
                            ? () async {
                                Navigator.of(context).pop();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.orange,
                                        ),
                                        SizedBox(width: 8),
                                        Text('개인 기준값 초기화'),
                                      ],
                                    ),
                                    content: const Text(
                                      '개인 기준값을 초기화하시겠습니까?\n\n'
                                      '일반인 평균값으로 리셋되며,\n'
                                      '학습된 내 기준값이 모두 삭제됩니다.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('취소'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                        ),
                                        child: const Text('초기화'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && mounted) {
                                  await UserStateStore.instance.clearBaseline();
                                  await _loadBaseline();

                                  // 센서 데이터도 초기화
                                  _sensorStreaming.clearData();

                                  setState(() {
                                    // 데이터 초기화
                                  });

                                  // 기준값 필요 여부 재평가
                                  await _checkBaselineStatus();

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('개인 기준값이 초기화되었습니다.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.restore),
                        label: const Text('개인 기준값 초기화'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                          side: BorderSide(
                            color: !_isCollecting
                                ? Colors.deepOrange
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: _isCollecting
                      ? null
                      : () {
                          setState(() {
                            // 동적 측정시간 설정 적용
                            _customMeasurementSeconds = tempWindowSeconds;
                            print(
                              '✅ 측정시간이 ${_customMeasurementSeconds.toStringAsFixed(1)}초로 설정되었습니다.',
                            );
                          });
                          Navigator.of(context).pop();
                        },
                  child: const Text('적용'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 측정 안내 카드
  Widget _buildInstructionCard() {
    final isSmall = Responsive.isSmallScreen(context);

    // 측정 완료 후
    if (_analysisResult != null && !_isCollecting) {
      final currentMode = BaselineManager.instance.getCurrentMLMode();

      // ML 모드별 색상 (명확하게 구분, profile_page와 동일)
      Color modeColor;
      IconData modeIcon;

      switch (currentMode) {
        case MLMode.ema:
          modeColor = const Color(0xFF2196F3); // 파란색 (기본 학습)
          modeIcon = Icons.functions;
          break;
        case MLMode.hybrid:
          modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조)
          modeIcon = Icons.hub;
          break;
        case MLMode.endToEnd:
          modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 완전)
          modeIcon = Icons.psychology;
          break;
      }

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              modeColor.withOpacity(0.15),
              const Color(0xFF1E1E1E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: modeColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(isSmall ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [modeColor, modeColor.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    modeIcon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '측정이 완료되었습니다',
                    style: GoogleFonts.inter(
                      fontSize: isSmall ? 15 : 17,
                      fontWeight: FontWeight.bold,
                      color: modeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '측정 환경을 일정하게 유지하면 더 정확한 결과를 얻을 수 있습니다.',
              style: TextStyle(
                fontSize: isSmall ? 13 : 14,
                color: Colors.white.withOpacity(0.8),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: modeColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: modeColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '정확도 향상 팁 보기',
                      style: TextStyle(
                        fontSize: isSmall ? 12 : 13,
                        color: modeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: modeColor,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 측정 중
    if (_isCollecting) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryGreen.withOpacity(0.2),
              const Color(0xFF1E1E1E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primaryGreen.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(isSmall ? 16 : 20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '측정 중',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '움직이지 말고 ${_customMeasurementSeconds.toStringAsFixed(1)}초간 그대로 유지하세요.',
              style: TextStyle(
                fontSize: isSmall ? 14 : 15,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 측정 전 (기준값 설정 모드)
    if (!_hasBaseline && !_isCheckingBaseline) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF203A43), Color(0xFF1E1E1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.green.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(isSmall ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.settings_input_component,
                    color: AppTheme.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '기준값 설정 준비',
                    style: GoogleFonts.inter(
                      fontSize: isSmall ? 15 : 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInstructionItem(
              '1',
              '스마트폰을 책상 위에 평평하게 올려두세요. (움직이지 않기)',
              isSmall,
            ),
            const SizedBox(height: 10),
            _buildInstructionItem(
              '2',
              '화면이 위를 향하도록 두고 주변 진동이 적은 곳에서 진행하세요.',
              isSmall,
            ),
            const SizedBox(height: 10),
            _buildInstructionItem(
              '3',
              '아래 ‘기준값 설정 시작’ 버튼을 눌러 10초간 자동 측정합니다.',
              isSmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    color: Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '왜 기준값이 필요할까요?\n• 기기별 센서 차이를 보정합니다\n• 개인 손떨림 특성을 반영합니다\n• 이후 피로도 측정의 정확도가 높아집니다',
                      style: TextStyle(
                        fontSize: isSmall ? 12 : 13,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 측정 전
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A3E), Color(0xFF1E1E1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(isSmall ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '측정 전 안내',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 15 : 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionItem(
            '1',
            '의자에 앉은 상태에서, 팔을 책상 위에 편히 올려주세요.',
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '2',
            '스마트폰을 한 손으로 가볍게 쥐고, 움직이지 마세요.',
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '3',
            '화면이 위를 향하도록 평평하게 두세요.',
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '4',
            '준비가 되면 아래 시작 버튼을 눌러주세요.',
            isSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(String number, String text, bool isSmall) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isSmall ? 22 : 26,
          height: isSmall ? 22 : 26,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: isSmall ? 11 : 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryGreen,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: isSmall ? 12 : 13,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiProcessingBanner() {
    final isSmall = Responsive.isSmallScreen(context);
    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F1B2C), Color(0xFF131313)],
        ),
      ),
      padding: Responsive.cardPadding(context),
      child: Row(
        children: [
          SizedBox(
            height: isSmall ? 32 : 36,
            width: isSmall ? 32 : 36,
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 분석 중',
                  style: TextStyle(
                    fontSize: isSmall ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '결과가 곧 반영됩니다.',
                  style: TextStyle(
                    fontSize: isSmall ? 11 : 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Baseline 설정 다이얼로그 위젯
class _BaselineSetupDialog extends StatefulWidget {
  final Function(bool) onComplete;

  const _BaselineSetupDialog({required this.onComplete});

  @override
  State<_BaselineSetupDialog> createState() => _BaselineSetupDialogState();
}

class _BaselineSetupDialogState extends State<_BaselineSetupDialog> {
  final SensorStreaming _sensorStreaming = SensorStreaming();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  bool _isCollecting = false;
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = '기기를 책상 위에 평평하게 올려놓고 기준값 설정 버튼을 눌러주세요';
  Map<String, dynamic>? _baselineResult;

  Future<void> _startBaselineCollection() async {
    if (_isCollecting) return;

    setState(() {
      _isCollecting = true;
      _progress = 0.0;
      _statusMessage = '기기를 움직이지 말고 10초간 그대로 유지하세요...';
    });

    // 센서 시작
    final success = await _sensorStreaming.startSensor();
    if (!success) {
      setState(() {
        _isCollecting = false;
        _statusMessage = '센서 시작에 실패했습니다. 다시 시도해주세요.';
      });
      return;
    }

    // 10초간 데이터 수집
    int count = 0;
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      count++;
      final progress = count / 100.0; // 10초 = 100 * 100ms

      setState(() {
        _progress = progress;
        _statusMessage =
            '기기를 움직이지 말고 ${(10 - count * 0.1).toStringAsFixed(1)}초 남음...';
      });

      if (count >= 100) {
        timer.cancel();
        _processBaselineData();
      }
    });
  }

  Future<void> _processBaselineData() async {
    setState(() {
      _isCollecting = false;
      _isProcessing = true;
      _statusMessage = 'baseline 데이터를 분석 중입니다...';
    });

    // 센서 중지 및 데이터 처리
    await _sensorStreaming.stopSensor();

    // 최근 측정 결과 가져오기
    final result = _sensorStreaming.getLastWindowResult();

    if (result != null) {
      // baseline 데이터 저장
      await _dbHelper.saveBaseline(result);

      setState(() {
        _baselineResult = result;
        _isProcessing = false;
        _statusMessage = 'baseline 설정이 완료되었습니다!';
      });
    } else {
      setState(() {
        _isProcessing = false;
        _statusMessage = '데이터 수집에 실패했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  void dispose() {
    if (_isCollecting) {
      _sensorStreaming.stopSensor();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = Responsive.isSmallScreen(context);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.settings_input_component,
            color: AppTheme.primaryGreen,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            '개인 기준값 설정',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 진행 상태
            if (_isCollecting || _isProcessing) ...[
              Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: LinearProgressIndicator(
                  value: _isCollecting ? _progress : null,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _isProcessing ? Colors.orange : AppTheme.primaryGreen,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 상태 메시지
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: isSmall ? 14 : 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            if (_baselineResult != null) ...[
              const SizedBox(height: 20),
              // baseline 결과 표시
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '설정된 Baseline 값',
                      style: GoogleFonts.poppins(
                        fontSize: isSmall ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildBaselineValue(
                          'RMS',
                          '${(_baselineResult!['fatigueRMS'] ?? 0.0).toStringAsFixed(4)}',
                          'm/s²',
                        ),
                        _buildBaselineValue(
                          'Freq',
                          '${(_baselineResult!['peakFreq'] ?? 0.0).toStringAsFixed(1)}',
                          'Hz',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isCollecting && !_isProcessing && _baselineResult == null) ...[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onComplete(false);
            },
            child: Text(
              '취소',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _startBaselineCollection,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '기준값 설정',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ] else if (_baselineResult != null) ...[
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onComplete(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '완료',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBaselineValue(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white60,
          ),
        ),
      ],
    );
  }
}
