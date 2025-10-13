import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';

import 'services/sensor_service.dart';
import 'services/analysis_service.dart';
import 'services/local_storage_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';

import 'providers/measurement_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/history_provider.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase 초기화
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 서비스 인스턴스 생성
    final sensorService = SensorService();
    final analysisService = AnalysisService();
    final storageService = LocalStorageService();
    final apiService = ApiService();
    final authService = AuthService();

    return MultiProvider(
      providers: [
        // Provider로 서비스 제공
        Provider<SensorService>.value(value: sensorService),
        Provider<AnalysisService>.value(value: analysisService),
        Provider<LocalStorageService>.value(value: storageService),
        Provider<ApiService>.value(value: apiService),
        Provider<AuthService>.value(value: authService),

        // ChangeNotifierProvider로 상태 관리
        ChangeNotifierProvider(
          create: (context) => AuthProvider(
            authService: authService,
            storageService: storageService,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => MeasurementProvider(
            sensorService: sensorService,
            analysisService: analysisService,
            storageService: storageService,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => HistoryProvider(
            storageService: storageService,
            apiService: apiService,
          ),
        ),
      ],
      child: MaterialApp(
        title: '근피로도 측정',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
        },
      ),
    );
  }
}

/// 스플래시 스크린 (초기 로딩 화면)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 초기화 작업 수행
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      final authProvider = context.read<AuthProvider>();

      // 로그인 상태에 따라 라우팅
      if (authProvider.isAuthenticated) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.fitness_center,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              '근피로도 측정',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

