import 'package:flutter_test/flutter_test.dart';

bool isOwnerOf(Map<String, dynamic> family, String currentUserId) {
  if (family['isOwner'] == true) return true;
  final members = family['members'];
  if (members is! List) return false;
  return members.any((m) =>
    m is Map &&
    m['userId']?.toString() == currentUserId &&
    m['accessRole']?.toString().toLowerCase() == 'owner'
  );
}

void main() {
  group('Family Budget & Group Expense Aggregation Tests', () {
    test('1. Owner role should be allowed to set family budget', () {
      final family = {
        'id': 10,
        'name': 'Gia Đình Anh Kiệt',
        'isOwner': true,
        'members': [
          {'userId': '101', 'accessRole': 'Owner'},
          {'userId': '102', 'accessRole': 'Member'},
        ],
      };

      expect(isOwnerOf(family, '101'), isTrue);
    });

    test('2. Member role should NOT be allowed to edit family budget', () {
      final family = {
        'id': 10,
        'name': 'Gia Đình Anh Kiệt',
        'isOwner': false,
        'members': [
          {'userId': '101', 'accessRole': 'Owner'},
          {'userId': '102', 'accessRole': 'Member'},
        ],
      };

      expect(isOwnerOf(family, '102'), isFalse);
    });

    test('3. Group total monthly expense should aggregate all member expenses', () {
      final member1Expenses = [100000, 250000, 50000];
      final member2Expenses = [300000, 150000];

      final totalMember1 = member1Expenses.fold<int>(0, (sum, val) => sum + val);
      final totalMember2 = member2Expenses.fold<int>(0, (sum, val) => sum + val);
      final groupTotalExpense = totalMember1 + totalMember2;

      expect(totalMember1, equals(400000));
      expect(totalMember2, equals(450000));
      expect(groupTotalExpense, equals(850000));

      const monthlyBudget = 1000000;
      final isExceeded = groupTotalExpense > monthlyBudget;
      final remaining = monthlyBudget - groupTotalExpense;

      expect(isExceeded, isFalse);
      expect(remaining, equals(150000));
    });

    test('4. Group budget overrun warning detection', () {
      const groupTotalExpense = 1200000;
      const monthlyBudget = 1000000;

      final isExceeded = groupTotalExpense > monthlyBudget;
      final overrunDelta = groupTotalExpense - monthlyBudget;

      expect(isExceeded, isTrue);
      expect(overrunDelta, equals(200000));
    });
  });
}
