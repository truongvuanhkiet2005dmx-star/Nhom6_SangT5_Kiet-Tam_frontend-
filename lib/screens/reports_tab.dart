import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import '../services/auto_transaction_service.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  int _modeIndex = 0; // 0: Chi tiêu, 1: Thu nhập
  int _selectedMonth = DateTime.now().month;
  bool _isLoading = true;

  int _totalAmount = 0;
  int _monthlyBudget = 10000000;
  Map<String, int> _categoryTotals = {};
  int _reportRequestId = 0;

  StreamSubscription<bool>? _autoTxSub;

  @override
  void initState() {
    super.initState();
    _loadReports();

    _autoTxSub = AutoTransactionService.instance.onTransactionAdded.stream.listen((_) {
      if (mounted) {
        _loadReports();
      }
    });
  }

  @override
  void dispose() {
    _autoTxSub?.cancel();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final currentReqId = ++_reportRequestId;

    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final activeFamilyGroupId = prefs.getInt('activeFamilyGroupId');
    _monthlyBudget = prefs.getInt('monthly_budget') ?? 10000000;

    if (userId == null) {
      if (mounted && currentReqId == _reportRequestId) {
        setState(() => _isLoading = false);
      }
      return;
    }

    bool fetchedFromBackend = false;
    final now = DateTime.now();
    int total = 0;
    Map<String, int> categories = {};

    // Thử lấy báo cáo tháng từ C# Backend API
    try {
      final token = await ApiService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final reportData = await ApiService.instance.getMonthlyReport(
          year: now.year,
          month: _selectedMonth,
          familyGroupId: activeFamilyGroupId,
        );

        if (reportData.isNotEmpty) {
          if (_modeIndex == 0) {
            total = (reportData['totalExpense'] as num?)?.toInt() ?? 0;
          } else {
            total = (reportData['totalIncome'] as num?)?.toInt() ?? 0;
          }

          final breakdownKey = _modeIndex == 0 ? 'expenseBreakdown' : 'incomeBreakdown';
          final categoryList = reportData[breakdownKey] ?? reportData['categoryBreakdown'] ?? reportData['categories'];

          if (categoryList is List) {
            for (var item in categoryList) {
              if (item is Map) {
                final catName = item['categoryName']?.toString() ?? item['category']?.toString() ?? 'Khác';
                final catAmt = ((item['amount'] ?? item['total']) as num?)?.toInt() ?? 0;
                categories[catName] = catAmt;
              }
            }
          }

          if (total > 0 || categories.isNotEmpty) {
            fetchedFromBackend = true;
          }
        }
      }
    } catch (e) {
      debugPrint("[ReportsTab] Backend report error (Fallback sang SQLite): $e");
    }

    // Fallback tính toán từ CSDL SQLite cục bộ nếu không kết nối được backend
    if (!fetchedFromBackend) {
      total = 0;
      categories = {};

      try {
        final transactions = await DatabaseHelper.instance.getAllTransactions(userId);

        for (final tx in transactions) {
          final type = tx['type']?.toString();
          if (type == 'transfer') continue;

          final isExpense = tx['isExpense'] == 1;
          if (_modeIndex == 0 && !isExpense) continue;
          if (_modeIndex == 1 && isExpense) continue;

          final date = DateTime.tryParse(tx['date'].toString());
          if (date == null) continue;

          if (date.year == now.year && date.month == _selectedMonth) {
            final amount = (tx['amount'] as num?)?.toInt() ?? 0;
            final category = tx['categoryName'].toString();

            total += amount;
            categories[category] = (categories[category] ?? 0) + amount;
          }
        }
      } catch (e) {
        debugPrint("Local SQLite report load error: $e");
      }
    }

    // Đảm bảo không ghi đè nếu người dùng đã chuyển tab khác trong khi chờ async
    if (!mounted || currentReqId != _reportRequestId) return;

    setState(() {
      _totalAmount = total;
      _categoryTotals = categories;
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
    return result;
  }

  IconData _getIcon(String category) {
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
      case 'Lương':
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
      default:
        return AppColors.primary;
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

    final categories = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final now = DateTime.now();

    final double circleProgress = (_monthlyBudget <= 0 || _totalAmount <= 0)
        ? 0.0
        : (_totalAmount / _monthlyBudget.toDouble()).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Container(
          width: 220,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _modeIndex = 0;
                    });
                    _loadReports();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: _modeIndex == 0 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Chi tiêu',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _modeIndex == 0 ? Colors.black : AppColors.textSub,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _modeIndex = 1;
                    });
                    _loadReports();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: _modeIndex == 1 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Thu nhập',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _modeIndex == 1 ? Colors.black : AppColors.textSub,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadReports,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(12, (i) => i + 1).map((m) {
                      final isSelected = m == _selectedMonth;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedMonth = m;
                          });
                          _loadReports();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isSelected ? AppColors.primary : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                          child: Text(
                            'thg $m ${now.year}',
                            style: TextStyle(
                              color: isSelected ? AppColors.textDark : AppColors.textSub,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 170,
                        height: 170,
                        child: CircularProgressIndicator(
                          value: circleProgress,
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          strokeWidth: 26,
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            _formatMoney(_totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _modeIndex == 0 ? 'Tổng chi tiêu' : 'Tổng thu nhập',
                            style: const TextStyle(color: AppColors.textSub, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'Chưa có dữ liệu giao dịch trong tháng này',
                        style: TextStyle(color: AppColors.textSub, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ...categories.map((entry) {
                    final double ratio = _totalAmount == 0 ? 0.0 : (entry.value / _totalAmount);
                    final percentStr = (ratio * 100).toStringAsFixed(2).replaceAll('.', ',');

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _getCategoryColor(entry.key),
                                child: Icon(
                                  _getIcon(entry.key),
                                  color: Colors.black87,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                _formatMoney(entry.value),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const SizedBox(width: 48),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 6,
                                    backgroundColor: AppColors.surface,
                                    color: _getCategoryColor(entry.key),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '$percentStr%',
                                style: const TextStyle(color: AppColors.textSub, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
