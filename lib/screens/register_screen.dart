import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'initial_wallet_setup_screen.dart';
import 'main_navigation_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.instance.registerDeviceToken(token);
      }
    } catch (e) {
      debugPrint("[RegisterScreen] FCM token error: $e");
    }
  }

  Future<void> _handleRegister() async {
    final email = _emailController.text.trim();
    final displayName = _displayNameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showSnackBar('Vui lòng nhập Địa chỉ Email hợp lệ!', Colors.orange);
      return;
    }

    if (displayName.isEmpty) {
      _showSnackBar('Vui lòng nhập Tên hiển thị!', Colors.orange);
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Mật khẩu phải có ít nhất 6 ký tự!', Colors.orange);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar('Mật khẩu xác nhận không khớp!', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Gọi Backend API POST /api/auth/register (email, password, displayName)
      try {
        await ApiService.instance.register(
          email: email,
          password: password,
          displayName: displayName,
        );
      } catch (be) {
        debugPrint("[RegisterScreen] Backend register error: $be");
        if (be is ApiException) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showSnackBar(be.message, Colors.red);
          return;
        }
      }

      // 2. Thử tạo tài khoản Firebase Auth
      User? fbUser;
      try {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        fbUser = cred.user;
      } catch (_) {}

      // 3. Tạo tài khoản CSDL SQLite cục bộ
      final userId = await DatabaseHelper.instance.registerUser(email, password);

      if (fbUser != null && fbUser.email != null) {
        await DatabaseHelper.instance.findOrCreateUserByFirebaseUid(
          firebaseUid: fbUser.uid,
          email: fbUser.email!,
          displayName: displayName,
        );
      } else {
        await DatabaseHelper.instance.findOrCreateUserByEmail(
          email: email,
          displayName: displayName,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', userId);
      await prefs.setString('username', email);
      await prefs.setString('displayName', displayName);
      await prefs.setBool('isLoggedIn', true);

      await _registerFcmToken();
      SyncService.instance.syncAllPendingTransactions(userId);

      if (!mounted) return;

      setState(() => _isLoading = false);

      _showSnackBar('Đăng ký tài khoản thành công! Bắt đầu thiết lập ví.', Colors.green);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => InitialWalletSetupScreen(userId: userId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      final isDuplicate = e.toString().toLowerCase().contains('unique');
      _showSnackBar(
        isDuplicate
            ? 'Địa chỉ Email này đã được sử dụng!'
            : 'Đăng ký không thành công: $e',
        Colors.red,
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: AppConstants.googleServerClientId,
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null || user.email == null || user.email!.isEmpty) {
        throw Exception("Không thể lấy thông tin Email từ Google.");
      }

      final firebaseIdToken = await user.getIdToken();
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw Exception("Không thể lấy Firebase ID Token.");
      }
      await ApiService.instance.loginWithGoogle(idToken: firebaseIdToken);

      final sqliteUser = await DatabaseHelper.instance.findOrCreateUserByFirebaseUid(
        firebaseUid: user.uid,
        email: user.email!,
        displayName: user.displayName ?? user.email!,
      );

      final userId = sqliteUser['id'] as int;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setInt('userId', userId);
      await prefs.setString('username', sqliteUser['username'] as String);

      await _registerFcmToken();
      SyncService.instance.syncAllPendingTransactions(userId);

      if (!mounted) return;

      setState(() => _isLoading = false);

      final userWallets = await DatabaseHelper.instance.getWallets(userId);
      final hasCashWallet = userWallets.any((w) => w['type'] == 'cash');

      if (mounted) {
        if (!hasCashWallet || userWallets.length <= 1) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (ctx) => InitialWalletSetupScreen(userId: userId)),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (ctx) => const MainNavigationScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      _showSnackBar('Đăng ký bằng Google chưa thành công: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
          onPressed: () => Navigator.pop(context),
        ),
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
              const Text(
                'Tạo Tài Khoản Mới',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bắt đầu hành trình quản lý tài chính của bạn',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSub,
                ),
              ),
              const SizedBox(height: 28),

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
                decoration: _inputDecoration(
                  'Nhập email (ví dụ: user@gmail.com)...',
                  Icons.email_outlined,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Tên hiển thị (Họ và Tên)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _displayNameController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: _inputDecoration(
                  'Nhập tên của bạn (ví dụ: Nguyễn Văn A)...',
                  Icons.person_outline,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Mật khẩu',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: AppColors.textDark),
                decoration: _passwordDecoration(
                  'Nhập mật khẩu (tối thiểu 6 ký tự)...',
                  _obscurePassword,
                  () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Xác nhận mật khẩu',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                style: const TextStyle(color: AppColors.textDark),
                decoration: _passwordDecoration(
                  'Nhập lại mật khẩu...',
                  _obscureConfirm,
                  () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                ),
              ),

              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
                        'Đăng Ký Tài Khoản',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.g_mobiledata, color: Colors.redAccent, size: 28),
                label: const Text(
                  'Đăng ký bằng Google',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textSub,
        fontSize: 14,
      ),
      prefixIcon: Icon(
        icon,
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
    );
  }

  InputDecoration _passwordDecoration(
    String hint,
    bool isObscure,
    VoidCallback onToggle,
  ) {
    return _inputDecoration(
      hint,
      Icons.lock_outline,
    ).copyWith(
      suffixIcon: IconButton(
        icon: Icon(
          isObscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: AppColors.primary,
        ),
        onPressed: onToggle,
      ),
    );
  }
}
