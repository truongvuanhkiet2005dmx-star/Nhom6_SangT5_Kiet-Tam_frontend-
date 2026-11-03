import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

import '../core/app_colors.dart';
import '../core/voice_parser_util.dart';
import '../services/auto_transaction_service.dart';
import 'home_tab.dart';
import 'reports_tab.dart';
import 'wallets_tab.dart';
import 'profile_tab.dart';
import 'add_transaction_screen.dart';
import 'bill_scanner_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState
    extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isDialogOpen = false;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    AutoTransactionService.instance.initialize();
  }

  late final List<Widget> _screens = const [
    HomeTab(),
    ReportsTab(),
    WalletsTab(),
    ProfileTab(),
  ];

  Future<void> _openAddTransaction({String? amount, String? note}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(
          initialAmount: amount,
          initialNote: note,
        ),
      ),
    );
  }

  Future<void> _openBillScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BillScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      final amount = result.toString();

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddTransactionScreen(
            initialAmount: amount,
          ),
        ),
      );
    }
  }

  Map<String, String> _parseVoiceText(String text) {
    final parsed = VoiceParserUtil.parseVoiceInput(text);
    final amountInt = parsed['amount'] as int? ?? 0;
    return {
      'amount': amountInt > 0 ? amountInt.toString() : '0',
      'note': parsed['note']?.toString() ?? text,
    };
  }

  Future<void> _startVoiceInput(StateSetter setDialogState) async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng cấp quyền Micro trong Cài đặt điện thoại!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _speechAvailable = await _speech.initialize();

    // F1 Fix: Không gán chuỗi lỗi vào _recognizedText khi mic hỏng, tránh hiện nút "Tiếp tục" sai UX
    if (!_speechAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể kết nối Micro. Vui lòng kiểm tra lại quyền!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language') ?? 'Tiếng Việt';
    String localeId = 'vi_VN';
    if (lang == 'English') {
      localeId = 'en_US';
    } else if (lang == '日本語') {
      localeId = 'ja_JP';
    }

    if (!mounted || !_isDialogOpen) return;

    setState(() {
      _isListening = true;
      _recognizedText = '';
    });
    setDialogState(() {
      _recognizedText = '';
    });

    await _speech.listen(
      localeId: localeId,
      onResult: (result) {
        if (!mounted || !_isDialogOpen) return;

        setDialogState(() {
          _recognizedText = result.recognizedWords;
        });
        setState(() {
          _recognizedText = result.recognizedWords;
        });
      },
    );
  }

  Future<void> _stopVoiceInput() async {
    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });
  }

  Future<void> _cancelVoiceInput() async {
    await _speech.cancel();

    if (!mounted) return;

    setState(() {
      _isListening = false;
      _recognizedText = '';
    });
  }

  void _showActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _actionButton(
                    icon: Icons.remove_circle,
                    color: Colors.redAccent,
                    label: 'Chi/Thu',
                    onTap: () {
                      Navigator.pop(context);
                      _openAddTransaction();
                    },
                  ),

                  _actionButton(
                    icon: Icons.camera_alt,
                    color: Colors.blueAccent,
                    label: 'Quét Bill',
                    onTap: () {
                      Navigator.pop(context);
                      _openBillScanner();
                    },
                  ),

                  _actionButton(
                    icon: Icons.mic,
                    color: AppColors.primary,
                    label: 'Giọng nói',
                    onTap: () {
                      Navigator.pop(context);
                      _showVoiceInputDialog();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showVoiceInputDialog() {
    _isDialogOpen = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              padding: const EdgeInsets.only(
                top: 32,
                bottom: 40,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isListening
                        ? 'Đang nghe...'
                        : 'Nhập bằng giọng nói',
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: Text(
                      _recognizedText.isEmpty
                          ? 'Ví dụ: "Ăn sáng ba mươi ngàn" hoặc "Cà phê 50k"'
                          : _recognizedText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontStyle: _recognizedText.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  GestureDetector(
                    onTap: () async {
                      if (_isListening) {
                        await _stopVoiceInput();
                      } else {
                        await _startVoiceInput(setDialogState);
                      }

                      if (_isDialogOpen) {
                        setDialogState(() {});
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 100,
                      width: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? Colors.red.withValues(alpha: 0.2)
                            : AppColors.primary.withValues(alpha: 0.2),
                        boxShadow: [
                          BoxShadow(
                            color: _isListening
                                ? Colors.red.withValues(alpha: 0.3)
                                : AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          height: 70,
                          width: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening
                                ? Colors.red
                                : AppColors.primary,
                          ),
                          child: Icon(
                            _isListening ? Icons.stop : Icons.mic,
                            color: Colors.black,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_recognizedText.isNotEmpty)
                    ElevatedButton(
                      onPressed: () {
                        final parsed = _parseVoiceText(_recognizedText);
                        Navigator.pop(context);
                        _openAddTransaction(
                          amount: parsed['amount'],
                          note: parsed['note'],
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Tiếp tục nhập giao dịch',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: () async {
                      await _cancelVoiceInput();

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      'Hủy',
                      style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() async {
      // F8 Fix: Thêm await khi gọi _stopVoiceInput tránh race condition
      _isDialogOpen = false;
      if (_isListening) {
        await _stopVoiceInput();
      }
    });
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : Colors.grey.shade600,
                size: 24,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      floatingActionButton: SizedBox(
        width: 54,
        height: 54,
        child: FloatingActionButton(
          onPressed: () {
            _showActionMenu(context);
          },
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 3,
          shape: const CircleBorder(),
          child: const Icon(
            Icons.add,
            size: 28,
          ),
        ),
      ),

      floatingActionButtonLocation:
      FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _buildNavItem(
                icon: Icons.ballot_outlined,
                label: 'Trang chủ',
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.pie_chart_outline_rounded,
                label: 'Biểu đồ',
                index: 1,
              ),

              const SizedBox(width: 54),

              _buildNavItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Ví',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.person_outline,
                label: 'Tôi',
                index: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}