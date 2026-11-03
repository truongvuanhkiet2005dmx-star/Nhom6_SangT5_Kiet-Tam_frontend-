import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/native_listener_bridge.dart';

class SmsListScreen extends StatefulWidget {
  const SmsListScreen({super.key});

  @override
  State<SmsListScreen> createState() => _SmsListScreenState();
}

class _SmsListScreenState extends State<SmsListScreen> {
  List<Map<String, String>> _messages = [];
  bool _isLoading = true;

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
      List<Map<String, String>> messages = await NativeListenerBridge.getInboxSms();

      if (!mounted) return;

      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // F2 Fix: Hướng dẫn mô phỏng an toàn, tránh tạo giao dịch thật từ mẫu demo
  void _showSampleSyncDialog(String bankName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đây là thẻ mẫu mô phỏng cho $bankName. Để đồng bộ thông báo thật, hãy dùng nút Sync trên Trang chủ!'),
        backgroundColor: Colors.amber.shade900,
        duration: const Duration(seconds: 4),
      ),
    );
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

                // F10 Fix: Xiết chặt nhận diện SMS ngân hàng, tránh khớp đơn lẻ chữ đ trong văn bản Tiếng Việt
                bool isBankSms = body.toLowerCase().contains('vnd') ||
                    body.toLowerCase().contains('vnđ') ||
                    body.toLowerCase().contains('tai khoan') ||
                    body.toLowerCase().contains('so du') ||
                    RegExp(r'\bTK\b', caseSensitive: false).hasMatch(body);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isBankSms ? AppColors.primary : AppColors.border,
                      width: isBankSms ? 1.5 : 1,
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
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                      ),
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