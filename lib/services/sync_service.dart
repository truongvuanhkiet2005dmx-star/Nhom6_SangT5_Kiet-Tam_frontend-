import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'api_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

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
        final initialBalance = (wallet['initialBalance'] as num?)?.toInt() ?? balance;
        final type = wallet['type']?.toString() ?? 'cash';
        final accountNumber = wallet['accountNumber']?.toString();
        final clientId = wallet['clientId']?.toString() ?? DatabaseHelper.instance.generateUuid();

        try {
          final res = await ApiService.instance.createWallet(
            name: name,
            balance: initialBalance,
            type: type,
            accountNumber: accountNumber,
            clientId: clientId,
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
    var eventId = tx['eventId']?.toString();

    if (eventId == null || eventId.isEmpty || eventId.startsWith('tx_')) {
      eventId = DatabaseHelper.instance.generateUuid();
      if (txId != null && txId > 0) {
        final db = await DatabaseHelper.instance.database;
        await db.update('transactions', {'eventId': eventId}, where: 'id = ?', whereArgs: [txId]);
      }
    }

    try {
      final token = await ApiService.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint("[SyncService] Chưa đăng nhập JWT backend. Bỏ qua gửi API cho $eventId (giữ isSynced = 0).");
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final int? familyGroupId = (tx['familyGroupId'] as num?)?.toInt() ?? prefs.getInt('activeFamilyGroupId');

      String type = tx['type']?.toString() ?? (tx['isExpense'] == 1 ? 'expense' : 'income');
      final String? adjustmentDirection = tx['adjustmentDirection']?.toString() ??
          (type == 'adjustment' ? (tx['isExpense'] == 1 ? 'decrease' : 'increase') : null);

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
      var occurredAtUtc = occurredDate.toUtc().toIso8601String();
      if (!occurredAtUtc.endsWith('Z')) {
        occurredAtUtc = '${occurredAtUtc}Z';
      }

      final int amount = (tx['amount'] as num?)?.toInt().abs() ?? 0;
      if (amount <= 0) return false;

      int? serverWalletId;
      final localWalletId = tx['walletId'] as int?;
      final localUserId = tx['userId'] as int?;

      if (localWalletId != null && localWalletId > 0) {
        var walletData = await DatabaseHelper.instance.getWalletById(localWalletId);
        if (walletData != null && walletData['serverId'] != null) {
          serverWalletId = walletData['serverId'] as int;
        } else if (localUserId != null) {
          await syncUnsyncedWallets(localUserId);
          walletData = await DatabaseHelper.instance.getWalletById(localWalletId);
          if (walletData != null && walletData['serverId'] != null) {
            serverWalletId = walletData['serverId'] as int;
          }
        }
      }

      int? serverToWalletId;
      final localToWalletId = tx['toWalletId'] as int?;
      if (localToWalletId != null && localToWalletId > 0) {
        var toWalletData = await DatabaseHelper.instance.getWalletById(localToWalletId);
        if (toWalletData != null && toWalletData['serverId'] != null) {
          serverToWalletId = toWalletData['serverId'] as int;
        } else if (localUserId != null) {
          await syncUnsyncedWallets(localUserId);
          toWalletData = await DatabaseHelper.instance.getWalletById(localToWalletId);
          if (toWalletData != null && toWalletData['serverId'] != null) {
            serverToWalletId = toWalletData['serverId'] as int;
          }
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

      if (adjustmentDirection != null) payload['adjustmentDirection'] = adjustmentDirection;

      if (serverWalletId != null && serverWalletId > 0) {
        payload['walletId'] = serverWalletId;
      }

      if (serverToWalletId != null && serverToWalletId > 0) {
        payload['toWalletId'] = serverToWalletId;
      }

      if (familyGroupId != null && familyGroupId > 0) {
        payload['familyGroupId'] = familyGroupId;
      }

      debugPrint("[SyncService] Gửi POST API (type: $type) với eventId: $eventId...");

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
      debugPrint("[SyncService] Không thể đồng bộ giao dịch ($eventId) với backend: $e. Giữ local isSynced = 0.");
      return false;
    }
  }

  Future<void> pullAndSyncFromBackend(int userId) async {
    if (_isSyncing) {
      debugPrint("[SyncService] Tiến trình đồng bộ đang chạy. Bỏ qua yêu cầu đồng bộ lặp.");
      return;
    }

    _isSyncing = true;
    try {
      final token = await ApiService.instance.getToken();
      if (token == null || token.isEmpty) return;

      // 1. Đồng bộ ví local chưa có serverId
      await syncUnsyncedWallets(userId);

      // 2. Gửi các giao dịch local chờ đồng bộ
      final unsynced = await DatabaseHelper.instance.getUnsyncedTransactions(userId);
      if (unsynced.isNotEmpty) {
        debugPrint("[SyncService] Phát hiện ${unsynced.length} giao dịch chờ đồng bộ.");
        for (var tx in unsynced) {
          await syncTransaction(tx);
        }
      }

      // 3. Tải ví từ Backend về local SQLite (upsert)
      try {
        final remoteWallets = await ApiService.instance.getWallets();
        for (var rw in remoteWallets) {
          if (rw is Map<String, dynamic>) {
            await DatabaseHelper.instance.upsertWalletFromBackend(userId, rw);
          }
        }
      } catch (e) {
        debugPrint("[SyncService] Lỗi kéo danh sách ví từ backend: $e");
      }

      // 4. Tải các giao dịch từ Backend về local SQLite (upsert với phân trang)
      try {
        int page = 1;
        const pageSize = 100;
        bool hasMore = true;
        while (hasMore) {
          final remoteTxs = await ApiService.instance.getTransactions(page: page, pageSize: pageSize);
          if (remoteTxs.isEmpty) {
            hasMore = false;
            break;
          }
          for (var rtx in remoteTxs) {
            if (rtx is Map<String, dynamic>) {
              await DatabaseHelper.instance.upsertTransactionFromBackend(userId, rtx);
            }
          }
          if (remoteTxs.length < pageSize) {
            hasMore = false;
          } else {
            page++;
          }
        }
      } catch (e) {
        debugPrint("[SyncService] Lỗi kéo giao dịch từ backend: $e");
      }
    } catch (e) {
      debugPrint("[SyncService] Lỗi tổng quát khi đồng bộ hai chiều: $e");
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> syncAllPendingTransactions(int userId) async {
    await pullAndSyncFromBackend(userId);
  }
}
