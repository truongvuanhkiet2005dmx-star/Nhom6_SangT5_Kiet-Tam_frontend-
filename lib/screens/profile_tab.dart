import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import '../services/native_listener_bridge.dart';
import 'welcome_setup_screen.dart';
import 'savings_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _isBiometricEnabled = true;
  bool _isReminderEnabled = true;

  String _username = 'Người dùng';
  String _email = '';
  String _language = 'Tiếng Việt';
  String _currency = 'VNĐ (₫)';

  List<String> _customCategories = ['Ăn uống', 'Đi lại', 'Mua sắm', 'Hóa đơn', 'Giải trí', 'Tiền lương', 'Tiền thưởng'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCategories = prefs.getStringList('custom_categories');

    String currentUsername = prefs.getString('username') ?? 'Người dùng';
    String currentEmail = '';

    try {
      final token = await ApiService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final profile = await ApiService.instance.getProfile();
        if (profile.isNotEmpty) {
          if (profile.containsKey('displayName') && profile['displayName'] != null) {
            currentUsername = profile['displayName'].toString();
          } else if (profile.containsKey('email') && profile['email'] != null) {
            currentUsername = profile['email'].toString();
          }
          if (profile.containsKey('email')) {
            currentEmail = profile['email'].toString();
          }
        }
      }
    } catch (e) {
      debugPrint("Get profile backend error: $e");
    }

    if (!mounted) return;

    setState(() {
      _username = currentUsername;
      _email = currentEmail;
      _language = prefs.getString('language') ?? 'Tiếng Việt';
      _currency = prefs.getString('currency') ?? 'VNĐ (₫)';
      _isBiometricEnabled = prefs.getBool('biometricEnabled') ?? true;
      _isReminderEnabled = prefs.getBool('reminderEnabled') ?? true;
      if (savedCategories != null && savedCategories.isNotEmpty) {
        _customCategories = savedCategories;
      }
    });
  }

  Future<void> _saveCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_categories', _customCategories);
  }

  Future<void> _setBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometricEnabled', value);
    if (!mounted) return;
    setState(() {
      _isBiometricEnabled = value;
    });
  }

  Future<void> _setReminder(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminderEnabled', value);
    if (!mounted) return;
    setState(() {
      _isReminderEnabled = value;
    });
  }

  Future<void> _openNotificationPermissionSettings() async {
    try {
      bool isGranted = await NativeListenerBridge.hasNotificationPermission();
      if (!isGranted) {
        await NativeListenerBridge.openNotificationPermissionSettings();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SmartMoney đã có quyền đọc Thông báo App Ngân hàng!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng bật quyền Truy cập Thông báo trong Cài đặt Android.'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await ApiService.instance.deleteDeviceToken(fcmToken);
      }
    } catch (_) {}

    await ApiService.instance.clearToken();

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: AppConstants.googleServerClientId,
      );
      await googleSignIn.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
    await prefs.remove('username');
    await prefs.remove('activeFamilyGroupId');

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const WelcomeSetupScreen(),
      ),
      (route) => false,
    );
  }

  void _showChangePasswordDialog() {
    final currentPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Đổi / Tạo mật khẩu', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu hiện tại (bỏ trống nếu tài khoản OTP)',
                  labelStyle: TextStyle(color: AppColors.textSub, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mới',
                  labelStyle: TextStyle(color: AppColors.textSub),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Xác nhận mật khẩu mới',
                  labelStyle: TextStyle(color: AppColors.textSub),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: AppColors.textSub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final curr = currentPassController.text;
                final next = newPassController.text;
                final conf = confirmPassController.text;

                if (next.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập mật khẩu mới!'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                if (next != conf) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mật khẩu mới không trùng khớp!'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                try {
                  await ApiService.instance.changePassword(
                    currentPassword: curr,
                    newPassword: next,
                  );
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đổi / Tạo mật khẩu thành công!'), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  if (!mounted) return;
                  final errorMsg = e is ApiException ? e.message : 'Lỗi đổi mật khẩu: $e';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Cập nhật', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteAccountDialog() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Xác nhận xóa tài khoản', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CẢNH BÁO: Thao tác này sẽ xóa vĩnh viễn tài khoản của bạn trên hệ thống. Dữ liệu local thuộc tài khoản này sẽ bị xóa.',
                style: TextStyle(color: AppColors.textSub, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu (bỏ trống nếu tài khoản OTP)',
                  labelStyle: TextStyle(color: AppColors.textSub, fontSize: 12),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: AppColors.textSub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                final password = passwordController.text;

                try {
                  await ApiService.instance.deleteAccount(password: password);

                  final prefs = await SharedPreferences.getInstance();
                  final currentUserId = prefs.getInt('userId');

                  if (currentUserId != null) {
                    final db = await DatabaseHelper.instance.database;
                    await db.delete('transactions', where: 'userId = ?', whereArgs: [currentUserId]);
                    await db.delete('wallets', where: 'userId = ?', whereArgs: [currentUserId]);
                    await db.delete('savings_goals', where: 'userId = ?', whereArgs: [currentUserId]);
                    await db.delete('users', where: 'id = ?', whereArgs: [currentUserId]);
                  }

                  await ApiService.instance.clearToken();
                  await prefs.remove('isLoggedIn');
                  await prefs.remove('userId');
                  await prefs.remove('username');
                  await prefs.remove('activeFamilyGroupId');
                  await prefs.remove('displayName');

                  if (!mounted) return;
                  Navigator.pop(context);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const WelcomeSetupScreen()),
                    (route) => false,
                  );
                } catch (e) {
                  if (!mounted) return;
                  final errorMsg = e is ApiException ? e.message : 'Không thể xóa tài khoản: $e';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMsg),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              child: const Text('Xóa tài khoản', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showCategoryManagementSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _CategoryManagementModal(
          categories: _customCategories,
          onCategoryAdded: (newCat) async {
            setState(() {
              _customCategories.add(newCat);
            });
            await _saveCustomCategories();
          },
        );
      },
    );
  }

  void _showFamilyWalletSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _FamilyWalletModal(
          onSaved: () {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã cập nhật Ví Gia Đình thành công!'), backgroundColor: Colors.green),
            );
          },
        );
      },
    );
  }

  void _showLanguageCurrencyDialog() {
    String tempLanguage = _language;
    String tempCurrency = _currency;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              title: const Text('Ngôn ngữ & Tiền tệ', style: TextStyle(color: AppColors.textDark)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: tempLanguage,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.textDark),
                    decoration: const InputDecoration(
                      labelText: 'Ngôn ngữ',
                      labelStyle: TextStyle(color: AppColors.textSub),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Tiếng Việt', child: Text('Tiếng Việt')),
                      DropdownMenuItem(value: 'English', child: Text('English')),
                      DropdownMenuItem(value: '日本語', child: Text('日本語')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        tempLanguage = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: tempCurrency,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.textDark),
                    decoration: const InputDecoration(
                      labelText: 'Tiền tệ',
                      labelStyle: TextStyle(color: AppColors.textSub),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'VNĐ (₫)', child: Text('VNĐ (₫)')),
                      DropdownMenuItem(value: 'USD (\$)', child: Text('USD (\$)')),
                      DropdownMenuItem(value: 'EUR (€)', child: Text('EUR (€)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        tempCurrency = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy', style: TextStyle(color: AppColors.textSub)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('language', tempLanguage);
                    await prefs.setString('currency', tempCurrency);

                    if (!mounted) return;

                    setState(() {
                      _language = tempLanguage;
                      _currency = tempCurrency;
                    });

                    Navigator.pop(context);
                  },
                  child: const Text('Lưu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Tôi', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person, size: 38, color: Colors.black),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          if (_email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _email,
                              style: const TextStyle(
                                color: AppColors.textSub,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '$_language • $_currency',
                            style: const TextStyle(
                              color: AppColors.textSub,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.savings_outlined,
                  title: 'Sổ tiết kiệm / Hũ mục tiêu',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SavingsScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.family_restroom,
                  title: 'Quản lý Ví gia đình',
                  color: Colors.blueAccent,
                  onTap: _showFamilyWalletSheet,
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.category_outlined,
                  title: 'Quản lý danh mục',
                  color: Colors.orangeAccent,
                  onTap: _showCategoryManagementSheet,
                ),
              ]),

              const SizedBox(height: 20),

              _buildMenuCard([
                _buildMenuItem(
                  icon: Icons.lock_reset_outlined,
                  title: 'Đổi / Tạo mật khẩu',
                  color: Colors.indigoAccent,
                  onTap: _showChangePasswordDialog,
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.notifications_active_outlined,
                  title: 'Quyền đọc Thông báo App Ngân hàng',
                  color: Colors.amber,
                  onTap: _openNotificationPermissionSettings,
                ),
                _buildDivider(),
                ListTile(
                  leading: const Icon(Icons.alarm, color: Colors.purpleAccent),
                  title: const Text(
                    'Nhắc nhở nhập chi tiêu',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 14),
                  ),
                  trailing: Switch(
                    value: _isReminderEnabled,
                    activeTrackColor: AppColors.primary,
                    onChanged: _setReminder,
                  ),
                ),
                _buildDivider(),
                ListTile(
                  leading: const Icon(Icons.fingerprint, color: Colors.tealAccent),
                  title: const Text(
                    'Vân tay / FaceID',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 14),
                  ),
                  trailing: Switch(
                    value: _isBiometricEnabled,
                    activeTrackColor: AppColors.primary,
                    onChanged: _setBiometric,
                  ),
                ),
                _buildDivider(),
                _buildMenuItem(
                  icon: Icons.language,
                  title: 'Ngôn ngữ & Tiền tệ',
                  color: Colors.teal,
                  onTap: _showLanguageCurrencyDialog,
                ),
              ]),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _showDeleteAccountDialog,
                icon: const Icon(Icons.delete_forever, size: 20),
                label: const Text('Xóa tài khoản', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900.withValues(alpha: 0.2),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.red.shade700),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900.withValues(alpha: 0.3),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.red.shade800),
                  ),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 14),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSub, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 0.5,
      indent: 52,
      color: AppColors.border,
    );
  }
}

