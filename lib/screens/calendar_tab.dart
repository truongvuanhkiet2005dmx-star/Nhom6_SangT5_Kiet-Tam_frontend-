import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../database/database_helper.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  final Map<DateTime, List<Map<String, dynamic>>> _events = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _loadData();
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');

      if (userId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final transactions = await DatabaseHelper.instance.getAllTransactions(userId);

      final Map<DateTime, List<Map<String, dynamic>>> events = {};

      for (final transaction in transactions) {
        final date = DateTime.tryParse(transaction['date'].toString());
        if (date == null) continue;

        final day = _normalizeDate(date);
        events.putIfAbsent(day, () => []);
        events[day]!.add(transaction);
      }

      if (!mounted) return;

      setState(() {
        _events.clear();
        _events.addAll(events);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[_normalizeDate(day)] ?? [];
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
        return Icons.attach_money;
      case 'Tiền thưởng':
        return Icons.card_giftcard;
      case 'Đầu tư':
        return Icons.trending_up;
      case 'Chuyển khoản':
        return Icons.swap_horiz;
      default:
        return Icons.category_outlined;
    }
  }

  Color _getColor(String category) {
    switch (category) {
      case 'Ăn uống':
      case 'Đồ ăn':
        return Colors.orange;
      case 'Đi lại':
        return Colors.blue;
      case 'Mua sắm':
        return Colors.pink;
      case 'Hóa đơn':
        return Colors.purple;
      case 'Giải trí':
        return Colors.red;
      case 'Sức khỏe':
        return Colors.green;
      case 'Tiền lương':
        return Colors.green;
      case 'Tiền thưởng':
        return Colors.orange;
      case 'Đầu tư':
        return Colors.blue;
      case 'Chuyển khoản':
        return Colors.blue;
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

    final selectedEvents = _getEventsForDay(_selectedDay);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Lịch Giao Dịch',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TableCalendar(
                    locale: 'vi_VN',
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) {
                      return isSameDay(_selectedDay, day);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    eventLoader: _getEventsForDay,
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: AppColors.textDark),
                      weekendStyle: TextStyle(color: Colors.redAccent),
                    ),
                    calendarStyle: CalendarStyle(
                      defaultTextStyle: const TextStyle(color: AppColors.textDark),
                      weekendTextStyle: const TextStyle(color: Colors.redAccent),
                      outsideTextStyle: const TextStyle(color: AppColors.textSub),
                      todayDecoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      selectedDecoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      markerSize: 6,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.textDark),
                      rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.textDark),
                      titleTextStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) {
                          return const SizedBox();
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: events.take(3).map((event) {
                            final transaction = event as Map<String, dynamic>;
                            final type = transaction['type'].toString();

                            Color color;
                            if (type == 'income') {
                              color = Colors.greenAccent;
                            } else if (type == 'expense') {
                              color = Colors.redAccent;
                            } else {
                              color = Colors.blueAccent;
                            }

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Giao dịch ngày ${_selectedDay.day}/${_selectedDay.month}/${_selectedDay.year}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),

                      if (selectedEvents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'Không có giao dịch nào trong ngày này',
                              style: TextStyle(
                                color: AppColors.textSub,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      else
                        ...selectedEvents.map(
                              (transaction) {
                            final category = transaction['categoryName'].toString();
                            final type = transaction['type'].toString();
                            // F3 Fix: Safe num casting
                            final amount = (transaction['amount'] as num?)?.toInt() ?? 0;
                            final isExpense = type == 'expense';
                            final isTransfer = type == 'transfer';

                            return _buildTransactionItem(
                              icon: _getIcon(category),
                              iconColor: _getColor(category),
                              title: category,
                              note: transaction['note']?.toString().isNotEmpty == true
                                  ? transaction['note'].toString()
                                  : 'Giao dịch',
                              amount: isTransfer
                                  ? _formatMoney(amount)
                                  : '${isExpense ? '- ' : '+ '}${_formatMoney(amount)}',
                              type: type,
                            );
                          },
                        ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String note,
    required String amount,
    required String type,
  }) {
    Color amountColor;

    if (type == 'expense') {
      amountColor = AppColors.textDark;
    } else if (type == 'income') {
      amountColor = Colors.greenAccent;
    } else {
      amountColor = Colors.blueAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withValues(alpha: 0.2),
            child: Icon(
              icon,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}