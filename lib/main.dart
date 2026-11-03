import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/app_colors.dart';
import 'screens/welcome_setup_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("[main] Firebase chưa được cấu hình google-services.json hoặc bị lỗi: $e");
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
  // F13 Fix: Lưu trữ _startScreenFuture trong State tránh flash loading mỗi khi rebuild widget
  late final Future<Widget> _startScreenFuture = _getStartScreen();

  Future<Widget> _getStartScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
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