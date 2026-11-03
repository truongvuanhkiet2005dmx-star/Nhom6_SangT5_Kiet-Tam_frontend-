import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';
import '../services/auto_transaction_service.dart';
import '../services/sync_service.dart';
import '../services/native_listener_bridge.dart';
import 'welcome_setup_screen.dart';
import 'sms_list_screen.dart';
import 'calendar_tab.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _hasNotificationPermission = true;
  int _totalBalance = 0;
  int _totalIncome = 0;
  int _totalExpense = 0;
  List<Map<String, dynamic>> _transactions = [];
  String _selectedFilter = 'Tất cả';
  DateTime? _lastLoadTime;

  StreamSubscription<bool>? _autoTxSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHomeData();

    _autoTxSub = AutoTransactionService.instance.onTransactionAdded.stream.listen((_) {
      if (mounted) {
        _loadHomeData();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTxSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastLoadTime != null && DateTime.now().difference(_lastLoadTime!) < const Duration(seconds: 5)) {
        return;
      }
      _loadHomeData();
    }
  }

  Future<void> _loadHomeData() async {
    _lastLoadTime = DateTime.now();

    setState(() {
      _isLoading = true;
    });

    try {
      bool isGranted = await NativeListenerBridge.hasNotificationPermission();
      if (mounted) {
        setState(() {
          _hasNotificationPermission = isGranted;
        });
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeSetupScreen()),
            (route) => false,
      );
      return;
    }

    final wallets = await DatabaseHelper.instance.getWallets(userId);
    int balance = 0;
    for (var w in wallets) {
      balance += ((w['balance'] as num?)?.toInt() ?? 0);
    }

    // F4 Fix: Lọc tổng Thu nhập và Chi tiêu chính xác theo Tháng & Năm cho Header "Thg X"
    final now = DateTime.now();
    final totalIncome = await DatabaseHelper.instance.getMonthIncome(userId, now.year, now.month);
    final totalExpense = await DatabaseHelper.instance.getMonthExpense(userId, now.year, now.month);

    final db = await DatabaseHelper.instance.database;
    final txs = await db.query(
      'transactions',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: 50,
    );

    if (!mounted) return;

    setState(() {
      _totalBalance = balance;
      _totalIncome = totalIncome;
      _totalExpense = totalExpense;
      _transactions = txs;
      _isLoading = false;
    });

    unawaited(SyncService.instance.syncAllPendingTransactions(userId));
  }

  Widget _buildNotificationPermissionBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amberAccent),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active, color: Colors.amberAccent, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cấp quyền đọc thông báo ngân hàng', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(height: 2),
                Text('Bật quyền để ứng dụng tự động bóc tách biến động số dư VietinBank, MoMo...', style: TextStyle(color: AppColors.textDark, fontSize: 11)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () async {
              await NativeListenerBridge.openNotificationPermissionSettings();
              await _loadHomeData();
            },
            child: const Text('Bật ngay', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualSyncDialog() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Đồng bộ Thông báo / SMS Ngân hàng', style: TextStyle(color: AppColors.textDark, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dán nội dung thông báo VietinBank/MBBank để tự động bóc tách số tiền và số dư ví:', style: TextStyle(color: AppColors.textSub, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                style: const TextStyle(color: AppColors.textDark, fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Dán nội dung thông báo ngân hàng tại đây...',
                  hintStyle: TextStyle(color: AppColors.textSub),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && data!.text!.isNotEmpty) {
                      controller.text = data.text!;
                    }
                  },
                  icon: const Icon(Icons.content_paste, size: 16, color: AppColors.primary),
                  label: const Text('Dán từ bộ nhớ tạm', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: AppColors.textSub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  try {
                    bool success = await AutoTransactionService.instance.processSmsContent(text, force: true);
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    await _loadHomeData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? 'Đã bóc tách & ghi nhận biến động số dư thành công!'
                            : 'Nội dung không chứa thông tin biến động số dư ngân hàng hợp lệ!'),
                        backgroundColor: success ? Colors.green : Colors.orange,
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Không thể xử lý nội dung này!'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Đồng bộ ngay', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    controller.dispose();
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Ăn uống':
      case 'Đồ ăn':
        return Icons.restaurant;
      case 'Đi lại':
        return Icons.directions_bus;
      case 'Mua sắm':
        return Icons.shopping_bag_outlined;
      case 'Hóa đơn':
        return Icons.receipt_long;
      case 'Giải trí':
        return Icons.movie_outlined;
      case 'Sức khỏe':
        return Icons.favorite_border;
      case 'Tiền lương':
        return Icons.attach_money;
      default:
        return Icons.category_outlined;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Ăn uống':
      case 'Đồ ăn':
        return const Color(0xFF80CBC4);
      case 'Đi lại':
        return const Color(0xFFFFAB91);
      case 'Mua sắm':
        return const Color(0xFFC5CAE9);
      case 'Hóa đơn':
        return const Color(0xFFE1BEE7);
      case 'Giải trí':
        return const Color(0xFFFFCDD2);
      case 'Sức khỏe':
        return const Color(0xFFA5D6A7);
      default:
        return const Color(0xFFFFE082);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const Icon(Icons.menu, color: AppColors.textDark),
        title: const Text(
          'SmartMoney',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: AppColors.primary),
            onPressed: _showManualSyncDialog,
            tooltip: 'Đồng bộ Thông báo/SMS',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month, color: AppColors.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CalendarTab(),
                ),
              );
            },
            tooltip: 'Xem lịch giao dịch',
          ),
          IconButton(
            icon: const Icon(Icons.sms_outlined, color: AppColors.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SmsListScreen(),
                ),
              );
            },
            tooltip: 'Lịch sử SMS',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHomeData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_hasNotificationPermission) _buildNotificationPermissionBanner(),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppColors.surface,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${now.year}\nThg ${now.month}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: AppColors.textDark, fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.keyboard_arrow_down, color: AppColors.textSub, size: 18),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryColumn('Chi tiêu', _formatMoney(_totalExpense)),
                            _buildSummaryColumn('Thu nhập', _formatMoney(_totalIncome)),
                            _buildSummaryColumn('Số dư', _formatMoney(_totalBalance)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: ['Tất cả', 'Chi', 'Thu'].map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : AppColors.textDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilter = filter;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                Builder(
                  builder: (context) {
                    final filteredTransactions = _transactions.where((tx) {
                      final isExp = tx['isExpense'] == 1;
                      final type = tx['type']?.toString();
                      if (_selectedFilter == 'Chi') return isExp && type != 'transfer';
                      if (_selectedFilter == 'Thu') return !isExp && type == 'income';
                      return true;
                    }).toList();

                    if (filteredTransactions.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Text(
                            'Chưa có giao dịch nào',
                            style: TextStyle(color: AppColors.textSub),
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTransactions.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1, thickness: 0.5, color: AppColors.border),
                      itemBuilder: (context, index) {
                        final tx = filteredTransactions[index];
                        final isExp = tx['isExpense'] == 1;
                        final amount = (tx['amount'] as num?)?.toInt() ?? 0;
                        final category = (tx['categoryName'] ?? 'Khác').toString();
                        final note = (tx['note'] ?? '').toString();

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: AppColors.background,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: _getCategoryColor(category),
                                child: Icon(
                                  _getCategoryIcon(category),
                                  color: Colors.black87,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    if (note.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        note,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSub,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                '${isExp ? '-' : '+'}${_formatMoney(amount)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isExp ? AppColors.textDark : Colors.greenAccent,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryColumn(String title, String amount) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSub,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}