import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants.dart';
import '../database/database_helper.dart';
import 'notification_service.dart';
import 'sync_service.dart';

class AutoTransactionService {
  static final AutoTransactionService instance = AutoTransactionService._();
  AutoTransactionService._();

  static bool _initialized = false;
  static bool _isInitializing = false;
  final Telephony telephony = Telephony.instance;
  final StreamController<bool> onTransactionAdded = StreamController<bool>.broadcast();
  static final Set<int> _processedCache = {};

  void initialize() async {
    if (_initialized || _isInitializing) {
      debugPrint("[AutoTransactionService] Dịch vụ đang khởi tạo hoặc đã khởi tạo trước đó. Bỏ qua.");
      return;
    }
    _isInitializing = true;

    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.sms,
        Permission.phone,
      ].request();

      if (statuses[Permission.sms]!.isGranted) {
        telephony.listenIncomingSms(
          onNewMessage: (SmsMessage message) {
            processSmsContent(message.body ?? '');
          },
          onBackgroundMessage: backgroundMessageHandler,
        );
      }

      bool? isGranted = await NotificationsListener.hasPermission;
      if (isGranted != true) {
        debugPrint("Notification Listener Permission not granted. Opening settings...");
        await NotificationsListener.openPermissionSettings();
      }

      await NotificationsListener.initialize(callbackHandle: notificationCallbackHandle);

      NotificationsListener.receivePort?.listen((evt) {
        handleNotificationEvent(evt);
      });

