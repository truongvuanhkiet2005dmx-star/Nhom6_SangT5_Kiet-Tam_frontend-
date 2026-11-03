import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_money_v2/main.dart';
import 'package:smart_money_v2/services/auto_transaction_service.dart';

void main() {
  testWidgets('Kiểm tra render SmartMoneyApp', (WidgetTester tester) async {
    // F27 Fix: Thêm setMockInitialValues để ngắt MissingPluginException khi chạy unit test
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SmartMoneyApp());
    expect(find.byType(SmartMoneyApp), findsOneWidget);
  });

  group('Unit Test AutoTransactionService', () {
    test('Bóc tách số tài khoản từ nội dung thông báo', () {
      final service = AutoTransactionService.instance;

      final result1 = service.extractAccountNumber("TK: 104880072280 GD: -50,000 VND");
      expect(result1, equals("104880072280"));

      final result2 = service.extractAccountNumber("VietinBank 1012345678 chuyen tien");
      expect(result2, equals("1012345678"));
    });
  });
}