import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'main_navigation_screen.dart';

class LoginScreen extends StatefulWidget {
  final String language;
  final String currency;

  const LoginScreen({
    super.key,
    required this.language,
    required this.currency,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  int _step = 1; // 1: Nhập Email, 2: Nhập mã OTP
  bool _isLoading = false;
  int _timerSeconds = 60;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timerSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_timerSeconds > 1) {
        setState(() => _timerSeconds--);
      } else {
        _timer?.cancel();
        setState(() => _timerSeconds = 0);
      }
    });
  }

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.instance.registerDeviceToken(token);
      }
    } catch (e) {
      debugPrint("[LoginScreen] FCM token registration warning: $e");
    }
  }

  Future<void> _handleRequestOtp() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnackBar('Vui lòng nhập Email hợp lệ!', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ApiService.instance.requestOtp(email: email);

      if (!mounted) return;

      _startTimer();
      setState(() {
        _step = 2;
        _isLoading = false;
      });

      _showSnackBar('Mã OTP đã được gửi tới email $email', Colors.green);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      final currentServerUrl = await ApiService.instance.baseUrl;
      final errorStr = e.toString();
      String userFriendlyMessage = e is ApiException ? e.message : 'Không thể gửi mã OTP: $e';
      if (errorStr.contains('Timeout') || errorStr.contains('SocketException') || errorStr.contains('refused')) {
        userFriendlyMessage = 'Không thể kết nối Server ($currentServerUrl). Hãy chạm nút 🌐 ở góc trên để chỉnh IP máy tính hoặc ngrok URL!';
      }
      _showSnackBar(userFriendlyMessage, Colors.red);
    }
  }

  Future<void> _handleVerifyOtp() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      _showSnackBar('Vui lòng nhập mã OTP!', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final responseData = await ApiService.instance.verifyOtp(email: email, code: code);

      String? displayName;
      if (responseData.containsKey('user') && responseData['user'] is Map) {
        final uMap = responseData['user'] as Map;
        displayName = uMap['displayName']?.toString();
      }

      final sqliteUser = await DatabaseHelper.instance.findOrCreateUserByEmail(
        email: email,
        displayName: displayName,
      );

      final userId = sqliteUser['id'] as int;
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('isLoggedIn', true);
      await prefs.setInt('userId', userId);
      await prefs.setString('username', sqliteUser['username'] as String);
      await prefs.setString('language', widget.language);
      await prefs.setString('currency', widget.currency);

      if (displayName != null && displayName.isNotEmpty) {
        await prefs.setString('displayName', displayName);
      }

      await _registerFcmToken();
      SyncService.instance.pullAndSyncFromBackend(userId);

      if (!mounted) return;

      setState(() => _isLoading = false);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      final errorMsg = e is ApiException ? e.message : 'Xác minh OTP thất bại: $e';
      _showSnackBar(errorMsg, Colors.red);
    }
  }

  Future<void> _showServerConfigDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBase = await ApiService.instance.baseUrl;
    final controller = TextEditingController(text: currentBase);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Row(
            children: [
              Icon(Icons.dns_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Cấu hình Server Backend', style: TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập địa chỉ Backend API (kết thúc bằng /api).\n\n• Điện thoại thật Wi-Fi: http://192.168.x.x:5087/api\n• Android Emulator: http://10.0.2.2:5087/api\n• Ngrok Public URL: https://...ngrok-free.dev/api',
                style: TextStyle(color: AppColors.textSub, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: AppColors.textDark, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ Backend URL',
                  labelStyle: TextStyle(color: AppColors.textSub),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.remove('custom_backend_url');
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _showSnackBar('Đã khôi phục địa chỉ Server mặc định!', Colors.green);
              },
              child: const Text('Mặc định', style: TextStyle(color: AppColors.textSub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final url = controller.text.trim();
                if (url.isNotEmpty) {
                  await prefs.setString('custom_backend_url', url);
                } else {
                  await prefs.remove('custom_backend_url');
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _showSnackBar('Đã lưu địa chỉ Server mới!', Colors.green);
              },
              child: const Text('Lưu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textDark,
            size: 20,
          ),
          onPressed: () {
            if (_step == 2) {
              setState(() => _step = 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined, color: AppColors.primary),
            tooltip: 'Đổi địa chỉ Server Backend',
            onPressed: _showServerConfigDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              Text(
                _step == 1 ? 'Đăng Nhập Email OTP' : 'Nhập Mã OTP',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Đơn vị: ${widget.currency} • Ngôn ngữ: ${widget.language}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub,
                ),
              ),

              const SizedBox(height: 28),

              if (_step == 1) ...[
                const Text(
                  'Địa chỉ Email / Gmail',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textDark),
                  decoration: InputDecoration(
                    hintText: 'Nhập email của bạn (ví dụ: user@gmail.com)...',
                    hintStyle: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: AppColors.primary,
                    ),
                    filled: true,
                    fillColor: AppColors.card,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRequestOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Gửi Mã OTP',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.mark_email_read_outlined, size: 40, color: AppColors.primary),
                      const SizedBox(height: 8),
                      Text(
                        'Mã xác thực đã được gửi tới:',
                        style: const TextStyle(color: AppColors.textSub, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _emailController.text.trim(),
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Nhập mã OTP (6 chữ số)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    letterSpacing: 8,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '123456',
                    hintStyle: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 22,
                      letterSpacing: 8,
                    ),
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.card,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Xác Minh & Đăng Nhập',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() => _step = 1);
                      },
                      child: const Text(
                        'Đổi Email khác',
                        style: TextStyle(color: AppColors.textSub, fontSize: 13),
                      ),
                    ),

                    TextButton(
                      onPressed: (_timerSeconds > 0 || _isLoading)
                          ? null
                          : _handleRequestOtp,
                      child: Text(
                        _timerSeconds > 0
                            ? 'Gửi lại mã (${_timerSeconds}s)'
                            : 'Gửi lại mã OTP',
                        style: TextStyle(
                          color: _timerSeconds > 0 ? AppColors.textSub : AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