      _initialized = true;
    } catch (e) {
      _initialized = false;
      debugPrint("Error initializing AutoTransactionService: $e");
    } finally {
      _isInitializing = false;
    }
  }

  void handleNotificationEvent(dynamic evt) {
    String pkg = '';
    String title = '';
    String text = '';
    String message = '';
    String bigText = '';
    String subText = '';
    List<String> textLines = [];

    if (evt is NotificationEvent) {
      pkg = (evt.packageName ?? '').toLowerCase();
      title = evt.title ?? '';
      text = evt.text ?? '';
      message = evt.message ?? '';

      try {
        bigText = (evt as dynamic).bigText?.toString() ?? '';
        subText = (evt as dynamic).subText?.toString() ?? '';
      } catch (_) {}

      if (bigText.isEmpty && evt.raw != null && evt.raw is Map) {
        final rawMap = evt.raw as Map;
        bigText = (rawMap['bigText'] ?? rawMap['big_text'] ?? rawMap['android.bigText'] ?? '').toString();
        subText = (rawMap['subText'] ?? rawMap['sub_text'] ?? rawMap['android.subText'] ?? '').toString();
        if (rawMap['textLines'] is List) {
          textLines = (rawMap['textLines'] as List).map((e) => e.toString()).toList();
        }
      }
    } else if (evt is Map) {
      pkg = (evt['package_name'] ?? evt['packageName'] ?? '').toString().toLowerCase();
      title = (evt['title'] ?? '').toString();
      text = (evt['text'] ?? '').toString();
      message = (evt['message'] ?? '').toString();
      bigText = (evt['bigText'] ?? evt['big_text'] ?? evt['android.bigText'] ?? '').toString();
      subText = (evt['subText'] ?? evt['sub_text'] ?? evt['android.subText'] ?? '').toString();
      if (evt['textLines'] is List) {
        textLines = (evt['textLines'] as List).map((e) => e.toString()).toList();
      }
    } else if (evt is String) {
      message = evt;
    }

    if (pkg.isNotEmpty) {
      bool isAllowed = AppConstants.allowedBankPackages.any((allowed) => pkg.contains(allowed));
      if (!isAllowed && !pkg.contains('sms') && !pkg.contains('messaging') && !pkg.contains('mms')) {
        debugPrint("[AutoTransactionService] Bỏ qua thông báo từ app không thuộc danh sách ngân hàng: $pkg");
        return;
      }
    }

    if (pkg.contains('smart_money') || pkg.contains('example')) {
      return;
    }

    String combinedLines = textLines.join('\n');
    String fullContent = "$title\n$text\n$message\n$bigText\n$subText\n$combinedLines".trim();

    if (fullContent.isNotEmpty) {
      processSmsContent(fullContent, packageName: pkg);
    }
  }

  static Future<void> simulateIncomingSms(String messageBody) async {
    await instance.processSmsContent(messageBody, force: true);
  }

  String? extractAccountNumber(String content) {
    final stkRegex = RegExp(
      r'(?:TK|STK|SDTK|Tai\s*khoan|So\s*TK|acc|account)\s*[:=]?\s*([0-9xX*]{4,16})',
      caseSensitive: false,
    );

    final match = stkRegex.firstMatch(content);
    if (match != null) {
      String stk = match.group(1) ?? '';
      if (stk.isNotEmpty) return stk;
    }

    final bankPrefixRegex = RegExp(
      r'(?:VCB|MB|TCB|BIDV|CTG|VPB|ACB|TPB|STB|EIB|Agribank|Momo|ZaloPay|VietinBank)\s+([0-9]{6,16})',
      caseSensitive: false,
    );
    final bankMatch = bankPrefixRegex.firstMatch(content);
    if (bankMatch != null) {
      String stk = bankMatch.group(1) ?? '';
      if (stk.isNotEmpty) return stk;
    }

    return null;
  }

  Map<String, dynamic>? findMatchingWallet(
      List<Map<String, dynamic>> wallets,
      String content,
      String? extractedStk,
      ) {
    if (wallets.isEmpty) return null;

    String lowerContent = content.toLowerCase();

    if (extractedStk != null && extractedStk.isNotEmpty) {
      String cleanExtracted = extractedStk.replaceAll(RegExp(r'[^\d]'), '');

      for (var wallet in wallets) {
        String? walletAccNum = wallet['accountNumber']?.toString();
        if (walletAccNum != null && walletAccNum.trim().isNotEmpty) {
          String cleanWalletAcc = walletAccNum.replaceAll(RegExp(r'[^\d]'), '');

          if (cleanWalletAcc.isNotEmpty) {
            if (cleanExtracted == cleanWalletAcc ||
                (cleanExtracted.length >= 4 && cleanWalletAcc.endsWith(cleanExtracted)) ||
                (cleanWalletAcc.length >= 4 && cleanExtracted.endsWith(cleanWalletAcc))) {
              return wallet;
            }
          }
        }
      }
    }

    final bankKeywords = {
      'vietinbank': ['vietinbank', 'ctg', 'vietin', 'vietin bank', 'ipay'],
      'mbbank': ['mb', 'mbbank', 'mb bank', 'mcbank'],
      'vcb': ['vcb', 'vietcombank'],
      'tcb': ['tcb', 'techcombank'],
      'bidv': ['bidv'],
      'vpb': ['vpb', 'vpbank', 'vp bank'],
      'agribank': ['agribank', 'agri'],
      'acb': ['acb'],
      'tpb': ['tpb', 'tpbank', 'tp bank'],
      'momo': ['momo'],
      'zalopay': ['zalopay', 'zalo'],
    };

    for (var wallet in wallets) {
      String walletNameLower = (wallet['name'] ?? '').toString().toLowerCase();

      for (var entry in bankKeywords.entries) {
        bool smsHasBank = entry.value.any((kw) => lowerContent.contains(kw));
        bool walletHasBank = entry.value.any((kw) => walletNameLower.contains(kw));

        if (smsHasBank && walletHasBank) {
          return wallet;
        }
      }
    }

    return null;
  }

  // F1 Fix: Đổi processSmsContent trả về Future<bool> thông báo thực tế xem có bóc tách & tạo giao dịch thành công không
  Future<bool> processSmsContent(String content, {bool force = false, String packageName = ''}) async {
    if (!force && (content.contains('SmartMoney') || content.contains('Chi tiêu tự động') || content.contains('Thu nhập tự động'))) {
      return false;
    }

    String lowerContent = content.toLowerCase();

    bool isBankMessage = lowerContent.contains('vnd') ||
        lowerContent.contains('vnđ') ||
        lowerContent.contains('đ') ||
        lowerContent.contains('đồng') ||
        lowerContent.contains('so du') ||
        lowerContent.contains('sodu') ||
        lowerContent.contains('tai khoan') ||
        RegExp(r'\b(?:tk|gd|ps|sd|stk)\b', caseSensitive: false).hasMatch(content);

    if (!isBankMessage) {
      return false;
    }

    int cacheHash = content.trim().hashCode;
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      int now = DateTime.now().millisecondsSinceEpoch;
      int? lastTime = prefs.getInt('dedup_$cacheHash');

      if (lastTime != null && (now - lastTime) < 10000) {
        debugPrint("[AutoTransactionService] Bỏ qua thông báo trùng lặp trong cache: $cacheHash");
        return false;
      }

      await prefs.setInt('dedup_$cacheHash', now);
      _processedCache.add(cacheHash);
      Timer(const Duration(seconds: 10), () {
        _processedCache.remove(cacheHash);
      });
    }

    String? extractedStk = extractAccountNumber(content);

    int? parsedAccountBalance;
    final balanceRegex = RegExp(
      r'(?:so\s*du|sd|sdc|sodu)\s*[:=]?\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)\s*(?:VND|đ|VNĐ|d)',
      caseSensitive: false,
    );
    final balanceMatch = balanceRegex.firstMatch(content);
    if (balanceMatch != null) {
      String rawBalance = balanceMatch.group(1) ?? '0';
      parsedAccountBalance = int.tryParse(rawBalance.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }

    final regex = RegExp(
      r'(?:GD|PS|So tien|chuyen|tru|cong|thanh toan)?\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)\s*(?:VND|đ|VNĐ|d|k\b)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(content);

    if (match != null) {
      String rawMatch = match.group(1) ?? '0';
      bool isExpenseFromSign = rawMatch.contains('-');
      String cleaned = rawMatch.replaceAll(RegExp(r'[^\d]'), '');
      int amount = int.tryParse(cleaned) ?? 0;

      if (amount >= 1000) {
        bool isIncome = rawMatch.contains('+') ||
            lowerContent.contains('giao dịch +') ||
            lowerContent.contains('gd: +') ||
            lowerContent.contains('gd:+') ||
            lowerContent.contains('ps:+') ||
            lowerContent.contains('ps: +') ||
            lowerContent.contains('ck:+') ||
            lowerContent.contains('cộng') ||
            lowerContent.contains('nhận');

        bool isExpense = !isIncome && (
            isExpenseFromSign ||
                lowerContent.contains('-') ||
                lowerContent.contains('trừ') ||
                lowerContent.contains('thanh toan') ||
                lowerContent.contains('chi') ||
                lowerContent.contains('rut tien')
        );

        await _saveAutoTransaction(amount, isExpense, content, parsedAccountBalance, extractedStk, packageName: packageName);
        return true;
      }
    }

    return false;
  }

  Future<void> _saveAutoTransaction(
      int amount,
      bool isExpense,
      String rawContent,
      int? parsedAccountBalance,
      String? extractedStk, {
        String packageName = '',
      }) async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('userId');

    final db = await DatabaseHelper.instance.database;

    if (userId == null) {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null && firebaseUser.email != null && firebaseUser.email!.isNotEmpty) {
        final sqliteUser = await DatabaseHelper.instance.findOrCreateUserByFirebaseUid(
          firebaseUid: firebaseUser.uid,
          email: firebaseUser.email!,
          displayName: firebaseUser.displayName,
        );
        userId = sqliteUser['id'] as int?;
      }

      if (userId == null) {
        final userRows = await db.query('users', orderBy: 'id DESC', limit: 1);
        if (userRows.isNotEmpty) {
          userId = userRows.first['id'] as int?;
        }
      }

      if (userId == null) {
        debugPrint("[AutoTransactionService] Bỏ qua lưu giao dịch tự động vì chưa có người dùng đăng nhập trong CSDL.");
        return;
      }
    }

    final activeUserId = userId;
    List<Map<String, dynamic>> wallets = await DatabaseHelper.instance.getWallets(activeUserId);

    if (wallets.isEmpty) {
      int newWalletId = await db.insert('wallets', {
        'userId': activeUserId,
        'name': 'Ví VietinBank',
        'type': 'bank',
        'balance': parsedAccountBalance ?? 1000000,
        'accountNumber': extractedStk ?? '',
      });
      wallets = [
        {
          'id': newWalletId,
          'userId': activeUserId,
          'name': 'Ví VietinBank',
          'type': 'bank',
          'balance': parsedAccountBalance ?? 1000000,
          'accountNumber': extractedStk ?? '',
        }
      ];
    }

    final matchedWalletCandidate = findMatchingWallet(wallets, rawContent, extractedStk);
    final isExactMatched = matchedWalletCandidate != null;
    final matchedWallet = matchedWalletCandidate ?? wallets.first;

    final walletId = matchedWallet['id'] as int;
    final walletUserId = matchedWallet['userId'] as int? ?? activeUserId;
    final walletName = matchedWallet['name'] as String;
    final currentBalance = matchedWallet['balance'] as int;

    String displayNote = rawContent;
    final ndMatch = RegExp(r'ND:\s*(.*)', caseSensitive: false).firstMatch(rawContent);
    if (ndMatch != null) {
      displayNote = ndMatch.group(1)?.trim() ?? rawContent;
    }

    int insertedTxId = 0;
    int newBalance = 0;
    await db.transaction((txn) async {
      if (isExactMatched && parsedAccountBalance != null) {
        newBalance = parsedAccountBalance;
      } else {
        newBalance = isExpense ? currentBalance - amount : currentBalance + amount;
      }

      await txn.update(
        'wallets',
        {'balance': newBalance},
        where: 'id = ?',
        whereArgs: [walletId],
      );

      insertedTxId = await txn.insert(
        'transactions',
        {
          'userId': walletUserId,
          'walletId': walletId,
          'toWalletId': null,
          'amount': amount,
          'type': isExpense ? 'expense' : 'income',
          'isExpense': isExpense ? 1 : 0,
          'categoryName': isExpense ? 'Hóa đơn' : 'Tiền lương',
          'date': DateTime.now().toIso8601String(),
          'note': 'Auto: $displayNote',
          'isSynced': 0,
          'eventId': 'tx_0',
        },
      );

      await txn.update(
        'transactions',
        {'eventId': 'tx_$insertedTxId'},
        where: 'id = ?',
        whereArgs: [insertedTxId],
      );
    });

    onTransactionAdded.add(true);

    try {
      String typeText = isExpense ? 'Chi tiêu' : 'Thu nhập';
      String formattedAmount = _formatMoney(amount);
      await NotificationService.instance.showNotification(
        'SmartMoney - $typeText tự động',
        '$typeText +$formattedAmount đ tại ví "$walletName".',
      );
    } catch (e) {
      debugPrint("Notification error in background: $e");
    }

    try {
      final txData = {
        'id': insertedTxId,
        'eventId': 'tx_$insertedTxId',
        'amount': amount,
        'type': isExpense ? 'expense' : 'income',
        'walletName': walletName,
        'bankName': walletName,
        'packageName': packageName,
        'categoryName': isExpense ? 'Hóa đơn' : 'Tiền lương',
        'date': DateTime.now().toIso8601String(),
        'note': 'Auto: $displayNote',
      };
      await SyncService.instance.syncTransaction(txData);
    } catch (e) {
      debugPrint("Auto background sync error: $e");
    }
  }

  static String _formatMoney(int amount) {
    final text = amount.toString();
    String result = '';
    for (int i = text.length - 1, count = 1; i >= 0; i--, count++) {
      result = text[i] + result;
      if (count % 3 == 0 && i != 0) {
        result = ',$result';
      }
    }
    return result;
  }
}

@pragma('vm:entry-point')
void notificationCallbackHandle(NotificationEvent evt) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 3));
  } catch (_) {}
  try {
    await NotificationService.instance.initializeForBackground();
  } catch (_) {}
  AutoTransactionService.instance.handleNotificationEvent(evt);
}

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 3));
  } catch (_) {}
  try {
    await NotificationService.instance.initializeForBackground();
  } catch (_) {}
  if (message.body != null && message.body!.isNotEmpty) {
    await AutoTransactionService.instance.processSmsContent(message.body!);
  }
}