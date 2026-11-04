import 'dart:async';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const SmartMoneyApp());

  // Non-blocking background initialization after runApp to ensure instant first frame render
  unawaited(Future.microtask(() async {
    final swMain = Stopwatch()..start();

    try {
      await Firebase.initializeApp();
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
      debugPrint("[main] Firebase/FCM background init warning: $e");
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

    swMain.stop();
    debugPrint("[Performance] Background main() setup completed in ${swMain.elapsedMilliseconds}ms");
  }));
}

class SmartMoneyApp extends StatefulWidget {
  const SmartMoneyApp({super.key});

  @override
  State<SmartMoneyApp> createState() => _SmartMoneyAppState();
}

class _SmartMoneyAppState extends State<SmartMoneyApp> {
  late final Future<Widget> _startScreenFuture = _getStartScreen();

  Future<Widget> _getStartScreen() async {
    final swStart = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    swStart.stop();
    debugPrint("[Performance] _getStartScreen completed in ${swStart.elapsedMilliseconds}ms");

    if (isLoggedIn) {
      return const _BiometricGuard(child: MainNavigationScreen());
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

class _BiometricGuard extends StatefulWidget {
  final Widget child;

  const _BiometricGuard({required this.child});

  @override
  State<_BiometricGuard> createState() => _BiometricGuardState();
}

class _BiometricGuardState extends State<_BiometricGuard> {
  bool _isLocked = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndAuthenticate();
    });
  }

  Future<void> _checkAndAuthenticate() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;

    if (!biometricEnabled) return;

    setState(() {
      _isLocked = true;
    });

    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final localAuth = LocalAuthentication();
      bool canCheck = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();

      if (canCheck) {
        bool authenticated = await localAuth.authenticate(
          localizedReason: 'Xác thực sinh trắc học để vào ứng dụng SmartMoney',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );

        if (authenticated && mounted) {
          setState(() {
            _isLocked = false;
          });
        }
      } else if (mounted) {
        // Nếu thiết bị không hỗ trợ sinh trắc học thì tự mở khóa
        setState(() {
          _isLocked = false;
        });
      }
    } catch (e) {
      debugPrint("[main] Post-frame biometric auth error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return _BiometricLockScreen(
        isAuthenticating: _isAuthenticating,
        onRetry: _authenticate,
      );
    }

    return widget.child;
  }
}

class _BiometricLockScreen extends StatelessWidget {
  final bool isAuthenticating;
  final VoidCallback onRetry;

  const _BiometricLockScreen({
    required this.isAuthenticating,
    required this.onRetry,
  });

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
                onPressed: isAuthenticating ? null : onRetry,
                icon: isAuthenticating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open, color: Colors.black),
                label: const Text('Mở khóa', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
