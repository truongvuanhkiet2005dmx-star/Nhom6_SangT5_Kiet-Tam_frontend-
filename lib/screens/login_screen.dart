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
import 'register_screen.dart';
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
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.instance.registerDeviceToken(token);
      }
    } catch (e) {
      debugPrint("[LoginScreen] Could not register FCM token: $e");
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      _showSnackBar(
        'Vui lòng nhập đầy đủ thông tin!',
        Colors.orange,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic>? backendAuthData;

      // 1. Gọi backend API POST /auth/login
      try {
        backendAuthData = await ApiService.instance.login(
          email: username,
          password: password,
        );
      } catch (backendError) {
        debugPrint("[LoginScreen] Backend login error: $backendError");
        // Nếu backend trả lỗi sai mật khẩu hoặc tài khoản không tồn tại, báo lỗi trực tiếp
        if (backendError is ApiException && (backendError.statusCode == 400 || backendError.statusCode == 401)) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showSnackBar(backendError.message, Colors.red);
          return;
        }
      }

      // 2. Thử xác thực Firebase Auth nếu là email chuẩn
      User? fbUser;
      if (username.contains('@')) {
        try {
          final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: username,
            password: password,
          );
          fbUser = cred.user;
        } catch (_) {}
      }

      // 3. Tìm hoặc tạo SQLite User cục bộ
      var user = await DatabaseHelper.instance.loginUser(username, password);

      if (user == null) {
        if (fbUser != null && fbUser.email != null) {
          user = await DatabaseHelper.instance.findOrCreateUserByFirebaseUid(
            firebaseUid: fbUser.uid,
            email: fbUser.email!,
            displayName: fbUser.displayName,
          );
        } else {
          // Tạo user mới trong SQLite local dựa trên email từ backend
          final newUserId = await DatabaseHelper.instance.registerUser(username, password);
          user = await DatabaseHelper.instance.getUserById(newUserId);
        }
      }

      if (!mounted) return;

      if (user == null) {
        setState(() => _isLoading = false);
        _showSnackBar('Tên đăng nhập hoặc mật khẩu không đúng!', Colors.red);
        return;
      }

      final userId = user['id'] as int;
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('isLoggedIn', true);
      await prefs.setInt('userId', userId);
      await prefs.setString('username', user['username'] as String);
      await prefs.setString('language', widget.language);
      await prefs.setString('currency', widget.currency);

      if (backendAuthData != null && backendAuthData.containsKey('user')) {
        final backendUser = backendAuthData['user'];
        if (backendUser is Map && backendUser.containsKey('displayName')) {
          await prefs.setString('displayName', backendUser['displayName'].toString());
        }
      }

      // Đăng ký FCM token sau khi có token
      await _registerFcmToken();

      // Trigger đồng bộ ví & giao dịch
      SyncService.instance.syncAllPendingTransactions(userId);

      setState(() => _isLoading = false);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      _showSnackBar('Có lỗi xảy ra khi đăng nhập: $e', Colors.red);
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

      // Đổi Firebase ID Token lấy JWT backend qua /auth/google
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
      await prefs.setString('language', widget.language);
      await prefs.setString('currency', widget.currency);

      await _registerFcmToken();
      SyncService.instance.syncAllPendingTransactions(userId);

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
      _showSnackBar('Đăng nhập Google không thành công: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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
              const SizedBox(height: 10),

              const Text(
                'Đăng Nhập',
                style: TextStyle(
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

              const Text(
                'Tên đăng nhập / Email',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),

              const SizedBox(height: 8),

              TextField(
                controller: _usernameController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Nhập tên hoặc email...',
                  hintStyle: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.person_outline,
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
                decoration: InputDecoration(
                  hintText: 'Nhập mật khẩu...',
                  hintStyle: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: AppColors.primary,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
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

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final email = _usernameController.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      _showSnackBar('Vui lòng nhập Email vào ô bên trên để khôi phục!', Colors.orange);
                      return;
                    }
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      _showSnackBar('Đã gửi email khôi phục mật khẩu tới $email!', Colors.green);
                    } catch (e) {
                      _showSnackBar('Không thể gửi email khôi phục mật khẩu!', Colors.red);
                    }
                  },
                  child: const Text(
                    'Quên mật khẩu?',
                    style: TextStyle(
                      color: AppColors.textSub,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
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
                  'Đăng nhập',
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
                  'Đăng nhập bằng Google',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Chưa có tài khoản? ',
                    style: TextStyle(
                      color: AppColors.textSub,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Đăng ký ngay',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
