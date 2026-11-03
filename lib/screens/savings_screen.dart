import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';
import 'welcome_setup_screen.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  int? _userId;
  List<Map<String, dynamic>> _goals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavingsGoals();
  }

  Future<void> _loadSavingsGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (userId == null) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeSetupScreen()),
            (route) => false,
      );
      return;
    }

    final goals = await DatabaseHelper.instance.getSavingsGoals(userId);

    if (!mounted) return;

    setState(() {
      _userId = userId;
      _goals = goals;
      _isLoading = false;
    });
  }

  String _formatMoney(int amount) {
    final text = amount.toString();
    String result = '';
    for (int i = text.length - 1, count = 1; i >= 0; i--, count++) {
      result = text[i] + result;
      if (count % 3 == 0 && i != 0) {
        result = ',$result';
      }
    }
    return '$result đ';
  }

  Future<void> _showAddGoalDialog() async {
    if (_userId == null) return;

    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final initialController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Thêm Hũ / Mục tiêu tiết kiệm', style: TextStyle(color: AppColors.textDark)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Tên mục tiêu',
                  labelStyle: TextStyle(color: AppColors.textSub),
                  hintText: 'Ví dụ: Mua iPhone 16, Mua Xe máy',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Số tiền mục tiêu',
                  labelStyle: TextStyle(color: AppColors.textSub),
                  suffixText: 'VNĐ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: initialController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Số tiền ban đầu (nếu có)',
                  labelStyle: TextStyle(color: AppColors.textSub),
                  suffixText: 'VNĐ',
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
                final name = nameController.text.trim();
                final target = int.tryParse(targetController.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;
                final initial = int.tryParse(initialController.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;

                if (name.isEmpty || target <= 0) return;

                await DatabaseHelper.instance.insertSavingsGoal({
                  'userId': _userId,
                  'name': name,
                  'targetAmount': target,
                  'currentAmount': initial,
                  'date': DateTime.now().toIso8601String(),
                });

                if (!mounted) return;
                Navigator.pop(context);
                _loadSavingsGoals();
              },
              child: const Text('Tạo hũ tiết kiệm', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    targetController.dispose();
    initialController.dispose();
  }

  Future<void> _depositMoneyDialog(Map<String, dynamic> goal) async {
    if (_userId == null) return;
    final goalId = goal['id'] as int;
    final currentAmount = goal['currentAmount'] as int;
    final amountController = TextEditingController();

    final wallets = await DatabaseHelper.instance.getWallets(_userId!);
    if (wallets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có ví tài khoản để trừ tiền!'), backgroundColor: Colors.orange),
      );
      return;
    }

    int selectedWalletId = wallets.first['id'] as int;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              title: Text('Nạp tiền vào: ${goal['name']}', style: const TextStyle(color: AppColors.textDark)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selectedWalletId,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.textDark),
                    decoration: const InputDecoration(
                      labelText: 'Chọn ví trừ tiền',
                      labelStyle: TextStyle(color: AppColors.textSub),
                    ),
                    items: wallets.map((w) {
                      return DropdownMenuItem<int>(
                        value: w['id'] as int,
                        child: Text('${w['name']} (${w['balance']} đ)', style: const TextStyle(color: AppColors.textDark)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedWalletId = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: const TextStyle(color: AppColors.textDark),
                    decoration: const InputDecoration(
                      labelText: 'Số tiền nạp thêm',
                      labelStyle: TextStyle(color: AppColors.textSub),
                      suffixText: 'VNĐ',
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
                    final addAmt = int.tryParse(amountController.text.replaceAll(',', '').replaceAll('.', '')) ?? 0;
                    if (addAmt <= 0) return;

                    // F14 & F4 Fix: Kiểm tra số dư ví trước khi trừ tiền nạp hũ
                    final wallet = await DatabaseHelper.instance.getWalletById(selectedWalletId);
                    if (wallet != null) {
                      final currentWalletBal = (wallet['balance'] as num?)?.toInt() ?? 0;
                      if (currentWalletBal < addAmt) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Số dư ví không đủ để nạp vào hũ tiết kiệm!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      await DatabaseHelper.instance.updateWalletBalance(selectedWalletId, currentWalletBal - addAmt);

                      await DatabaseHelper.instance.insertTransaction({
                        'userId': _userId,
                        'walletId': selectedWalletId,
                        'amount': addAmt,
                        'type': 'expense',
                        'isExpense': 1,
                        'categoryName': 'Tiết kiệm',
                        'date': DateTime.now().toIso8601String(),
                        'note': 'Nạp vào hũ: ${goal['name']}',
                      });
                    }

                    final newAmount = currentAmount + addAmt;
                    await DatabaseHelper.instance.updateSavingsGoalAmount(goalId, newAmount);

                    if (!mounted) return;
                    Navigator.pop(context);
                    _loadSavingsGoals();
                  },
                  child: const Text('Nạp tiền', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int totalSavings = 0;
    for (var g in _goals) {
      totalSavings += (g['currentAmount'] as int? ?? 0);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sổ tiết kiệm & Hũ mục tiêu', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TỔNG TIỀN ĐÃ TIẾT KIỆM',
                    style: TextStyle(color: AppColors.textSub, fontSize: 12, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatMoney(totalSavings),
                    style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Danh sách mục tiêu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                ),
                TextButton.icon(
                  onPressed: _showAddGoalDialog,
                  icon: const Icon(Icons.add_circle, color: AppColors.primary),
                  label: const Text('Tạo mục tiêu', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_goals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Chưa có hũ tiết kiệm nào. Hãy tạo mục tiêu đầu tiên!',
                    style: TextStyle(color: AppColors.textSub, fontSize: 14),
                  ),
                ),
              )
            else
              ..._goals.map((goal) {
                final current = goal['currentAmount'] as int? ?? 0;
                final target = goal['targetAmount'] as int? ?? 1;
                final percent = (current / target).clamp(0.0, 1.0);
                final goalId = goal['id'] as int;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: AppColors.surface,
                                child: Icon(Icons.savings_outlined, color: AppColors.primary),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                goal['name'].toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              await DatabaseHelper.instance.deleteSavingsGoal(goalId);
                              _loadSavingsGoals();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Đã tích lũy: ${_formatMoney(current)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
                          Text('Mục tiêu: ${_formatMoney(target)}', style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 8,
                          backgroundColor: AppColors.surface,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _depositMoneyDialog(goal),
                          icon: const Icon(Icons.add, color: Colors.black),
                          label: const Text('Nạp thêm tiền', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}