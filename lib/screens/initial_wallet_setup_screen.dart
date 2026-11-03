import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';
import 'main_navigation_screen.dart';

class InitialWalletSetupScreen extends StatefulWidget {
  final int userId;

  const InitialWalletSetupScreen({
    super.key,
    required this.userId,
  });

  @override
  State<InitialWalletSetupScreen> createState() =>
      _InitialWalletSetupScreenState();
}

class _InitialWalletSetupScreenState
    extends State<InitialWalletSetupScreen> {
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _bankController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();

  String _selectedBank = 'VietinBank';
  bool _isLoading = false;

  final List<String> _popularBanks = [
    'VietinBank',
    'MB Bank',
    'Vietcombank',
    'Techcombank',
    'BIDV',
    'Agribank',
    'VPBank',
    'TPBank',
    'Ví MoMo',
    'Tài khoản khác',
  ];

  int _parseMoney(String value) {
    final cleaned = value
        .replaceAll('.', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');

    return int.tryParse(cleaned) ?? 0;
  }

  Future<void> _saveWallets() async {
    final cash = _parseMoney(_cashController.text);
    final bank = _parseMoney(_bankController.text);
    final accNum = _accountNumberController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      final existingWallets = await DatabaseHelper.instance.getWallets(widget.userId);

      // F5/F13 Fix: Cập nhật ví hiện có, tự động giữ lại STK cũ nếu ô nhập mới để trống
      final existingCash = existingWallets.where((w) => w['type'] == 'cash').firstOrNull;
      if (existingCash != null) {
        await DatabaseHelper.instance.updateWalletBalance(existingCash['id'] as int, cash);
      } else {
        await DatabaseHelper.instance.insertWallet({
          'userId': widget.userId,
          'name': 'Ví tiền mặt',
          'balance': cash,
          'type': 'cash',
        });
      }

      final existingBank = existingWallets.where((w) => w['type'] == 'bank').firstOrNull;
      if (existingBank != null) {
        final currentAccNum = existingBank['accountNumber']?.toString() ?? '';
        final finalAccNum = accNum.isNotEmpty ? accNum : currentAccNum;
        await DatabaseHelper.instance.updateWallet(existingBank['id'] as int, {
          'name': _selectedBank,
          'balance': bank,
          'accountNumber': finalAccNum,
        });
      } else {
        await DatabaseHelper.instance.insertWallet({
          'userId': widget.userId,
          'name': _selectedBank,
          'balance': bank,
          'type': 'bank',
          'accountNumber': accNum.isEmpty ? null : accNum,
        });
      }

      await SyncService.instance.syncUnsyncedWallets(widget.userId);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // F3 Fix: Xóa bỏ hoàn toàn màn hình Login/Welcome khỏi back-stack chuyển tiếp mượt mà
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const MainNavigationScreen(),
        ),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể lưu số dư. Vui lòng thử lại!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _bankController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
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
                'Thiết lập số dư ban đầu',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Chọn ngân hàng sử dụng chính và khai báo số dư để ứng dụng bắt đầu tính toán và tự động đồng bộ SMS.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSub,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Tiền mặt trong ví',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _cashController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(color: AppColors.textSub),
                  suffixText: 'VNĐ',
                  suffixStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  prefixIcon: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.greenAccent,
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
                'Ngân hàng / Ví điện tử chính',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                initialValue: _selectedBank,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.account_balance,
                    color: AppColors.primary,
                  ),
                  filled: true,
                  fillColor: AppColors.card,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                items: _popularBanks.map((bank) {
                  return DropdownMenuItem(
                    value: bank,
                    child: Text(bank, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedBank = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 16),

              const Text(
                'Số tài khoản / STK (Để đồng bộ SMS tự động)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _accountNumberController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Ví dụ: 1012345678',
                  hintStyle: const TextStyle(color: AppColors.textSub),
                  prefixIcon: const Icon(
                    Icons.credit_card,
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

              const SizedBox(height: 16),

              const Text(
                'Số dư tài khoản ngân hàng',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _bankController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: const TextStyle(color: AppColors.textSub),
                  suffixText: 'VNĐ',
                  suffixStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  prefixIcon: const Icon(
                    Icons.monetization_on_outlined,
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

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _saveWallets,
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
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2,
                  ),
                )
                    : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Hoàn tất & Bắt đầu',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}