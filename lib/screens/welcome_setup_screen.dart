import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import 'login_screen.dart';

class WelcomeSetupScreen extends StatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  State<WelcomeSetupScreen> createState() =>
      _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState
    extends State<WelcomeSetupScreen> {
  String selectedLanguage = 'Tiếng Việt';
  String selectedCurrency = 'VNĐ (₫)';

  final List<String> languages = [
    'Tiếng Việt',
    'English',
    '日本語',
  ];

  final List<String> currencies = [
    'VNĐ (₫)',
    'USD (\$)',
    'EUR (€)',
  ];

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'language',
      selectedLanguage,
    );

    await prefs.setString(
      'currency',
      selectedCurrency,
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          language: selectedLanguage,
          currency: selectedCurrency,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppColors.primary,
                    size: 44,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'SmartMoney',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Thiết lập ngôn ngữ & tiền tệ cơ sở để bắt đầu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSub,
                ),
              ),

              const SizedBox(height: 36),

              const Text(
                'Ngôn ngữ ứng dụng',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedLanguage,
                    dropdownColor: AppColors.card,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.primary,
                    ),
                    items: languages.map((lang) {
                      return DropdownMenuItem(
                        value: lang,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.language,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              lang,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        selectedLanguage = value;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Đơn vị tiền tệ chính',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedCurrency,
                    dropdownColor: AppColors.card,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.primary,
                    ),
                    items: currencies.map((currency) {
                      return DropdownMenuItem(
                        value: currency,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.monetization_on_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              currency,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        selectedCurrency = value;
                      });
                    },
                  ),
                ),
              ),

              const Spacer(),

              ElevatedButton(
                onPressed: _continue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Tiếp tục',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
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