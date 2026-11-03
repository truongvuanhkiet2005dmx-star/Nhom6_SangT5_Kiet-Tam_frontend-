import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'api_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Future<void> syncUnsyncedWallets(int userId) async {
    try {
      final token = await ApiService.instance.getToken();
      if (token == null || token.isEmpty) return;

      final unsyncedWallets = await DatabaseHelper.instance.getUnsyncedWallets(userId);
      if (unsyncedWallets.isEmpty) return;

      debugPrint("[SyncService] Phát hiện ${unsyncedWallets.length} ví chưa có serverId.");
      for (final wallet in unsyncedWallets) {
        final localId = wallet['id'] as int;
        final name = wallet['name']?.toString() ?? 'Ví';
        final balance = (wallet['balance'] as num?)?.toInt() ?? 0;
        final type = wallet['type']?.toString() ?? 'cash';
        final accountNumber = wallet['accountNumber']?.toString();

        try {
          final res = await ApiService.instance.createWallet(
            name: name,
            balance: balance,
            type: type,
            accountNumber: accountNumber,
          );

          final serverId = (res['id'] ?? res['walletId']) as int?;
          if (serverId != null && serverId > 0) {
            await DatabaseHelper.instance.updateWalletServerId(localId, serverId);
            debugPrint("[SyncService] Đã gán serverId $serverId cho ví local $localId");
          }
        } catch (e) {
          debugPrint("[SyncService] Không thể tạo ví trên server cho ví local $localId: $e");
        }
      }
    } catch (e) {
      debugPrint("[SyncService] Lỗi khi đồng bộ ví: $e");
    }
  }

  Future<bool> syncTransaction(Map<String, dynamic> tx) async {
    final txId = tx['id'] as int?;
    final eventId = tx['eventId']?.toString().isNotEmpty == true
        ? tx['eventId'].toString()
        : (txId != null ? 'tx_$txId' : 'tx_${DateTime.now().millisecondsSinceEpoch}');

    try {
      final token = await ApiService.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint("[SyncService] Chưa đăng nhập JWT backend. Bỏ qua gửi API cho $eventId (giữ isSynced = 0).");
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final familyGroupId = prefs.getInt('activeFamilyGroupId');

      String type = (tx['type']?.toString().isNotEmpty == true)
          ? tx['type'].toString()
          : (tx['isExpense'] == 1 ? 'expense' : 'income');
      if (type != 'income' && type != 'expense') {
        type = 'expense';
      }

      final String source = tx['walletName']?.toString() ?? 'Ví tài khoản';
      final String bankName = tx['bankName']?.toString() ?? source;
      final String packageName = tx['packageName']?.toString() ?? '';
      final String categoryName = tx['categoryName']?.toString() ?? 'Khác';
      final String note = tx['note']?.toString() ?? '';

      DateTime occurredDate;
      if (tx['date'] != null && tx['date'].toString().isNotEmpty) {
        occurredDate = DateTime.tryParse(tx['date'].toString()) ?? DateTime.now();
      } else {
        occurredDate = DateTime.now();
      }
      final String occurredAtUtc = occurredDate.toUtc().toIso8601String();

      final int amount = (tx['amount'] as num?)?.toInt().abs() ?? 0;
      if (amount <= 0) return false;

      int? serverWalletId;
      final localWalletId = tx['walletId'] as int?;
      if (localWalletId != null && localWalletId > 0) {
        final walletData = await DatabaseHelper.instance.getWalletById(localWalletId);
        if (walletData != null && walletData['serverId'] != null) {
          serverWalletId = walletData['serverId'] as int;
        }
      }

      final payload = <String, dynamic>{
        'eventId': eventId,
        'amount': amount,
        'type': type,
        'categoryName': categoryName,
        'source': source,
        'bankName': bankName,
        'packageName': packageName,
        'occurredAtUtc': occurredAtUtc,
        'note': note,
      };

      if (serverWalletId != null && serverWalletId > 0) {
        payload['walletId'] = serverWalletId;
      }

      if (familyGroupId != null && familyGroupId > 0) {
        payload['familyGroupId'] = familyGroupId;
      }

      debugPrint("[SyncService] Gửi POST /transactions với eventId: $eventId...");

      final res = await ApiService.instance.createTransaction(payload);

      if (txId != null) {
        await DatabaseHelper.instance.markTransactionSynced(txId);

        final serverId = (res['id'] ?? res['transactionId']) as int?;
        if (serverId != null && serverId > 0) {
          await DatabaseHelper.instance.updateTransactionServerId(txId, serverId);
        }
      }

      debugPrint("[SyncService] Đồng bộ giao dịch $eventId thành công.");
      return true;
    } catch (e) {
      debugPrint("[SyncService] Lỗi khi gửi API đồng bộ giao dịch ($eventId): $e");
      return false;
    }
  }

  Future<void> syncAllPendingTransactions(int userId) async {
    try {
      await syncUnsyncedWallets(userId);

      final unsynced = await DatabaseHelper.instance.getUnsyncedTransactions(userId);
      if (unsynced.isEmpty) return;

      debugPrint("[SyncService] Phát hiện ${unsynced.length} giao dịch chờ đồng bộ cho userId $userId.");
      for (var tx in unsynced) {
        await syncTransaction(tx);
      }
    } catch (e) {
      debugPrint("[SyncService] Lỗi khi duyệt danh sách đồng bộ chờ: $e");
    }
  }
}
