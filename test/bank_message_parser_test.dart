import 'package:flutter_test/flutter_test.dart';
import 'package:smart_money_v2/services/bank_message_parser.dart';

void main() {
  group('BankMessageParser Tests', () {
    test('1. Vietcombank Expense Pattern', () {
      const sample =
          'Số dư TK VCB 1036583632 -603,300 VND lúc 19-07-2026 16:12:24. Số dư 233,893 VND. Ref ATM_CWD... GD:BARD Thu Co so 7,704';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.bankName, equals('Vietcombank'));
      expect(result.accountNumber, equals('1036583632'));
      expect(result.amount, equals(603300));
      expect(result.isExpense, isTrue);
      expect(result.endingBalance, equals(233893));
      expect(result.displayNote, equals('BARD Thu Co so 7,704'));
      expect(result.refId, equals('ATM_CWD...'));
    });

    test('2. Vietcombank Income Pattern', () {
      const sample =
          'Số dư TK VCB 1036583632 +2,000,000 VND lúc 19-07-2026 16:12:24. Số dư 2,233,893 VND. Ref 123456 GD:Nhan tien luong';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.bankName, equals('Vietcombank'));
      expect(result.accountNumber, equals('1036583632'));
      expect(result.amount, equals(2000000));
      expect(result.isExpense, isFalse);
      expect(result.endingBalance, equals(2233893));
      expect(result.displayNote, equals('Nhan tien luong'));
      expect(result.refId, equals('123456'));
    });

    test('3. Pipe-delimited Income Pattern', () {
      const sample =
          'TK 99xxxx99 | GD: +1,000,000 VND | 06/07/24 20:56 | SD: 1,234,567 VND | ND: chuyen tien';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.accountNumber, equals('99xxxx99'));
      expect(result.amount, equals(1000000));
      expect(result.isExpense, isFalse);
      expect(result.endingBalance, equals(1234567));
      expect(result.displayNote, equals('chuyen tien'));
    });

    test('4. Pipe-delimited Expense Pattern', () {
      const sample =
          'TK 99xxxx99 | GD: -500,000 VND | 06/07/24 20:56 | SD: 734,567 VND | ND: mua hang';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.accountNumber, equals('99xxxx99'));
      expect(result.amount, equals(500000));
      expect(result.isExpense, isTrue);
      expect(result.endingBalance, equals(734567));
      expect(result.displayNote, equals('mua hang'));
    });

    test('5. Non-bank / Ambiguous Message should return null', () {
      const sample = 'Ma xac nhan OTP cua ban la 123456. Vui long khong chia se ma nay.';

      final result = BankMessageParser.parse(sample);

      expect(result, isNull);
    });

    test('6. VietinBank Multiline Income Pattern', () {
      const sample = '''VietinBank:04/11/2026 23:10
TK:104880072280
GD:+10,000 VND
SDC:145,000 VND
ND:rút tiền về tài khoản, REQ_ID 155158452424''';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.bankName, equals('VietinBank'));
      expect(result.accountNumber, equals('104880072280'));
      expect(result.amount, equals(10000));
      expect(result.isExpense, isFalse);
      expect(result.endingBalance, equals(145000));
      expect(result.refId, equals('155158452424'));
      expect(result.displayNote, equals('rút tiền về tài khoản, REQ_ID 155158452424'));
    });

    test('7. VietinBank Multiline Expense Pattern', () {
      const sample = '''VietinBank:04/11/2026 23:15
TK:104880072280
GD:-50,000 VND
SDC:95,000 VND
ND:thanh toán mua sắm, REQ_ID 155158452425''';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.bankName, equals('VietinBank'));
      expect(result.accountNumber, equals('104880072280'));
      expect(result.amount, equals(50000));
      expect(result.isExpense, isTrue);
      expect(result.endingBalance, equals(95000));
      expect(result.refId, equals('155158452425'));
      expect(result.displayNote, equals('thanh toán mua sắm, REQ_ID 155158452425'));
    });

    test('8. Shorthand 50k Amount Pattern', () {
      const sample = 'MBBank: TK 1012345678 GD: -50k VND SDC: 1,500,000 VND ND: mua ca phe REQ_ID 998877';

      final result = BankMessageParser.parse(sample);

      expect(result, isNotNull);
      expect(result!.bankName, equals('MBBank'));
      expect(result.accountNumber, equals('1012345678'));
      expect(result.amount, equals(50000));
      expect(result.isExpense, isTrue);
      expect(result.endingBalance, equals(1500000));
      expect(result.refId, equals('998877'));
    });

    test('9. Balance Audit Reconciliation Calculation - Income with SDC', () {
      final parsed = BankMessageParser.parse('VietinBank: TK:104880072280 GD:+10,000 VND SDC:145,000 VND ND:nhan tien REQ_ID 112233');

      expect(parsed, isNotNull);
      final currentBalance = 100000;
      final expectedPostTxBal = parsed!.isExpense ? (currentBalance - parsed.amount) : (currentBalance + parsed.amount);
      final delta = (parsed.endingBalance ?? 0) - expectedPostTxBal;

      expect(expectedPostTxBal, equals(110000));
      expect(delta, equals(35000));
    });

    test('10. Balance Audit Reconciliation Calculation - Expense with SDC Mismatch', () {
      final parsed = BankMessageParser.parse('VietinBank: TK:104880072280 GD:-20,000 VND SDC:120,000 VND ND:mua do REQ_ID 445566');

      expect(parsed, isNotNull);
      final currentBalance = 145000;
      final expectedPostTxBal = parsed!.isExpense ? (currentBalance - parsed.amount) : (currentBalance + parsed.amount);
      final delta = (parsed.endingBalance ?? 0) - expectedPostTxBal;

      expect(expectedPostTxBal, equals(125000));
      expect(delta, equals(-5000));
    });
  });
}
