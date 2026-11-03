import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/app_colors.dart';
import '../core/voice_parser_util.dart';
import '../database/database_helper.dart';
import '../services/auto_transaction_service.dart';
import '../services/sync_service.dart';
import 'bill_scanner_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  final String? initialAmount;
  final String? initialNote;

  const AddTransactionScreen({
    super.key,
    this.initialAmount,
    this.initialNote,
  });

  @override
  State<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState
    extends State<AddTransactionScreen> {
  String _amount = '0';
  int _tabIndex = 0; // 0: Chi tiêu, 1: Thu nhập, 2: Chuyển khoản

  // F2 Fix: Khớp danh mục mặc định "Đồ ăn" với item trong lưới
  String _selectedCategory = 'Đồ ăn';

  int? _selectedWalletId;
  String _selectedWallet = 'Chọn ví nguồn';

  int? _selectedToWalletId;
  String _selectedToWallet = 'Chọn ví đích';

  DateTime _selectedDate = DateTime.now();
  String _note = '';

  List<Map<String, dynamic>> _wallets = [];
  int? _userId;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialAmount != null &&
        widget.initialAmount!.isNotEmpty) {
      _amount = widget.initialAmount!
          .replaceAll(',', '')
          .replaceAll('.', '');
    }

    if (widget.initialNote != null &&
        widget.initialNote!.isNotEmpty) {
      _note = widget.initialNote!;
    }

    _loadData();
  }

  Future<void> _loadData() async {
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

    final wallets = await DatabaseHelper.instance.getWallets(userId);

    if (!mounted) return;

    setState(() {
      _userId = userId;
      _wallets = wallets;
      _isLoading = false;

      if (_wallets.isNotEmpty) {
        _selectedWalletId = _wallets.first['id'] as int;
        _selectedWallet = _wallets.first['name'].toString();

        if (_wallets.length > 1) {
          _selectedToWalletId = _wallets[1]['id'] as int;
          _selectedToWallet = _wallets[1]['name'].toString();
        }
      }
    });
  }

  String get _formattedAmount {
    if (_amount.isEmpty) return '0';

    final cleaned = _amount.replaceAll(',', '').replaceAll('.', '');
    final number = int.tryParse(cleaned) ?? 0;

    return _formatMoney(number);
  }

  int _getAmount() {
    final cleaned = _amount.replaceAll(',', '').replaceAll('.', '').trim();
    final parsed = num.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return 0;
    if (parsed > 1000000000000) return 1000000000000;
    return parsed.toInt();
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

  void _onKeyPress(String key) {
    if (key == '⌫') {
      setState(() {
        if (_amount.length > 1) {
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
        }
      });
      return;
    }

    if (key == '✓') {
      _saveTransaction();
      return;
    }

    if (key == '+') return;

    if (key == '000') {
      setState(() {
        if (_amount != '0' && _amount.length <= 9) {
          _amount += '000';
        }
      });
      return;
    }

    if (key == 'Hôm nay') {
      _pickDate();
      return;
    }

    if (key == ',' || key == '.') {
      return;
    }

    setState(() {
      if (_amount == '0') {
        _amount = key;
      } else if (_amount.length < 12) {
        _amount += key;
      }
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (date == null) return;

    setState(() {
      _selectedDate = date;
    });
  }

  Future<void> _showNoteDialog() async {
    final newNote = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(initialNote: _note),
    );

    if (newNote != null && mounted) {
      setState(() {
        _note = newNote;
      });
    }
  }

  Future<void> _showWalletPicker({bool isTargetWallet = false}) async {
    if (_wallets.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  isTargetWallet ? 'Chọn ví đích (Nhận tiền)' : 'Chọn ví nguồn (Trừ tiền)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Builder(
                builder: (context) {
                  final filteredWallets = _wallets.where((wallet) {
                    if (isTargetWallet && (wallet['id'] as int) == _selectedWalletId) {
                      return false;
                    }
                    return true;
                  }).toList();

                  if (filteredWallets.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Bạn cần có ít nhất 2 ví để thực hiện chuyển khoản. Hãy tạo thêm ví trong Tab Ví!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSub, fontSize: 13),
                      ),
                    );
                  }

                  return Column(
                    children: filteredWallets.map((wallet) {
                      final balance = wallet['balance'] as int;
                      final walletId = wallet['id'] as int;

                      return ListTile(
                        leading: const Icon(
                          Icons.account_balance_wallet,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          wallet['name'].toString(),
                          style: const TextStyle(color: AppColors.textDark),
                        ),
                        subtitle: Text(
                          '${_formatMoney(balance)} đ',
                          style: const TextStyle(color: AppColors.textSub),
                        ),
                        trailing: (isTargetWallet ? walletId == _selectedToWalletId : walletId == _selectedWalletId)
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : null,
                        onTap: () {
                          setState(() {
                            if (isTargetWallet) {
                              _selectedToWalletId = walletId;
                              _selectedToWallet = wallet['name'].toString();
                            } else {
                              _selectedWalletId = walletId;
                              _selectedWallet = wallet['name'].toString();
                            }
                          });
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBillScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BillScannerScreen(),
      ),
    );

    if (result == null || !mounted) return;

    final cleaned = result
        .toString()
        .replaceAll(',', '')
        .replaceAll('.', '')
        .replaceAll(' đ', '')
        .trim();

    if (int.tryParse(cleaned) != null) {
      setState(() {
        _amount = cleaned;
        _selectedCategory = 'Hóa đơn';
        if (_note.isEmpty) {
          _note = 'Quét hóa đơn';
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã nhận số tiền hóa đơn! Bấm nút ✓ để lưu.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _openVoiceInputSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _VoiceInputModal(
          onVoiceParsed: (amount, category, note) {
            setState(() {
              if (amount != null && amount > 0) {
                _amount = amount.toString();
              }
              if (category != null && category.isNotEmpty) {
                _selectedCategory = category;
              }
              if (note != null && note.isNotEmpty) {
                _note = note;
              }
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đã nhận diện giọng nói: $note'),
                backgroundColor: Colors.green,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) return;

    // F19 Fix: Thông báo phản hồi rõ ràng khi chưa có userId hoặc chưa chọn ví
    if (_userId == null || _selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa chọn ví hoặc không tìm thấy tài khoản!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amount = _getAmount();

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số tiền!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_tabIndex == 2 && (_selectedToWalletId == null || _selectedToWalletId == _selectedWalletId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ví đích khác ví nguồn!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final db = await DatabaseHelper.instance.database;

      int insertedId = 0;
      await db.transaction((txn) async {
        final fromWallet = await txn.query(
          'wallets',
          where: 'id = ? AND userId = ?',
          whereArgs: [_selectedWalletId, _userId],
          limit: 1,
        );

        if (fromWallet.isEmpty) {
          throw Exception('Ví nguồn không tồn tại');
        }

        final currentBalance = fromWallet.first['balance'] as int;

        if (_tabIndex == 0) {
          await txn.update(
            'wallets',
            {'balance': currentBalance - amount},
            where: 'id = ? AND userId = ?',
            whereArgs: [_selectedWalletId, _userId],
          );
        } else if (_tabIndex == 1) {
          await txn.update(
            'wallets',
            {'balance': currentBalance + amount},
            where: 'id = ? AND userId = ?',
            whereArgs: [_selectedWalletId, _userId],
          );
        } else if (_tabIndex == 2) {
          await txn.update(
            'wallets',
            {'balance': currentBalance - amount},
            where: 'id = ? AND userId = ?',
            whereArgs: [_selectedWalletId, _userId],
          );

          final toWallet = await txn.query(
            'wallets',
            where: 'id = ? AND userId = ?',
            whereArgs: [_selectedToWalletId, _userId],
            limit: 1,
          );

          if (toWallet.isNotEmpty) {
            final targetBalance = toWallet.first['balance'] as int;
            await txn.update(
              'wallets',
              {'balance': targetBalance + amount},
              where: 'id = ? AND userId = ?',
              whereArgs: [_selectedToWalletId, _userId],
            );
          }
        }

        String typeStr = 'expense';
        int isExpenseVal = 1;

        if (_tabIndex == 1) {
          typeStr = 'income';
          isExpenseVal = 0;
        } else if (_tabIndex == 2) {
          typeStr = 'transfer';
          isExpenseVal = 0;
        }

        insertedId = await txn.insert(
          'transactions',
          {
            'userId': _userId,
            'walletId': _selectedWalletId,
            'toWalletId': _tabIndex == 2 ? _selectedToWalletId : null,
            'amount': amount,
            'type': typeStr,
            'isExpense': isExpenseVal,
            'categoryName': _tabIndex == 2 ? 'Chuyển khoản' : _selectedCategory,
            'date': _selectedDate.toIso8601String(),
            'note': _note,
            'isSynced': 0,
            'eventId': 'tx_0',
          },
        );

        await txn.update(
          'transactions',
          {'eventId': 'tx_$insertedId'},
          where: 'id = ?',
          whereArgs: [insertedId],
        );
      });

      // F6 Fix: Lấy kết quả đồng bộ C# Backend thực tế
      bool isSyncedSuccess = false;
      try {
        final txData = {
          'id': insertedId,
          'eventId': 'tx_$insertedId',
          'amount': amount,
          'type': _tabIndex == 0 ? 'expense' : (_tabIndex == 1 ? 'income' : 'transfer'),
          'walletName': _selectedWallet,
          'bankName': _selectedWallet,
          'packageName': '',
          'categoryName': _tabIndex == 2 ? 'Chuyển khoản' : _selectedCategory,
          'date': _selectedDate.toIso8601String(),
          'note': _note,
        };
        isSyncedSuccess = await SyncService.instance.syncTransaction(txData);
      } catch (e) {
        debugPrint("Manual tx sync error: $e");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSyncedSuccess
              ? 'Đã lưu & đồng bộ thành công!'
              : 'Đã lưu cục bộ, đang chờ đồng bộ server...'),
          backgroundColor: isSyncedSuccess ? Colors.green : Colors.orange,
        ),
      );

      AutoTransactionService.instance.onTransactionAdded.add(true);

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final errorStr = e.toString().replaceAll('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorStr.isNotEmpty ? errorStr : 'Không thể lưu giao dịch!'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // F2 Fix: Thêm 'Hóa đơn' vào danh sách categories chi tiêu trong grid
    final expenseCategories = [
      {'name': 'Đồ ăn', 'icon': Icons.restaurant},
      {'name': 'Đi lại', 'icon': Icons.directions_bus},
      {'name': 'Mua sắm', 'icon': Icons.shopping_bag_outlined},
      {'name': 'Hóa đơn', 'icon': Icons.receipt_long},
      {'name': 'Điện thoại', 'icon': Icons.phone_android},
      {'name': 'Giải trí', 'icon': Icons.movie_outlined},
      {'name': 'Giáo dục', 'icon': Icons.menu_book},
      {'name': 'Làm đẹp', 'icon': Icons.face},
      {'name': 'Thể thao', 'icon': Icons.pool},
      {'name': 'Giao lưu', 'icon': Icons.people_outline},
      {'name': 'Quần áo', 'icon': Icons.checkroom},
      {'name': 'Khác', 'icon': Icons.more_horiz},
    ];

    final incomeCategories = [
      {'name': 'Lương', 'icon': Icons.account_balance_wallet_outlined},
      {'name': 'Thưởng', 'icon': Icons.card_giftcard},
      {'name': 'Đầu tư', 'icon': Icons.trending_up},
      {'name': 'Khác', 'icon': Icons.more_horiz},
    ];

    final categories = _tabIndex == 1 ? incomeCategories : expenseCategories;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: AppColors.textDark, fontSize: 16)),
        ),
        title: const Text(
          'Thêm',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: AppColors.primary, size: 28),
            onPressed: _isSaving ? null : _saveTransaction,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildModeTab('Chi tiêu', 0),
                _buildModeTab('Thu nhập', 1),
                _buildModeTab('Chuyển khoản', 2),
              ],
            ),
          ),

          Expanded(
            child: _tabIndex == 2
                ? Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.swap_horiz, size: 60, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Chuyển tiền giữa 2 ví tài khoản',
                    style: TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Số tiền sẽ được trừ ở Ví nguồn và tự động cộng vào Ví đích.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSub, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showWalletPicker(isTargetWallet: false),
                          icon: const Icon(Icons.upload, color: Colors.redAccent),
                          label: Text(_selectedWallet, style: const TextStyle(color: AppColors.textDark, fontSize: 12)),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, color: AppColors.primary),
                      ),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showWalletPicker(isTargetWallet: true),
                          icon: const Icon(Icons.download, color: Colors.greenAccent),
                          label: Text(_selectedToWallet, style: const TextStyle(color: AppColors.textDark, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
                : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final item = categories[index];
                      final name = item['name'] as String;
                      final icon = item['icon'] as IconData;
                      final isSelected = _selectedCategory == name;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategory = name;
                          });
                        },
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: isSelected ? AppColors.primary : AppColors.card,
                              child: Icon(
                                icon,
                                color: isSelected ? Colors.black : AppColors.textDark,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? AppColors.primary : AppColors.textSub,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surface,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => _showWalletPicker(isTargetWallet: false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet, size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(_selectedWallet, style: const TextStyle(color: AppColors.textDark, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '$_formattedAmount đ',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _showNoteDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _note.isEmpty ? 'Ghi chú: Nhập ghi chú...' : 'Ghi chú: $_note',
                            style: TextStyle(
                              color: _note.isEmpty ? AppColors.textSub : AppColors.primary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.mic, color: AppColors.primary),
                      onPressed: _openVoiceInputSheet,
                      tooltip: 'Nhập bằng giọng nói Tiếng Việt',
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                      onPressed: _openBillScanner,
                      tooltip: 'Quét hóa đơn AI',
                    ),
                  ],
                ),
              ],
            ),
          ),

          Container(
            color: AppColors.card,
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
              bottom: bottomInset + 16,
            ),
            child: Column(
              children: [
                _buildKeypadRow(['7', '8', '9', 'Hôm nay']),
                _buildKeypadRow(['4', '5', '6', '+']),
                _buildKeypadRow(['1', '2', '3', '000']),
                _buildKeypadRow(['0', '⌫', '✓']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, int index) {
    final isSelected = _tabIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tabIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.textDark : AppColors.textSub,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        final isSave = key == '✓';
        final isAction = key == 'Hôm nay' || key == '+';

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: InkWell(
              onTap: () => _onKeyPress(key),
              borderRadius: BorderRadius.circular(8),
              child: Ink(
                height: 52,
                decoration: BoxDecoration(
                  color: isSave ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: key == '⌫'
                      ? const Icon(Icons.backspace_outlined, color: AppColors.textDark, size: 20)
                      : (key == '✓'
                      ? const Icon(Icons.check, color: Colors.black, size: 28)
                      : Text(
                    key,
                    style: TextStyle(
                      fontSize: isAction ? 13 : 20,
                      fontWeight: FontWeight.bold,
                      color: isAction ? AppColors.primary : AppColors.textDark,
                    ),
                  )),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VoiceInputModal extends StatefulWidget {
  final Function(int? amount, String? category, String? note) onVoiceParsed;

  const _VoiceInputModal({required this.onVoiceParsed});

  @override
  State<_VoiceInputModal> createState() => _VoiceInputModalState();
}

class _VoiceInputModalState extends State<_VoiceInputModal> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _liveText = '';
  String _selectedLocale = 'vi_VN';
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _isListening = status == 'listening';
            });
          }
        },
        onError: (errorNotification) {
          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isAvailable = available;
        });

        if (available) {
          _startListening();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAvailable = false;
        });
      }
    }
  }

  Future<void> _startListening() async {
    if (!_isAvailable) return;

    setState(() {
      _liveText = 'Đang lắng nghe... Hãy đọc câu thoại (ví dụ: "Cà phê 50k")';
    });

    await _speech.listen(
      localeId: _selectedLocale,
      onResult: (result) {
        if (mounted) {
          setState(() {
            _liveText = result.recognizedWords;
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _confirmAndParse() {
    if (_liveText.isEmpty || _liveText.startsWith('Đang lắng nghe')) {
      Navigator.pop(context);
      return;
    }

    final parsed = VoiceParserUtil.parseVoiceInput(_liveText);

    widget.onVoiceParsed(parsed['amount'] as int?, parsed['category'] as String?, parsed['note'] as String?);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nhập Bằng Giọng Nói',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('🇻🇳 Tiếng Việt', style: TextStyle(fontSize: 11)),
                    selected: _selectedLocale == 'vi_VN',
                    selectedColor: AppColors.primary,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedLocale = 'vi_VN';
                        });
                        _startListening();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('🇺🇸 English', style: TextStyle(fontSize: 11)),
                    selected: _selectedLocale == 'en_US',
                    selectedColor: AppColors.primary,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedLocale = 'en_US';
                        });
                        _startListening();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minHeight: 100),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isListening ? AppColors.primary : AppColors.border,
                width: 2,
              ),
            ),
            child: Text(
              _liveText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _liveText.startsWith('Đang lắng nghe')
                    ? AppColors.textSub
                    : AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 20),

          GestureDetector(
            onTap: _isAvailable
                ? () {
              if (_isListening) {
                _stopListening();
              } else {
                _startListening();
              }
            }
                : null,
            child: CircleAvatar(
              radius: 36,
              backgroundColor: !_isAvailable
                  ? Colors.grey
                  : (_isListening ? Colors.redAccent : AppColors.primary),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: Colors.black,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isListening ? 'Chạm để dừng thu âm' : 'Chạm để nói lại',
            style: const TextStyle(color: AppColors.textSub, fontSize: 12),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    _stopListening();
                    Navigator.pop(context);
                  },
                  child: const Text('Hủy', style: TextStyle(color: AppColors.textSub)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _confirmAndParse,
                  child: const Text(
                    'Xác Nhận & Tự Động Điền',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  final String initialNote;

  const _NoteDialog({required this.initialNote});

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Ghi chú giao dịch', style: TextStyle(color: AppColors.textDark)),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        autofocus: true,
        style: const TextStyle(color: AppColors.textDark),
        decoration: const InputDecoration(
          hintText: 'Ví dụ: Ăn sáng, Mua quà...',
          hintStyle: TextStyle(color: AppColors.textSub),
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: AppColors.textSub)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            Navigator.pop(context, _controller.text.trim());
          },
          child: const Text('Lưu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}