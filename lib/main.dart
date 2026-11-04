import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:local_auth/local_auth.dart';

import 'core/app_colors.dart';
import 'screens/welcome_setup_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    // FCM Push Handler dành riêng cho Push Notifications từ C# Backend
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        NotificationService.instance.showNotification(
          notification.title ?? 'SmartMoney',
          notification.body ?? '',
        );
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      ApiService.instance.registerDeviceToken(newToken);
    });
  } catch (e) {
    debugPrint("[main] Firebase/FCM chưa được cấu hình hoặc bị lỗi: $e");
  }

  try {
    await initializeDateFormatting('vi_VN', null);
  } catch (e) {
    debugPrint("Error initializing date formatting: $e");
  }

  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint("Error initializing NotificationService: $e");
  }

  runApp(const SmartMoneyApp());
}

class SmartMoneyApp extends StatefulWidget {
  const SmartMoneyApp({super.key});

  @override
  State<SmartMoneyApp> createState() => _SmartMoneyAppState();
}

class _SmartMoneyAppState extends State<SmartMoneyApp> {
  late final Future<Widget> _startScreenFuture = _getStartScreen();

  Future<Widget> _getStartScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;

    if (isLoggedIn) {
      if (biometricEnabled) {
        final localAuth = LocalAuthentication();
        try {
          bool canCheck = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
          if (canCheck) {
            bool authenticated = await localAuth.authenticate(
              localizedReason: 'Xác thực sinh trắc học để vào ứng dụng SmartMoney',
              options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
            );
            if (!authenticated) {
              return _BiometricLockScreen(onRetry: () {
                setState(() {});
              });
            }
          }
        } catch (e) {
          debugPrint("[main] Biometric auth error on start: $e");
        }
      }
      return const MainNavigationScreen();
    }

    return const WelcomeSetupScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản lý chi tiêu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'sans-serif',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
        ),
        useMaterial3: true,
      ),
      home: FutureBuilder<Widget>(
        future: _startScreenFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return const WelcomeSetupScreen();
          }

          return snapshot.data ?? const WelcomeSetupScreen();
        },
      ),
    );
  }
}

class _BiometricLockScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _BiometricLockScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, size: 80, color: AppColors.primary),
              const SizedBox(height: 20),
              const Text(
                'Ứng dụng đang được khóa',
                style: TextStyle(color: AppColors.textDark, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vui lòng xác thực sinh trắc học để mở khóa SmartMoney.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSub, fontSize: 13),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: onRetry,
                icon: const Icon(Icons.lock_open, color: Colors.black),
                label: const Text('Mở khóa', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
