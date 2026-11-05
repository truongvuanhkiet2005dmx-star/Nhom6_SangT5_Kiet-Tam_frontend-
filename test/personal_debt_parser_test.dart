import 'package:flutter_test/flutter_test.dart';
import 'package:smart_money_v2/services/personal_debt_parser.dart';

void main() {
  group('PersonalDebtParser Tests', () {
    test('1. Personal Debt SMS: "Mình nợ bạn 100k tiền mặt nha"', () {
      const sample = 'Mình nợ bạn 100k tiền mặt nha';
      final result = PersonalDebtParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.amount, equals(100000));
      expect(result.isExpense, isTrue);
      expect(result.suggestedCategory, equals('Nợ cá nhân'));
      expect(result.note, equals(sample));
      expect(result.dedupKey, startsWith('DEBT_'));
      expect(result.isPendingConfirmation, isTrue);
    });

    test('2. Personal Loan SMS: "Cho mượn 500 nghìn"', () {
      const sample = 'Cho mượn 500 nghìn';
      final result = PersonalDebtParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.amount, equals(500000));
      expect(result.isExpense, isTrue);
      expect(result.suggestedCategory, equals('Cho vay'));
    });

    test('3. Debt Payment Received SMS: "Đã nhận 1 triệu tiền trả nợ"', () {
      const sample = 'Đã nhận 1 triệu tiền trả nợ';
      final result = PersonalDebtParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.amount, equals(1000000));
      expect(result.isExpense, isFalse);
      expect(result.suggestedCategory, equals('Thu nợ'));
    });

    test('4. Returned Debt Payment SMS: "Đã trả 1.5tr tiền nợ"', () {
      const sample = 'Đã trả 1.5tr tiền nợ';
      final result = PersonalDebtParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.amount, equals(1500000));
      expect(result.isExpense, isTrue);
      expect(result.suggestedCategory, equals('Trả nợ'));
    });

    test('5. Non-debt / Ambiguous Chat Message should return null', () {
      const sample = 'Hôm nay đi cà phê không bạn ơi?';
      final result = PersonalDebtParser.parse(sample);

      expect(result, isNull);
    });

    test('6. Bank SMS should return null in PersonalDebtParser', () {
      const sample = 'VietinBank: TK:104880072280 GD:+10,000 VND SDC:145,000 VND REQ_ID 12345';
      final result = PersonalDebtParser.parse(sample);

      expect(result, isNull);
    });
  });
}
