import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide UserIdentity;
import 'package:muscle_fatigue_tracker/utils/app_log.dart';
import 'sensor/streaming.dart';
import 'sensor/config.dart';
import 'model/database_helper.dart';
import 'model/baseline.dart';
import 'model/user_state_store.dart';
import 'model/measure_session.dart';
import 'model/config.dart';
import 'model/ml.dart';
import 'widgets/fatigue_gauge.dart';
import 'widgets/banner_ad_widget.dart';
import 'screens/measurement_history_page.dart';
import 'screens/main_home_page.dart';
import 'screens/heatmap_full_viewer_page.dart';
import 'screens/splash_screen.dart';
import 'screens/profile_page.dart';
import 'theme/app_theme.dart';
import 'utils/responsive.dart';
import 'utils/ad_manager.dart';
import 'worker/worker_manager.dart'; // 워커 매니저를 위해 필요
import 'worker/model_update_scheduler.dart';
import 'model/personalization_manager.dart';
import 'utils/user_identity.dart';
import 'services/supabase_runtime_state.dart';
import 'features/heatmap/model/heatmap_models.dart';
import 'features/heatmap/data/heatmap_api_config.dart';
import 'features/heatmap/ui/heatmap_bridge_cta_card.dart';
import 'providers/heatmap_provider.dart';

