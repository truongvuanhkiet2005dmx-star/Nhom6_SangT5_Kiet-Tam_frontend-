import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';
import '../services/auto_transaction_service.dart';
import '../services/native_listener_bridge.dart';
import '../services/personal_debt_parser.dart';

class SmsListScreen extends StatefulWidget {
  const SmsListScreen({super.key});

  @override
  State<SmsListScreen> createState() => _SmsListScreenState();
}

class _SmsListScreenState extends State<SmsListScreen> {
  List<Map<String, String>> _messages = [];
  bool _isLoading = true;
  final Set<String> _confirmedDedupKeys = {};
  List<Map<String, dynamic>> _userWallets = [];
  int? _userId;

  final List<Map<String, String>> _sampleBankNotifications = [
    {
      'bank': 'VietinBank iPay',
      'title': 'Mẫu mô phỏng biến động số dư',
      'body': 'VietinBank:08/10/2026 01:37\nTK:104880072280\nGD:-10,000 VND\nSDC:1,378,944 VND\nND:MoMo CASHIN 0355680504 150574678098 2009',
      'stk': '104880072280',
      'amount': '-10,000 đ',
    },
    {
      'bank': 'MBBank',
      'title': 'Mẫu mô phỏng tài khoản MB',
      'body': 'MBBank: TK 0123456789 GD:-50,000VND SD:2,100,000VND luc 12:30. ND: Thanh toan qua QR',
      'stk': '0123456789',
      'amount': '-50,000 đ',
    },
    {
      'bank': 'Vietcombank (VCB)',
      'title': 'Mẫu mô phỏng VCB Digibank',
      'body': 'VCB: SD TK 0071001234567 -20,000 VND luc 15:10. So du 5,200,000 VND. ND: Mua hang Shopee',
      'stk': '0071001234567',
      'amount': '-20,000 đ',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSmsMessages();
  }

  Future<void> _loadSmsMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      _userId = userId;

      if (userId != null) {
        final db = await DatabaseHelper.instance.database;
        final wallets = await DatabaseHelper.instance.getWallets(userId);
        _userWallets = wallets;

        // Batch query SQLite for confirmed debt keys
        final confirmedRows = await db.query(
          'transactions',
          columns: ['note'],
          where: 'userId = ? AND note LIKE ?',
          whereArgs: [userId, '%DEBT_%'],
        );

        for (final row in confirmedRows) {
          final noteStr = row['note']?.toString() ?? '';
          final keyMatch = RegExp(r'DEBT_\d+').firstMatch(noteStr);
          if (keyMatch != null) {
            _confirmedDedupKeys.add(keyMatch.group(0)!);
          }
        }
      }

      List<Map<String, String>> messages = await NativeListenerBridge.getInboxSms();

      if (!mounted) return;

      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("[SmsListScreen] Error loading inbox SMS: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSampleSyncDialog(String bankName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đây là thẻ mẫu mô phỏng cho $bankName. Để đồng bộ thông báo thật, hãy dùng nút Sync trên Trang chủ!'),
        backgroundColor: Colors.amber.shade900,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _showConfirmDebtDialog(ParsedPersonalDebtMessage debt) async {
    if (_userId == null || _userWallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn chưa tạo ví tài khoản. Vui lòng tạo ví trước khi xác nhận!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int selectedWalletId = _userWallets.first['id'] as int;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Xác Nhận Ghi Nhận Nợ Cá Nhân',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Số tiền: ${_formatMoney(debt.amount)} đ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: debt.isExpense ? Colors.redAccent : Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Đề xuất: ${debt.suggestedCategory} (${debt.isExpense ? "Chi tiêu" : "Thu nhập"})',
                          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nội dung: ${debt.note}',
                          style: const TextStyle(color: AppColors.textDark, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Chọn Ví Cần Ghi Nhận:',
                    style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedWalletId,
                    dropdownColor: AppColors.card,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold),
                    items: _userWallets.map((w) {
                      final name = w['name'].toString();
                      final bal = w['balance'] as int;
                      return DropdownMenuItem<int>(
                        value: w['id'] as int,
                        child: Text('$name (${_formatMoney(bal)} đ)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          selectedWalletId = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Bỏ qua', style: TextStyle(color: AppColors.textSub)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            await AutoTransactionService.instance.confirmPersonalDebtTransaction(
                              debt,
                              walletId: selectedWalletId,
                            );
                            setState(() {
                              _confirmedDedupKeys.add(debt.dedupKey);
                            });
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã xác nhận & lưu giao dịch vào ví thành công!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          child: const Text(
                            'Lưu & Xác Nhận',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Lịch sử Thông báo & SMS', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSub,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Thông báo App Ngân hàng'),
              Tab(text: 'Tin nhắn SMS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Mẫu mô phỏng Notification Listener
            ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sampleBankNotifications.length,
              itemBuilder: (context, index) {
                final item = _sampleBankNotifications[index];
                final bank = item['bank']!;
                final title = item['title']!;
                final body = item['body']!;
                final stk = item['stk']!;
                final amount = item['amount']!;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.notifications_active, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                bank,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              'STK: $stk',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(title, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      Text(body, style: const TextStyle(fontSize: 12, color: AppColors.textDark)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Thay đổi: $amount', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: () => _showSampleSyncDialog(bank),
                            icon: const Icon(Icons.info_outline, color: Colors.black, size: 16),
                            label: const Text('Xem mô phỏng', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            // Tab 2: Hộp thư SMS thực tế
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _messages.isEmpty
                ? const Center(
              child: Text('Không tìm thấy tin nhắn nào trong hộp thư!', style: TextStyle(color: AppColors.textSub)),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final body = msg['body'] ?? '';
                final sender = msg['address'] ?? 'Không rõ';

                bool isBankSms = body.toLowerCase().contains('vnd') ||
                    body.toLowerCase().contains('vnđ') ||
                    body.toLowerCase().contains('tai khoan') ||
                    body.toLowerCase().contains('so du') ||
                    RegExp(r'\bTK\b', caseSensitive: false).hasMatch(body);

                final parsedDebt = isBankSms ? null : PersonalDebtParser.parse(body);
                final isConfirmed = parsedDebt != null && _confirmedDedupKeys.contains(parsedDebt.dedupKey);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isBankSms
                          ? AppColors.primary
                          : (parsedDebt != null
                          ? (isConfirmed ? Colors.green : Colors.orange)
                          : AppColors.border),
                      width: (isBankSms || parsedDebt != null) ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            sender,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
                          ),
                          if (isBankSms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Text(
                                'SMS Ngân hàng',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else if (parsedDebt != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isConfirmed ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isConfirmed ? Colors.green : Colors.orange),
                              ),
                              child: Text(
                                isConfirmed ? 'Đã xác nhận' : 'Chờ xác nhận Nợ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isConfirmed ? Colors.greenAccent : Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                      ),
                      if (parsedDebt != null && !isConfirmed) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Đề xuất: ${_formatMoney(parsedDebt.amount)} đ (${parsedDebt.suggestedCategory})',
                              style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              onPressed: () => _showConfirmDebtDialog(parsedDebt),
                              icon: const Icon(Icons.check_circle_outline, color: Colors.black, size: 16),
                              label: const Text('Xác nhận', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
