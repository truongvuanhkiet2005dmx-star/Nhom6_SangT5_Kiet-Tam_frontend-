import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavingsGoal Logic Tests', () {
    test('1. Valid Savings Goal Target and Initial Amounts', () {
      final name = 'Mua Xe Máy'.trim();
      final targetStr = '30,000,000';
      final initialStr = '5,000,000';

      final target = int.tryParse(targetStr.replaceAll(',', '').replaceAll('.', '')) ?? 0;
      final initial = int.tryParse(initialStr.replaceAll(',', '').replaceAll('.', '')) ?? 0;

      expect(name, equals('Mua Xe Máy'));
      expect(target, equals(30000000));
      expect(initial, equals(5000000));
      expect(target > 0, isTrue);
    });

    test('2. Savings Deposit Balance Deduction and Goal Addition Math', () {
      const currentWalletBal = 10000000;
      const currentGoalAmount = 5000000;
      const depositAmount = 2000000;

      final hasSufficientBalance = currentWalletBal >= depositAmount;
      final newWalletBal = currentWalletBal - depositAmount;
      final newGoalAmount = currentGoalAmount + depositAmount;

      expect(hasSufficientBalance, isTrue);
      expect(newWalletBal, equals(8000000));
      expect(newGoalAmount, equals(7000000));
    });

    test('3. Insufficient Wallet Balance Should Block Savings Deposit', () {
      const currentWalletBal = 500000;
      const depositAmount = 2000000;

      final hasSufficientBalance = currentWalletBal >= depositAmount;

      expect(hasSufficientBalance, isFalse);
    });
  });
}