void main() async {
  if (kDebugMode) {
    appLog('\n🚀 앱 시작...');
    appLog('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  WidgetsFlutterBinding.ensureInitialized();
  await AdManager.instance.initialize();
  await EasyLocalization.ensureInitialized();
  await UserIdentity.instance.ensureInitialized();
  await _initializeSupabaseClient();
  final migratedFrom = UserIdentity.instance.lastMigratedFrom;
  if (migratedFrom != null) {
    final newId = await UserIdentity.instance.userId;
    await DatabaseHelper.instance.migrateUserId(
      oldUserId: migratedFrom,
      newUserId: newId,
    );
  }

  // 데이터베이스 초기화
  if (kDebugMode) {
    appLog('🗄️ 데이터베이스 초기화 중...');
  }
  try {
    final db = await DatabaseHelper.instance.database;
    if (kDebugMode) {
      appLog('✅ 통합 DB 초기화 완료');
      appLog('   - DB 경로: ${db.path}');
    }

    // Baseline Manager 초기화
    await BaselineManager.instance.initialize();
    if (kDebugMode) {
      appLog('✅ Baseline Manager 초기화 완료');
    }

    // ML Manager 초기화
    await MLManager.instance.initialize();
    if (kDebugMode) {
      appLog('✅ ML Manager 초기화 완료');
    }

    // Worker Manager 초기화
    await initializeWorkerManager();
    if (kDebugMode) {
      appLog('✅ Worker Manager 초기화 완료');
    }

    // User Embedding은 분석 시에만 계산됨
    if (kDebugMode) {
      appLog('✅ User Embedding은 분석 시에 자동 계산됩니다');
    }

    await ModelUpdateScheduler.instance.start();
    if (kDebugMode) {
      appLog('✅ 모델 자동 다운로드 스케줄러 시작');
    }

    await PersonalizationManager.instance.initialize();
    await PersonalizationManager.instance.ensurePersonalization();
    if (kDebugMode) {
      appLog('✅ 개인화 매니저 초기화 및 점검 완료');
    }
  } catch (e, stackTrace) {
    if (kDebugMode) {
      appLog('❌ 초기화 실패: $e');
      appLog('스택 트레이스: $stackTrace');
    }
  }

  if (kDebugMode) {
    appLog('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('ko', 'KR'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: const MyApp(),
    ),
  );
}

Future<void> _initializeSupabaseClient() async {
  if (SupabaseRuntimeState.isTemporarilySuspended) {
    if (kDebugMode) {
      appLog(
        '⚠️ Supabase 초기화 일시중지 상태: ${SupabaseRuntimeState.lastReason ?? 'unknown'}',
      );
    }
    return;
  }
  final config = HeatmapApiConfig.fromEnvironment();

  if (!config.isConfigured) {
    if (kDebugMode) {
      appLog('⚠️ Supabase 설정이 비어 있어 초기화를 건너뜁니다.');
    }
    return;
  }

  try {
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.publishableKey,
    );
    final sessionReady = await _ensureAnonymousSupabaseSession(
      config.supabaseUrl,
    );
    if (sessionReady) {
      SupabaseRuntimeState.clearSuspension();
    }
  } catch (error) {
    SupabaseRuntimeState.suspendFor(
      const Duration(minutes: 3),
      reason: 'init_failed',
    );
    if (kDebugMode) {
      appLog('⚠️ Supabase 초기화 실패: $error');
    }
  }
}

Future<bool> _ensureAnonymousSupabaseSession(String supabaseUrl) async {
  final client = Supabase.instance.client;
  // 1) 기존 세션이 유효하면 그대로 사용
  try {
    final currentUser = client.auth.currentUser;
    if (currentUser != null) {
      await _verifySupabaseUrlCall(client, supabaseUrl);
      return true;
    }
  } catch (_) {
    // 기존 세션이 유효하지 않으면 익명 세션 재생성으로 복구
  }

  // 2) 세션이 없거나 만료되면 익명 로그인 시도
  try {
    final deviceUserId = await UserIdentity.instance.userId;
    final authResponse = await client.auth.signInAnonymously(
      data: {'device_user_id': deviceUserId},
    );
    if (authResponse.user == null) {
      throw const AuthException('익명 세션 생성에 실패했습니다.');
    }
    await _verifySupabaseUrlCall(client, supabaseUrl);
    SupabaseRuntimeState.clearSuspension();
    return true;
  } catch (error) {
    SupabaseRuntimeState.suspendFor(
      const Duration(minutes: 3),
      reason: 'anonymous_session_failed',
    );
    if (kDebugMode) {
      appLog('⚠️ Supabase 익명 세션 확보 실패: $error');
    }
    return false;
  }
}

Future<void> _verifySupabaseUrlCall(
  SupabaseClient client,
  String supabaseUrl,
) async {
  final userResponse = await client.auth.getUser();
  if (userResponse.user == null) {
    throw const AuthException('현재 세션 사용자 정보를 불러오지 못했습니다.');
  }
  if (kDebugMode) {
    appLog('✅ Supabase URL 호출 성공: $supabaseUrl');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HeatmapProvider>(
      create: (_) => HeatmapProvider(),
      child: MaterialApp(
        title: 'Muscle Care',
        onGenerateTitle: (_) => 'app.title'.tr(),
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: const SplashScreen(),
        // 오류 발생 시 빨간 화면 대신 에러 위젯 표시
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.0)),
            child: child!,
          );
        },
      ),
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

  // 동적 분석시간 설정
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

  // (실제 분석 상태를 고정 메시지로 표시)

  // Baseline 상태 확인
  Future<void> _checkBaselineStatus() async {
    try {
      // DB 상태 동기화: 첫 분석 여부 + 기준값 존재 여부 모두 확인
      final isFirstMeasurement =
          await DatabaseHelper.instance.isFirstMeasurement();
      final hasBaselineInDb = await DatabaseHelper.instance.hasBaseline();

      final needBaseline = isFirstMeasurement || !hasBaselineInDb;

      setState(() {
        _hasBaseline = !needBaseline; // 필요하면 false, 아니면 true
        _isCheckingBaseline = false;
      });

      if (needBaseline) {
        if (kDebugMode) {
          appLog(
            '⚠️ 기준값 설정 필요: (isFirst=$isFirstMeasurement, hasBaseline=$hasBaselineInDb)',
          );
        }
      } else {
        if (kDebugMode) {
          appLog('✅ 기준값 사용 가능');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        appLog('❌ 기준값 상태 확인 실패: $e');
      }
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
            // 분석 완료 후 결과가 있으면 기준값 완료 배너 플래그 리셋
            // (사용자가 "나중에" 버튼을 누르지 않아도 결과가 표시되도록)
            if (_justCompletedBaseline && result['fatigueScore'] != null) {
              _justCompletedBaseline = false;
              _completedBaseline = null;
            }
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
      if (kDebugMode) {
        appLog('❌ initState 오류: $e');
        appLog('스택 트레이스: $stackTrace');
      }
    }
  }

  void _showQualityWarning(Map<String, dynamic> data) {
    if (!mounted) return;
    final coverage = (data['coverage'] as double?) ?? 0.0;
    final accel = data['accel'] ?? 0;
    final gyro = data['gyro'] ?? 0;
    final message = 'sensor.qualityWarning.message'.tr(
      namedArgs: {
        'coverage': coverage.toStringAsFixed(2),
        'accel': '$accel',
        'gyro': '$gyro',
      },
    );
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
                color: AppTheme.textHigh,
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
      if (kDebugMode) {
        appLog('❌ Baseline 로드 실패: $e');
        appLog('스택 트레이스: $stackTrace');
      }
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_isCollecting) {
        unawaited(_stopCollection());
      } else {
        unawaited(_sensorStreaming.stopSensor());
      }
      _autoStopTimer?.cancel();
      _baselineTimer?.cancel();
      return;
    }
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
    HapticFeedback.lightImpact();
    // Baseline이 설정되지 않은 경우 먼저 설정하도록 안내
    if (!_hasBaseline) {
      _showBaselineSetupDialog();
      return;
    }

    // 새로운 분석 시작 시 이전 데이터 초기화
    // 기준 맞추기 직후 첫 분석인 경우 플래그 리셋
    setState(() {
      _analysisResult = null;
      _isAiProcessing = false;
      _justCompletedBaseline = false; // 첫 분석 시작 시 리셋
      _completedBaseline = null; // 완료 배너도 리셋
    });

    final success = await _sensorStreaming.startSensor();

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('sensor.errors.cannotStartSensor'.tr()),
            duration: const Duration(seconds: 3),
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
        if (_isCollecting && mounted) {
          await _stopCollection();
          // 분석 완료 SnackBar 제거 (컨디션 점수 결과 카드만 표시)
        }
      },
    );
  }

  // 데이터 수집 중지
  Future<void> _stopCollection() async {
    HapticFeedback.lightImpact();
    await _sensorStreaming.stopSensor();
    _autoStopTimer?.cancel();

    // 분석 완료 후 기준값 상태 확인 (첫 분석 후 기준값이 설정되었을 수 있음)
    await _checkBaselineStatus();

    if (mounted) {
      setState(() {
        _isCollecting = false;
        _remainingSeconds = 0.0;
        // _analysisResult는 유지 (분석 결과 표시를 위해)
        // 기준값 설정 직후가 아니면 결과 표시 가능
        if (_justCompletedBaseline) {
          _justCompletedBaseline = false;
          _completedBaseline = null;
        }
      });
    }
  }

  // 완료 배너 값 표시용 (간단한 3줄 형태)
  Widget _buildBaselineSummaryValue(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMedium,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: AppTheme.textHigh,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textLow,
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
      _baselineStatus = 'sensor.baselineStatus.keepStill10s'.tr();
      _justCompletedBaseline = false;
      _analysisResult = null; // 결과 카드 숨김 보장
    });

    // 기준값 분석은 로그/업로드에서 제외되도록 플래그 설정
    _sensorStreaming.setExcludeFromLogging(true);

    final success = await _sensorStreaming.startSensor();
    if (!success) {
      // baseline 측정은 로그/업로드 제외 플래그를 사용하므로,
      // 센서 시작 실패 시 플래그가 남아 이후 정상 측정까지 "무시"되는 문제를 방지한다.
      _sensorStreaming.setExcludeFromLogging(false);
      setState(() {
        _isBaselineSetting = false;
        _baselineStatus = 'sensor.baselineStatus.cannotStartSensor'.tr();
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
        _baselineStatus = 'sensor.baselineStatus.keepStillRemaining'.tr(
          namedArgs: {'seconds': remain.toStringAsFixed(1)},
        );
      });

      if (tick >= 100) {
        timer.cancel();

        await _sensorStreaming.stopSensor();
        final result = _sensorStreaming.getLastWindowResult();

        if (result != null) {
          await UserStateStore.instance.saveBaseline(result);
          // 기준값 저장 후 상태 확인 및 업데이트
          await _checkBaselineStatus();
          if (!mounted) return;
          setState(() {
            // _checkBaselineStatus()에서 이미 _hasBaseline이 업데이트됨
            // 하지만 확실히 하기 위해 다시 설정
            _hasBaseline = true;
            _isCheckingBaseline = false;
            _isBaselineSetting = false;
            _baselineStatus = 'sensor.baselineStatus.completed'.tr();
            _justCompletedBaseline = true;
            _analysisResult = null; // 이번 세션은 컨디션 점수 카드 미노출
          });
          // 자동 이동 대신 완료 배너로 선택 유도
          _completedBaseline = result;
          if (kDebugMode) {
            appLog('✅ 기준값 설정 완료: _hasBaseline=$_hasBaseline');
          }
        } else {
          if (!mounted) return;
          setState(() {
            _isBaselineSetting = false;
            _baselineStatus = 'sensor.baselineStatus.collectFailed'.tr();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('sensor.errors.baselineFailed'.tr()),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const showSmartBanner = true;

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
            icon: Icons.history_outlined,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MeasurementHistoryPage(),
                ),
              );
              if (!mounted) return;
              // 다른 페이지에서 돌아왔을 때 분석 결과 초기화
              setState(() {
                _analysisResult = null;
              });
            },
            tooltip: 'sensor.tooltips.history'.tr(),
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
              // 다른 페이지에서 돌아왔을 때 분석 결과 초기화
              setState(() {
                _analysisResult = null;
              });
              await _checkBaselineStatus();
              await _loadBaseline();
            },
            tooltip: 'sensor.tooltips.profile'.tr(),
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 2 : 6),
          _buildAppBarIcon(
            icon: Icons.settings_outlined,
            onPressed: _showSettingsDialog,
            tooltip: 'sensor.tooltips.settings'.tr(),
          ),
          SizedBox(width: Responsive.isSmallScreen(context) ? 4 : 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: Responsive.responsivePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 분석 안내 카드
              _buildInstructionCard(),
              const SizedBox(height: 16),

              if (_isBaselineSetting) ...[
                Container(
                  width: double.infinity,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.textHigh.withValues(alpha: 0.15),
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
                        color: AppTheme.textHigh.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isCollecting
                            ? Icons.monitor_heart
                            : _analysisResult != null
                                ? Icons.check_circle
                                : Icons.touch_app_outlined,
                        color: AppTheme.textHigh,
                        size: Responsive.isSmallScreen(context) ? 40 : 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 상태 텍스트
                    Text(
                      _isCollecting
                          ? 'sensor.state.analyzing'.tr()
                          : _analysisResult != null
                              ? 'sensor.state.done'.tr()
                              : (!_hasBaseline && !_isCheckingBaseline
                                  ? 'sensor.state.prepareBaseline'.tr()
                                  : 'sensor.state.ready'.tr()),
                      style: TextStyle(
                        fontSize: Responsive.isSmallScreen(context) ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textHigh,
                      ),
                    ),
                    if (_isCollecting) ...[
                      const SizedBox(height: 8),
                      Text(
                        'sensor.state.remaining'.tr(
                          namedArgs: {
                            'seconds': _remainingSeconds.toStringAsFixed(1),
                          },
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textMedium,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: 1 -
                              (_remainingSeconds / _customMeasurementSeconds),
                          backgroundColor: AppTheme.textHigh.withValues(
                            alpha: 0.2,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.textHigh,
                          ),
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
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'sensor.baseline.completed'.tr(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textHigh,
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
                              foregroundColor: AppTheme.textMedium,
                            ),
                            child: Text('common.later'.tr()),
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
                                _analysisResult =
                                    null; // 다른 페이지에서 돌아왔을 때 분석 결과 초기화
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                            ),
                            child: Text('sensor.buttons.viewProfile'.tr()),
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

              // 분석 결과 카드 (기준값 설정 중/직후에는 숨김)
              if (_analysisResult != null &&
                  !_isCollecting &&
                  _hasBaseline &&
                  !_isBaselineSetting &&
                  !_justCompletedBaseline) ...[
                _buildFatigueScoreCard(_analysisResult!),
                const SizedBox(height: 16),
                _buildMainResultCard(_analysisResult!),
                const SizedBox(height: 12),
                _buildHeatmapBridgeCard(_analysisResult!),
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
                            color: AppTheme.ctaOnBrand,
                            size: Responsive.isSmallScreen(context) ? 24 : 28,
                          ),
                          SizedBox(
                            width: Responsive.isSmallScreen(context) ? 8 : 12,
                          ),
                          Flexible(
                            child: Text(
                              _isCheckingBaseline
                                  ? 'sensor.buttons.checkingBaseline'.tr()
                                  : !_hasBaseline
                                      ? 'sensor.buttons.startBaseline'.tr()
                                      : 'sensor.buttons.startAnalysis'.tr(
                                          namedArgs: {
                                            'seconds': _customMeasurementSeconds
                                                .toStringAsFixed(1),
                                          },
                                        ),
                              style: TextStyle(
                                fontSize:
                                    Responsive.isSmallScreen(context) ? 16 : 18,
                                fontWeight: FontWeight.bold,
                                color: _isCheckingBaseline
                                    ? Colors.orange
                                    : AppTheme.ctaOnBrand,
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
                            color: AppTheme.textHigh,
                            size: Responsive.isSmallScreen(context) ? 24 : 28,
                          ),
                          SizedBox(
                            width: Responsive.isSmallScreen(context) ? 8 : 12,
                          ),
                          Text(
                            'sensor.buttons.stopAnalysis'.tr(),
                            style: TextStyle(
                              fontSize:
                                  Responsive.isSmallScreen(context) ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textHigh,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // 측정 대기/분석 결과 체류 구간에서만 자연스럽게 노출
              if (showSmartBanner) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: AppTheme.textHigh.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.textHigh.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const BannerAdWidget(
                    key: ValueKey('sensor_analysis_banner'),
                    showPlaceholder: false,
                    padding: EdgeInsets.symmetric(vertical: 4),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.textHigh.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.textHigh.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.health_and_safety_outlined,
                      color: Colors.orangeAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'sensor.disclaimer.compact'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMedium,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 컨디션 점수 카드 (게이지 위젯 사용)
  Widget _buildFatigueScoreCard(Map<String, dynamic> result) {
    final fatigueScore = result['fatigueScore'] ?? 1.0;
    final fatigueLevel = FatigueCalculator.getFatigueLevel(fatigueScore);
    final localizedFatigueLevel = _localizedFatigueLevel(fatigueLevel);

    return Container(
      decoration: AppTheme.cardDecoration(
        gradient: AppTheme.fatigueGradient(fatigueScore),
      ),
      padding: Responsive.cardPadding(context),
      child: Column(
        children: [
          // 컨디션 레벨 배지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.isSmallScreen(context) ? 16 : 20,
              vertical: Responsive.isSmallScreen(context) ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: AppTheme.textHigh.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFatigueLevelIcon(fatigueLevel),
                  color: AppTheme.textHigh,
                  size: Responsive.isSmallScreen(context) ? 20 : 24,
                ),
                SizedBox(width: Responsive.isSmallScreen(context) ? 6 : 8),
                Text(
                  localizedFatigueLevel,
                  style: TextStyle(
                    fontSize: Responsive.isSmallScreen(context) ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textHigh,
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
                    color: AppTheme.textHigh,
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(width: Responsive.isSmallScreen(context) ? 6 : 8),
                Text(
                  '/ 3.0',
                  style: TextStyle(
                    fontSize: Responsive.isSmallScreen(context) ? 14 : 18,
                    color: AppTheme.textMedium,
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
    String modeLabel;

    switch (currentMode) {
      case MLMode.ema:
        modeColor = const Color(0xFF2196F3); // 파란색 (기본 학습)
        modeIcon = Icons.functions;
        statusMessage = 'sensor.aiStatus.ema'.tr();
        modeLabel = 'sensor.aiMode.ema'.tr();
        break;
      case MLMode.hybrid:
        modeColor = const Color(0xFF00ACC1); // 청록색 (AI 보조)
        modeIcon = Icons.hub;
        statusMessage = 'sensor.aiStatus.hybrid'.tr();
        modeLabel = 'sensor.aiMode.hybrid'.tr();
        break;
      case MLMode.endToEnd:
        modeColor = const Color(0xFF9C27B0); // 진보라색 (AI 완전)
        modeIcon = Icons.psychology;
        statusMessage = 'sensor.aiStatus.endToEnd'.tr();
        modeLabel = 'sensor.aiMode.endToEnd'.tr();
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
              color: AppTheme.textHigh,
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
                  'sensor.aiMode.round'.tr(
                    namedArgs: {
                      'mode': modeLabel,
                      'round': nextMeasurementIndex.toString(),
                    },
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  showPhaseCounter
                      ? 'sensor.aiMode.progressWithCount'.tr(
                          namedArgs: {
                            'percent': '$progressPercent',
                            'count': '${phaseCount.toInt()}',
                            'span': '$phaseSpan',
                          },
                        )
                      : 'sensor.aiMode.progressOnly'.tr(
                          namedArgs: {'percent': '$progressPercent'},
                        ),
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
                  'sensor.aiMode.tip'.tr(),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textLow,
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
              'sensor.aiMode.phase'.tr(
                namedArgs: {'phase': '${currentMode.phase}'},
              ),
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

  // 컨디션 레벨별 아이콘
  IconData _getFatigueLevelIcon(String level) {
    switch (_fatigueLevelCode(level)) {
      case 'recovered':
        return Icons.sentiment_very_satisfied;
      case 'recovering':
        return Icons.sentiment_satisfied;
      case 'delayed':
        return Icons.sentiment_dissatisfied;
      case 'need_recovery':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.help_outline;
    }
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

  // 주요 결과 카드 (RMS, Variance, Freq)
  Widget _buildMainResultCard(Map<String, dynamic> result) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: Responsive.cardPadding(context),
      constraints: const BoxConstraints(minHeight: 320),
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
              Expanded(
                child: Text(
                  'sensor.result.title'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textHigh,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // RMS
          _buildMetricRow(
            icon: Icons.graphic_eq,
            label: 'sensor.metrics.activity'.tr(),
            value: (result['fatigueRMS'] ?? 0.0).toStringAsFixed(4),
            subtitle: 'sensor.metrics.activitySub'.tr(),
          ),
          const SizedBox(height: 16),

          // Variance
          _buildMetricRow(
            icon: Icons.show_chart,
            label: 'sensor.metrics.variation'.tr(),
            value: (result['fatigueVariance'] ?? 0.0).toStringAsFixed(4),
            subtitle: 'sensor.metrics.variationSub'.tr(),
          ),
          const SizedBox(height: 16),

          // Peak Frequency
          _buildMetricRow(
            icon: Icons.multiline_chart,
            label: 'sensor.metrics.frequency'.tr(),
            value: 'sensor.metrics.frequencyUnit'.tr(
              namedArgs: {
                'value': (result['peakFreq'] ?? 0.0).toStringAsFixed(1),
              },
            ),
            subtitle: 'sensor.metrics.frequencySub'.tr(),
          ),
          const SizedBox(height: 12),
          // 분석 시간
          Divider(color: AppTheme.textHigh.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: AppTheme.textMedium,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _formatTime(result['timestamp']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMedium,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapBridgeCard(Map<String, dynamic> analysisResult) {
    final payload = MeasurementBridgePayload.fromAnalysisResult(analysisResult);

    return HeatmapBridgeCtaCard(
      payload: payload,
      onViewHeatmap: () => _openHeatmapPage(
        payload: payload,
        openQuickRecordOnStart: false,
      ),
      onQuickRecord: () => _openHeatmapPage(
        payload: payload,
        openQuickRecordOnStart: true,
      ),
    );
  }

  Future<void> _openHeatmapPage({
    required MeasurementBridgePayload payload,
    required bool openQuickRecordOnStart,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => openQuickRecordOnStart
            ? MainHomePage(
                openLogSheetOnStart: true,
                bridgePayload: payload,
              )
            : const HeatmapFullViewerPage(),
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
      constraints: const BoxConstraints(minHeight: 80),
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      decoration: BoxDecoration(
        color: AppTheme.textHigh.withValues(alpha: 0.05),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isSmall ? 12 : 14,
                    color: AppTheme.textMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    fontSize: isSmall ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textHigh,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isSmall ? 10 : 11,
                    color: AppTheme.textLow,
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
                'sensor.baselineGuide.title'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textHigh,
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
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'sensor.baselineGuide.need'.tr(),
                        style: const TextStyle(
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
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app,
                          color: AppTheme.primaryGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'sensor.baselineGuide.howTo'.tr(),
                          style: const TextStyle(
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
                      'sensor.baselineGuide.step1.title'.tr(),
                      'sensor.baselineGuide.step1.desc'.tr(),
                      Icons.phone_android,
                    ),
                    const SizedBox(height: 12),
                    _buildStepGuide(
                      '2',
                      'sensor.baselineGuide.step2.title'.tr(),
                      'sensor.baselineGuide.step2.desc'.tr(),
                      Icons.settings_input_component,
                    ),
                    const SizedBox(height: 12),
                    _buildStepGuide(
                      '3',
                      'sensor.baselineGuide.step3.title'.tr(),
                      'sensor.baselineGuide.step3.desc'.tr(),
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
                        'sensor.baselineGuide.why'.tr(),
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
                'common.later'.tr(),
                style: TextStyle(
                  color: AppTheme.textMedium,
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
              child: Text(
                'sensor.baselineGuide.start'.tr(),
                style: const TextStyle(color: AppTheme.ctaOnBrand),
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
              style: TextStyle(
                color: AppTheme.textHigh,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textHigh,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMedium,
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
                SnackBar(
                  content: Text('sensor.baselineGuide.completedToast'.tr()),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
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
                      color: AppTheme.ctaOnBrand,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'sensor.settings.title'.tr(),
                    style: TextStyle(
                      color: AppTheme.textHigh,
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
                    // 분석 시간 설정
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 20,
                          color: AppTheme.primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'sensor.settings.analysisDuration'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.textHigh,
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
                              inactiveTrackColor: AppTheme.textHigh.withValues(
                                alpha: 0.2,
                              ),
                              overlayColor:
                                  AppTheme.primaryGreen.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: tempWindowSeconds,
                              min: 0.5,
                              max: 30,
                              divisions: 59,
                              label: 'sensor.settings.seconds'.tr(
                                namedArgs: {
                                  'seconds': tempWindowSeconds.toStringAsFixed(
                                    1,
                                  ),
                                },
                              ),
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
                            'sensor.settings.seconds'.tr(
                              namedArgs: {
                                'seconds': tempWindowSeconds.toStringAsFixed(1),
                              },
                            ),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'sensor.settings.locked'.tr(),
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // 데이터 관리
                    Row(
                      children: [
                        const Icon(
                          Icons.storage_outlined,
                          size: 20,
                          color: AppTheme.highFatigueColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'sensor.settings.dataManagement'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.textHigh,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 모든 기록 삭제
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: !_isCollecting
                            ? () async {
                                Navigator.of(context).pop();
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'sensor.settings.confirm.title'.tr(),
                                        ),
                                      ],
                                    ),
                                    content: Text(
                                      'sensor.settings.confirm.deleteAllLogs'
                                          .tr(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text('common.cancel'.tr()),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: Text('common.delete'.tr()),
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
                                  if (!mounted || !context.mounted) {
                                    return;
                                  }

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'sensor.settings.deleteAllDone'.tr(),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.delete_forever),
                        label: Text('sensor.settings.deleteAllLogs'.tr()),
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
                                    title: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'sensor.settings.resetBaseline'.tr(),
                                        ),
                                      ],
                                    ),
                                    content: Text(
                                      'sensor.settings.confirm.resetBaseline'
                                          .tr(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text('common.cancel'.tr()),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                        ),
                                        child: Text('common.reset'.tr()),
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
                                  if (!mounted || !context.mounted) {
                                    return;
                                  }

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'sensor.settings.resetBaselineDone'
                                            .tr(),
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.restore),
                        label: Text('sensor.settings.resetBaseline'.tr()),
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
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.textHigh.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.textHigh.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.health_and_safety_outlined,
                            color: Colors.orangeAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'sensor.settings.disclaimer'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMedium,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
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
                  child: Text('common.cancel'.tr()),
                ),
                ElevatedButton(
                  onPressed: _isCollecting
                      ? null
                      : () {
                          setState(() {
                            // 동적 분석시간 설정 적용
                            _customMeasurementSeconds = tempWindowSeconds;
                            if (kDebugMode) {
                              appLog(
                                '✅ 분석 시간이 ${_customMeasurementSeconds.toStringAsFixed(1)}초로 설정되었습니다.',
                              );
                            }
                          });
                          Navigator.of(context).pop();
                        },
                  child: Text('common.apply'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 분석 안내 카드
  Widget _buildInstructionCard() {
    final isSmall = Responsive.isSmallScreen(context);

    // 분석 완료 후
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
                    color: AppTheme.textHigh,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'sensor.instructions.analysisDone'.tr(),
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
              'sensor.instructions.analysisDoneDesc'.tr(),
              style: TextStyle(
                fontSize: isSmall ? 13 : 14,
                color: AppTheme.textMedium,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
                if (!mounted) return;
                // 다른 페이지에서 돌아왔을 때 분석 결과 초기화
                setState(() {
                  _analysisResult = null;
                });
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
                      'sensor.instructions.viewPersonalizationTip'.tr(),
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
            const SizedBox(height: 12),
            _buildMedicalDisclaimer(),
          ],
        ),
      );
    }

    // 분석 중
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
                  'sensor.instructions.analyzingTitle'.tr(),
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
              'sensor.instructions.analyzingDesc'.tr(
                namedArgs: {
                  'seconds': _customMeasurementSeconds.toStringAsFixed(1),
                },
              ),
              style: TextStyle(
                fontSize: isSmall ? 14 : 15,
                color: AppTheme.textHigh,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _buildMedicalDisclaimer(compact: true),
          ],
        ),
      );
    }

    // 분석 전 (기준값 설정 모드)
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
                    'sensor.instructions.baselineIntroTitle'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: isSmall ? 15 : 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textHigh,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInstructionItem(
              '1',
              'sensor.instructions.baselineStep1'.tr(),
              isSmall,
            ),
            const SizedBox(height: 10),
            _buildInstructionItem(
              '2',
              'sensor.instructions.baselineStep2'.tr(),
              isSmall,
            ),
            const SizedBox(height: 10),
            _buildInstructionItem(
              '3',
              'sensor.instructions.baselineStep3'.tr(),
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
                      'sensor.instructions.baselineWhy'.tr(),
                      style: TextStyle(
                        fontSize: isSmall ? 12 : 13,
                        color: AppTheme.textMedium,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildMedicalDisclaimer(),
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
          color: AppTheme.textHigh.withValues(alpha: 0.1),
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
                  'sensor.instructions.preAnalysisTitle'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 15 : 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textHigh,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionItem(
            '1',
            'sensor.instructions.preStep1'.tr(),
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '2',
            'sensor.instructions.preStep2'.tr(),
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '3',
            'sensor.instructions.preStep3'.tr(),
            isSmall,
          ),
          const SizedBox(height: 10),
          _buildInstructionItem(
            '4',
            'sensor.instructions.preStep4'.tr(),
            isSmall,
          ),
          const SizedBox(height: 12),
          _buildMedicalDisclaimer(),
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
            color: AppTheme.textHigh.withValues(alpha: 0.1),
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
              color: AppTheme.textMedium,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicalDisclaimer({bool compact = false}) {
    final textStyle = TextStyle(
      fontSize: compact ? 11 : 12,
      color: AppTheme.textMedium,
      height: 1.4,
    );

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.textHigh.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.textHigh.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            color: Colors.orangeAccent,
            size: compact ? 18 : 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              compact
                  ? 'sensor.disclaimer.compact'.tr()
                  : 'sensor.disclaimer.full'.tr(),
              style: textStyle,
            ),
          ),
        ],
      ),
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
                  'sensor.aiProcessing.title'.tr(),
                  style: TextStyle(
                    fontSize: isSmall ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'sensor.aiProcessing.subtitle'.tr(),
                  style: TextStyle(
                    fontSize: isSmall ? 11 : 12,
                    color: AppTheme.textMedium,
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
  Timer? _collectionTimer;

  bool _isCollecting = false;
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = '';
  Map<String, dynamic>? _baselineResult;

  Future<void> _startBaselineCollection() async {
    if (_isCollecting) return;

    setState(() {
      _isCollecting = true;
      _progress = 0.0;
      _statusMessage = 'sensor.baselineDialog.keepStill10s'.tr();
    });

    // 센서 시작
    final success = await _sensorStreaming.startSensor();
    if (!success) {
      setState(() {
        _isCollecting = false;
        _statusMessage = 'sensor.baselineDialog.startFailed'.tr();
      });
      return;
    }

    // 10초간 데이터 수집
    int count = 0;
    _collectionTimer?.cancel();
    _collectionTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      count++;
      final progress = count / 100.0; // 10초 = 100 * 100ms

      setState(() {
        _progress = progress;
        _statusMessage = 'sensor.baselineDialog.remaining'.tr(
          namedArgs: {'seconds': (10 - count * 0.1).toStringAsFixed(1)},
        );
      });

      if (count >= 100) {
        timer.cancel();
        _collectionTimer = null;
        _processBaselineData();
      }
    });
  }

  Future<void> _processBaselineData() async {
    setState(() {
      _isCollecting = false;
      _isProcessing = true;
      _statusMessage = 'sensor.baselineDialog.processing'.tr();
    });

    // 센서 중지 및 데이터 처리
    await _sensorStreaming.stopSensor();

    // 최근 분석 결과 가져오기
    final result = _sensorStreaming.getLastWindowResult();

    if (result != null) {
      // baseline 데이터 저장
      await _dbHelper.saveBaseline(result);

      setState(() {
        _baselineResult = result;
        _isProcessing = false;
        _statusMessage = 'sensor.baselineDialog.done'.tr();
      });
    } else {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'sensor.baselineDialog.collectFailed'.tr();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _statusMessage = 'sensor.baselineDialog.initialGuide'.tr();
  }

  @override
  void dispose() {
    _collectionTimer?.cancel();
    if (_isCollecting) {
      unawaited(_sensorStreaming.stopSensor());
    }
    _sensorStreaming.dispose();
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
            'sensor.baselineDialog.title'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textHigh,
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
                  color: AppTheme.textHigh.withValues(alpha: 0.2),
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
                color: AppTheme.textHigh,
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
                      'sensor.baselineDialog.resultTitle'.tr(),
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
              'common.cancel'.tr(),
              style: TextStyle(
                color: AppTheme.textMedium,
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
            child: Text(
              'sensor.baselineDialog.start'.tr(),
              style: const TextStyle(color: AppTheme.ctaOnBrand),
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
            child: Text(
              'common.complete'.tr(),
              style: const TextStyle(color: AppTheme.ctaOnBrand),
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
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textMedium,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: AppTheme.textHigh,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textLow,
          ),
        ),
      ],
    );
  }
}