class _CategoryManagementModal extends StatefulWidget {
  final List<String> categories;
  final Function(String) onCategoryAdded;

  const _CategoryManagementModal({
    required this.categories,
    required this.onCategoryAdded,
  });

  @override
  State<_CategoryManagementModal> createState() => _CategoryManagementModalState();
}

class _CategoryManagementModalState extends State<_CategoryManagementModal> {
  final _categoryController = TextEditingController();

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quản lý Danh mục Thu / Chi', style: TextStyle(color: AppColors.textDark, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.categories.map((cat) {
              return Chip(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                label: Text(cat, style: const TextStyle(color: AppColors.textDark)),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _categoryController,
                  style: const TextStyle(color: AppColors.textDark),
                  decoration: const InputDecoration(
                    hintText: 'Nhập danh mục mới...',
                    hintStyle: TextStyle(color: AppColors.textSub),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () {
                  final text = _categoryController.text.trim();
                  if (text.isNotEmpty) {
                    widget.onCategoryAdded(text);
                    setState(() {});
                    _categoryController.clear();
                  }
                },
                child: const Text('Thêm', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyWalletModal extends StatefulWidget {
  final VoidCallback onSaved;

  const _FamilyWalletModal({required this.onSaved});

  @override
  State<_FamilyWalletModal> createState() => _FamilyWalletModalState();
}

class _FamilyWalletModalState extends State<_FamilyWalletModal> {
  final _familyNameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _budgetController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<dynamic> _families = [];
  int? _activeFamilyGroupId;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadFamilyData();
  }

  bool _isOwnerOf(dynamic f) {
    if (f is! Map) return false;
    if (f['isOwner'] == true) return true;
    final members = f['members'];
    if (members is! List || _myUserId == null) return false;
    return members.any((m) =>
      m is Map &&
      m['userId']?.toString() == _myUserId &&
      m['accessRole']?.toString().toLowerCase() == 'owner'
    );
  }

  Future<void> _loadFamilyData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _activeFamilyGroupId = prefs.getInt('activeFamilyGroupId');

    try {
      final token = await ApiService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        try {
          final profile = await ApiService.instance.getProfile();
          if (profile.containsKey('id')) {
            _myUserId = profile['id']?.toString();
          }
        } catch (_) {}

        final list = await ApiService.instance.getFamilies();
        _families = list;

        if (_activeFamilyGroupId != null && _activeFamilyGroupId! > 0) {
          final now = DateTime.now();
          final budgetData = await ApiService.instance.getBudget(
            _activeFamilyGroupId!,
            year: now.year,
            month: now.month,
          );
          if (budgetData.containsKey('monthlyLimit')) {
            _budgetController.text = (budgetData['monthlyLimit'] as num?)?.toInt().toString() ?? '';
          }
        }
      }
    } catch (e) {
      debugPrint("[FamilyWalletModal] Load error: $e");
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _createFamily() async {
    final name = _familyNameController.text.trim();
    final displayName = _displayNameController.text.trim();

    if (name.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final newFamily = await ApiService.instance.createFamily(
        name: name,
        displayName: displayName.isNotEmpty ? displayName : name,
      );

      final familyId = (newFamily['id'] ?? newFamily['familyGroupId']) as int?;
      if (familyId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('activeFamilyGroupId', familyId);
      }

      if (!mounted) return;
      _familyNameController.clear();
      _displayNameController.clear();
      await _loadFamilyData();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is ApiException ? e.message : 'Lỗi tạo nhóm: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _joinFamily() async {
    final inviteCode = _inviteCodeController.text.trim();
    final displayName = _displayNameController.text.trim();
    final relationship = _relationshipController.text.trim();

    if (inviteCode.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final joined = await ApiService.instance.joinFamily(
        inviteCode: inviteCode,
        displayName: displayName.isNotEmpty ? displayName : 'Thành viên',
        relationship: relationship.isNotEmpty ? relationship : 'Người thân',
      );

      final familyId = (joined['id'] ?? joined['familyGroupId']) as int?;
      if (familyId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('activeFamilyGroupId', familyId);
      }

      if (!mounted) return;
      _inviteCodeController.clear();
      await _loadFamilyData();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is ApiException ? e.message : 'Lỗi tham gia nhóm: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _leaveFamily(int familyId) async {
    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.leaveFamily(familyId);
      final prefs = await SharedPreferences.getInstance();
      if (_activeFamilyGroupId == familyId) {
        await prefs.remove('activeFamilyGroupId');
        _activeFamilyGroupId = null;
      }
      if (!mounted) return;
      await _loadFamilyData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã rời nhóm gia đình!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is ApiException ? e.message : 'Không thể rời nhóm: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteMember(int familyId, String memberUserId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Xóa thành viên', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc muốn xóa "$memberName" khỏi nhóm gia đình không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: AppColors.textSub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.deleteFamilyMember(familyId, memberUserId);
      if (!mounted) return;
      await _loadFamilyData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa thành viên $memberName khỏi nhóm!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is ApiException ? e.message : 'Lỗi xóa thành viên: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteFamily(int familyId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Xóa nhóm gia đình', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc muốn giải tán nhóm gia đình này không? Thao tác này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: AppColors.textSub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Giải tán nhóm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.deleteFamily(familyId);
      final prefs = await SharedPreferences.getInstance();
      if (_activeFamilyGroupId == familyId) {
        await prefs.remove('activeFamilyGroupId');
        _activeFamilyGroupId = null;
      }
      if (!mounted) return;
      await _loadFamilyData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa nhóm gia đình!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is ApiException ? e.message : 'Lỗi xóa nhóm: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _switchToPersonalMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeFamilyGroupId');
    if (!mounted) return;
    setState(() => _activeFamilyGroupId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã chuyển về Chế độ Quản lý Cá nhân!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _saveBudget() async {
    if (_activeFamilyGroupId == null || _activeFamilyGroupId! <= 0) return;
    final budgetVal = int.tryParse(_budgetController.text.replaceAll(',', '').replaceAll('.', '').trim()) ?? 0;
    if (budgetVal <= 0) return;

    setState(() => _isSubmitting = true);
    try {
      final now = DateTime.now();
      await ApiService.instance.setBudget(
        _activeFamilyGroupId!,
        year: now.year,
        month: now.month,
        monthlyLimit: budgetVal,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật hạn mức ngân sách gia đình!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e is ApiException ? e.message : 'Lỗi cập nhật ngân sách: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    _displayNameController.dispose();
    _inviteCodeController.dispose();
    _relationshipController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quản lý Nhóm Gia Đình', style: TextStyle(color: AppColors.textDark, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Chia sẻ giao dịch và quản lý hạn mức ngân sách cùng các thành viên gia đình.', style: TextStyle(color: AppColors.textSub, fontSize: 12)),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else ...[
              if (_families.isNotEmpty) ...[
                const Text('Nhóm gia đình của bạn:', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Column(
                  children: _families.map((f) {
                    final fId = (f['id'] ?? f['familyGroupId']) as int?;
                    final fName = f['name']?.toString() ?? 'Nhóm gia đình';
                    final isSelected = fId == _activeFamilyGroupId;
                    final isOwner = _isOwnerOf(f);
                    final members = f['members'] is List ? f['members'] as List : [];

                    return Card(
                      color: isSelected ? AppColors.surface : AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(fName, style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
                            subtitle: Text(f['inviteCode'] != null ? 'Mã mời: ${f['inviteCode']}' : '', style: const TextStyle(color: AppColors.textSub, fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (fId != null) ...[
                                  IconButton(
                                    icon: const Icon(Icons.exit_to_app, color: Colors.orangeAccent, size: 20),
                                    tooltip: 'Rời nhóm',
                                    onPressed: _isSubmitting ? null : () => _leaveFamily(fId),
                                  ),
                                  if (isOwner)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                      tooltip: 'Xóa nhóm',
                                      onPressed: _isSubmitting ? null : () => _deleteFamily(fId),
                                    ),
                                ],
                                const SizedBox(width: 4),
                                isSelected
                                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                                    : ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                  onPressed: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    if (fId != null) {
                                      await prefs.setInt('activeFamilyGroupId', fId);
                                      setState(() => _activeFamilyGroupId = fId);
                                    }
                                  },
                                  child: const Text('Chọn', style: TextStyle(color: Colors.black, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          if (members.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(height: 1, color: AppColors.border),
                                  const SizedBox(height: 8),
                                  const Text('Thành viên nhóm:', style: TextStyle(color: AppColors.textSub, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  ...members.map((m) {
                                    if (m is! Map) return const SizedBox();
                                    final mUserId = m['userId']?.toString() ?? m['id']?.toString();
                                    final mName = m['displayName']?.toString() ?? m['username']?.toString() ?? 'Thành viên';
                                    final mRole = m['accessRole']?.toString() ?? m['role']?.toString() ?? '';
                                    final mIsOwner = mRole.toLowerCase() == 'owner';

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          Icon(
                                            mIsOwner ? Icons.star : Icons.person_outline,
                                            size: 16,
                                            color: mIsOwner ? Colors.amber : AppColors.textSub,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '$mName ${mIsOwner ? "(Chủ nhóm)" : ""}',
                                              style: TextStyle(
                                                color: AppColors.textDark,
                                                fontSize: 13,
                                                fontWeight: mIsOwner ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                          if (isOwner && !mIsOwner && fId != null && mUserId != null && mUserId.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                                              tooltip: 'Xóa khỏi nhóm',
                                              onPressed: _isSubmitting ? null : () => _deleteMember(fId, mUserId, mName),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (_activeFamilyGroupId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _switchToPersonalMode,
                        icon: const Icon(Icons.person, size: 16, color: AppColors.primary),
                        label: const Text('Bỏ chọn nhóm (Về chế độ Cá nhân)', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              if (_activeFamilyGroupId != null && _activeFamilyGroupId! > 0) ...[
                const Text('Hạn mức Ngân sách Nhóm Tháng này:', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final activeGroup = _families.firstWhere(
                      (f) => (f['id'] ?? f['familyGroupId']) == _activeFamilyGroupId,
                      orElse: () => null,
                    );
                    final isActiveOwner = activeGroup != null && _isOwnerOf(activeGroup);

                    if (!isActiveOwner) {
                      return const Text(
                        'Chỉ chủ nhóm mới đặt được hạn mức.',
                        style: TextStyle(color: AppColors.textSub, fontSize: 12, fontStyle: FontStyle.italic),
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppColors.textDark),
                            decoration: const InputDecoration(
                              hintText: 'Nhập hạn mức VNĐ (Ví dụ: 5000000)',
                              hintStyle: TextStyle(color: AppColors.textSub),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          onPressed: _isSubmitting ? null : _saveBudget,
                          child: const Text('Lưu Hạn Mức', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 32, color: AppColors.border),
              ],

              const Text('Tạo Nhóm Gia Đình Mới:', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _familyNameController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Tên nhóm gia đình (Ví dụ: Gia đình Nguyễn)',
                  labelStyle: TextStyle(color: AppColors.textSub),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: _isSubmitting ? null : _createFamily,
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: const Text('Tạo nhóm mới', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),

              const Divider(height: 32, color: AppColors.border),

              const Text('Hoặc Tham Gia Nhóm Bằng Mã Mời:', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _inviteCodeController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Mã mời tham gia nhóm',
                  labelStyle: TextStyle(color: AppColors.textSub),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primary)),
                  onPressed: _isSubmitting ? null : _joinFamily,
                  icon: const Icon(Icons.group_add, color: AppColors.primary),
                  label: const Text('Tham gia bằng Mã Mời', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
