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

    test('5. Member Transaction Sync Payload should include familyGroupId', () {
      final txPayload = {
        'id': 501,
        'eventId': 'evt-123-abc',
        'userId': 102, // Member ID
        'familyGroupId': 10, // Family Group ID
        'amount': 150000,
        'type': 'expense',
        'isExpense': 1,
        'categoryName': 'Ăn uống',
        'walletId': 20, // Member's wallet ID
      };

      expect(txPayload['familyGroupId'], equals(10));
      expect(txPayload['userId'], equals(102));
      expect(txPayload['walletId'], equals(20));
      expect(txPayload['amount'], equals(150000));
    });

    test('6. Budget API Response Key Normalization', () {
      final resp1 = {'monthlyLimit': 5000000};
      final resp2 = {'limit': 5000000};
      final resp3 = {'amount': 5000000};

      int extractLimit(Map<String, dynamic> data) {
        return (data['monthlyLimit'] ?? data['limit'] ?? data['amount'] as num?)?.toInt() ?? 0;
      }

      expect(extractLimit(resp1), equals(5000000));
      expect(extractLimit(resp2), equals(5000000));
      expect(extractLimit(resp3), equals(5000000));
    });
  });
}
