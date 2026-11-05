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
import 'bank_message_parser.dart';
import 'personal_debt_parser.dart';
import 'notification_service.dart';
import 'sync_service.dart';

class AutoTransactionService {
  static final AutoTransactionService instance = AutoTransactionService._();
  AutoTransactionService._();

  static bool _initialized = false;
  static bool _isInitializing = false;
  StreamSubscription<dynamic>? _notificationSub;
  final Telephony telephony = Telephony.instance;
  final StreamController<bool> onTransactionAdded = StreamController<bool>.broadcast();
  static final Set<int> _processedCache = {};

  void initialize() async {
    if (_initialized || _isInitializing) {
      debugPrint("[AutoTransactionService] Dịch vụ đang khởi tạo hoặc đã khởi tạo trước đó. Bỏ qua.");
      return;
    }
    _isInitializing = true;
    final swInit = Stopwatch()..start();

    try {
      final smsStatus = await Permission.sms.status;

      if (smsStatus.isGranted) {
        telephony.listenIncomingSms(
          onNewMessage: (SmsMessage message) {
            processSmsContent(message.body ?? '');
          },
          onBackgroundMessage: backgroundMessageHandler,
        );
      }

      // 1. Call NotificationsListener.initialize FIRST
      await NotificationsListener.initialize(
        callbackHandle: notificationCallbackHandle,
      );

      // 2. Register receivePort listener SECOND (safely cancel old subscription first)
      await _notificationSub?.cancel();
      _notificationSub = NotificationsListener.receivePort?.listen((evt) {
        handleNotificationEvent(evt);
      });

      // 3. Check permission and call startService THIRD
      bool? isGranted = await NotificationsListener.hasPermission;
      if (isGranted == true) {
        await NotificationsListener.startService();
      } else {
        debugPrint("[AutoTransactionService] Notification Listener Permission not granted.");
      }

      _initialized = true;
    } catch (e) {
      _initialized = false;
      debugPrint("Error initializing AutoTransactionService: $e");
    } finally {
      swInit.stop();
      debugPrint("[Performance] AutoTransactionService.initialize completed in ${swInit.elapsedMilliseconds}ms");
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
      r'(?:TK|STK|SDTK|Tai\s*khoan|So\s*TK|acc|account|TK VCB)\s*[:=]?\s*([0-9xX*]{6,16})',
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

  String? extractBankRefId(String content) {
    final refRegex = RegExp(
      r'(?:REQ_ID|Ref|Mã\s*GD|Ma\s*GD|RefNo|TraceNo)\s*[:=]?\s*([A-Za-z0-9_.-]{6,32})',
      caseSensitive: false,
    );
    final match = refRegex.firstMatch(content);
    if (match != null) {
      return match.group(1)?.trim();
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
                (cleanExtracted.length >= 6 && cleanWalletAcc.endsWith(cleanExtracted)) ||
                (cleanWalletAcc.length >= 6 && cleanExtracted.endsWith(cleanWalletAcc))) {
              return wallet;
            }
          }
        }
      }
    }

    final bankKeywords = {
      'vietcombank': ['vietcombank', 'vcb'],
      'vietinbank': ['vietinbank', 'ctg', 'vietin', 'vietin bank', 'ipay'],
      'mbbank': ['mb', 'mbbank', 'mb bank', 'mcbank'],
      'techcombank': ['tcb', 'techcombank'],
      'bidv': ['bidv'],
      'vpbank': ['vpb', 'vpbank', 'vp bank'],
      'agribank': ['agribank', 'agri'],
      'acb': ['acb'],
      'tpbank': ['tpb', 'tpbank', 'tp bank'],
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

  Future<bool> processSmsContent(String content, {bool force = false, String packageName = ''}) async {
    final sw = Stopwatch()..start();
    if (!force && (content.contains('SmartMoney') || content.contains('Chi tiêu tự động') || content.contains('Thu nhập tự động'))) {
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

    final parsedBank = BankMessageParser.parse(content, packageName: packageName);
    if (parsedBank != null) {
      await _saveParsedTransaction(parsedBank, rawContent: content, packageName: packageName);
      sw.stop();
      debugPrint("[Performance] AutoTransactionService.processSmsContent (Bank) completed in ${sw.elapsedMilliseconds}ms");
      return true;
    }

    // If not a bank SMS and packageName is empty (incoming Telephony SMS), check for personal debt:
    if (packageName.isEmpty) {
      final parsedDebt = PersonalDebtParser.parse(content);
      if (parsedDebt != null) {
        await _handlePersonalDebtConfirmation(parsedDebt);
        sw.stop();
        debugPrint("[Performance] AutoTransactionService.processSmsContent (Debt) completed in ${sw.elapsedMilliseconds}ms");
        return true;
      }
    }

    debugPrint("[AutoTransactionService] Bỏ qua SMS/thông báo không khớp cấu trúc ngân hàng hoặc nợ cá nhân: $content");
    return false;
  }

  Future<void> _handlePersonalDebtConfirmation(ParsedPersonalDebtMessage debt) async {
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (userId != null) {
      final existingTx = await db.query(
        'transactions',
        where: 'userId = ? AND note LIKE ?',
        whereArgs: [userId, '%${debt.dedupKey}%'],
        limit: 1,
      );

      if (existingTx.isNotEmpty) {
        debugPrint("[AutoTransactionService] Bỏ qua SMS nợ cá nhân do đã xác nhận trước đó: ${debt.dedupKey}");
        return;
      }
    }

    // Emit confirmation notification without modifying SQLite balances or auto-inserting
    try {
      String typeText = debt.isExpense ? 'Khoản nợ/chi đề xuất' : 'Khoản thu nợ đề xuất';
      String formattedAmount = _formatMoney(debt.amount);
      await NotificationService.instance.showNotification(
        'SmartMoney - $typeText',
        'SMS: "${debt.note}" ($formattedAmount đ). Mở app để xác nhận ghi nhận ví!',
      );
    } catch (e) {
      debugPrint("Error showing personal debt notification: $e");
    }
  }

  Future<void> confirmPersonalDebtTransaction(
    ParsedPersonalDebtMessage debt, {
    required int walletId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;

    final db = await DatabaseHelper.instance.database;
    final wallet = await DatabaseHelper.instance.getWalletById(walletId);
    if (wallet == null) return;

    final currentBalance = wallet['balance'] as int;
    final walletName = wallet['name'] as String;
    final activeFamilyGroupId = prefs.getInt('activeFamilyGroupId');
    final generatedEventId = DatabaseHelper.instance.generateUuid();

    final newBalance = debt.isExpense ? (currentBalance - debt.amount) : (currentBalance + debt.amount);

    int insertedTxId = 0;
    await db.transaction((txn) async {
      final dupCheck = await txn.query(
        'transactions',
        where: 'userId = ? AND note LIKE ?',
        whereArgs: [userId, '%${debt.dedupKey}%'],
        limit: 1,
      );

      if (dupCheck.isNotEmpty) {
        debugPrint("[AutoTransactionService] Bỏ qua xác nhận vì giao dịch nợ cá nhân đã tồn tại: ${debt.dedupKey}");
        return;
      }

      await txn.update(
        'wallets',
        {'balance': newBalance},
        where: 'id = ? AND userId = ?',
        whereArgs: [walletId, userId],
      );

      insertedTxId = await txn.insert(
        'transactions',
        {
          'userId': userId,
          'walletId': walletId,
          'toWalletId': null,
          'familyGroupId': activeFamilyGroupId,
          'amount': debt.amount,
          'type': debt.isExpense ? 'expense' : 'income',
          'isExpense': debt.isExpense ? 1 : 0,
          'categoryName': debt.suggestedCategory,
          'date': DateTime.now().toIso8601String(),
          'note': 'Auto [${debt.dedupKey}]: ${debt.note}',
          'isSynced': 0,
          'eventId': generatedEventId,
        },
      );
    });

    if (insertedTxId == 0) return;

    onTransactionAdded.add(true);

    unawaited(Future.microtask(() async {
      try {
        final txData = {
          'id': insertedTxId,
          'eventId': generatedEventId,
          'userId': userId,
          'amount': debt.amount,
          'type': debt.isExpense ? 'expense' : 'income',
          'walletId': walletId,
          'walletName': walletName,
          'bankName': walletName,
          'packageName': '',
          'categoryName': debt.suggestedCategory,
          'date': DateTime.now().toIso8601String(),
          'note': 'Auto [${debt.dedupKey}]: ${debt.note}',
        };
        await SyncService.instance.syncTransaction(txData);
      } catch (e) {
        debugPrint("Personal debt background sync error: $e");
      }
    }));
  }

  Future<void> _saveParsedTransaction(
      ParsedBankMessage parsed, {
        required String rawContent,
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
        debugPrint("[AutoTransactionService] Bỏ qua lưu giao dịch tự động vì chưa có người dùng đăng nhập.");
        return;
      }
    }

    final activeUserId = userId;
    final detectedBankName = parsed.bankName;
    final amount = parsed.amount;
    final isExpense = parsed.isExpense;
    final parsedAccountBalance = parsed.endingBalance;
    final extractedStk = parsed.accountNumber;
    final refId = parsed.refId;

    // Stable Dedup Key based strictly on transaction reference or normalized message hash
    final now = DateTime.now();
    final rawHash = rawContent.trim().replaceAll(RegExp(r'\s+'), ' ').hashCode.abs();
    final dedupKey = (refId != null && refId.isNotEmpty)
        ? "REF_$refId"
        : "HASH_${detectedBankName}_${extractedStk ?? ''}_${amount}_${isExpense}_$rawHash";

    List<Map<String, dynamic>> wallets = await DatabaseHelper.instance.getWallets(activeUserId);
    Map<String, dynamic>? matchedWallet = findMatchingWallet(wallets, rawContent, extractedStk);
    bool isNewWallet = false;

    if (matchedWallet == null) {
      isNewWallet = true;
      final newClientId = DatabaseHelper.instance.generateUuid();
      final initBal = parsedAccountBalance != null
          ? (isExpense ? parsedAccountBalance + amount : parsedAccountBalance - amount)
          : 0;
      final finalBal = parsedAccountBalance ?? (isExpense ? 0 : amount);
      final walletTitle = 'Ví $detectedBankName';

      int newWalletId = await db.insert('wallets', {
        'userId': activeUserId,
        'name': walletTitle,
        'type': 'bank',
        'balance': finalBal,
        'initialBalance': initBal,
        'accountNumber': extractedStk ?? '',
        'clientId': newClientId,
      });

      final createdWallet = await DatabaseHelper.instance.getWalletById(newWalletId);
      matchedWallet = createdWallet ?? {
        'id': newWalletId,
        'userId': activeUserId,
        'name': walletTitle,
        'type': 'bank',
        'balance': finalBal,
        'initialBalance': initBal,
        'accountNumber': extractedStk ?? '',
        'clientId': newClientId,
      };
    }

    final walletId = matchedWallet['id'] as int;
    final walletUserId = matchedWallet['userId'] as int? ?? activeUserId;
    final walletName = matchedWallet['name'] as String;
    final currentBalance = matchedWallet['balance'] as int;

    // Out-of-order / late-arriving message check
    bool isLateArrivingMessage = false;
    if (!isNewWallet && parsedAccountBalance != null) {
      final latestTxRes = await db.query(
        'transactions',
        where: 'walletId = ?',
        orderBy: 'date DESC, id DESC',
        limit: 1,
      );

      if (latestTxRes.isNotEmpty) {
        final latestTxDateStr = latestTxRes.first['date']?.toString();
        if (latestTxDateStr != null) {
          final latestTxDate = DateTime.tryParse(latestTxDateStr);
          if (latestTxDate != null && now.isBefore(latestTxDate.subtract(const Duration(minutes: 10)))) {
            isLateArrivingMessage = true;
            debugPrint("[AutoTransactionService] Cảnh báo: Thông báo trễ/cũ hơn mốc thời gian đã ghi nhận. Bỏ qua cập nhật SDC lùi.");
          }
        }
      }
    }

    String displayNote = parsed.displayNote ?? rawContent;
    final generatedEventId = DatabaseHelper.instance.generateUuid();

    // Calculate expected balance & audit adjustment ONLY for existing wallets and non-late messages
    final expectedBalanceAfterTx = isExpense ? (currentBalance - amount) : (currentBalance + amount);
    int? adjustmentDelta;
    if (!isNewWallet && !isLateArrivingMessage && parsedAccountBalance != null && currentBalance > 0 && parsedAccountBalance != expectedBalanceAfterTx) {
      adjustmentDelta = parsedAccountBalance - expectedBalanceAfterTx;
    }

    int insertedTxId = 0;
    int finalWalletBalance = (!isLateArrivingMessage && parsedAccountBalance != null)
        ? parsedAccountBalance
        : (isNewWallet ? (isExpense ? 0 : amount) : expectedBalanceAfterTx);

    bool isDuplicate = false;
    await db.transaction((txn) async {
      final dupCheck = await txn.query(
        'transactions',
        where: 'userId = ? AND note LIKE ?',
        whereArgs: [activeUserId, '%$dedupKey%'],
        limit: 1,
      );

      if (dupCheck.isNotEmpty) {
        isDuplicate = true;
        debugPrint("[AutoTransactionService] Bỏ qua vì phát hiện giao dịch trùng lặp trong SQLite: $dedupKey");
        return;
      }

      if (adjustmentDelta != null && adjustmentDelta != 0) {
        final adjEventId = DatabaseHelper.instance.generateUuid();
        final isAdjDecrease = adjustmentDelta < 0;
        final adjAmount = adjustmentDelta.abs();

        await txn.insert(
          'transactions',
          {
            'userId': walletUserId,
            'walletId': walletId,
            'toWalletId': null,
            'amount': adjAmount,
            'type': 'adjustment',
            'adjustmentDirection': isAdjDecrease ? 'decrease' : 'increase',
            'isExpense': isAdjDecrease ? 1 : 0,
            'categoryName': 'Sửa số dư',
            'date': DateTime.now().toIso8601String(),
            'note': 'Auto Audit: Điều chỉnh cân bằng số dư với ngân hàng ($dedupKey)',
            'isSynced': 0,
            'eventId': adjEventId,
          },
        );
      }

      await txn.update(
        'wallets',
        {'balance': finalWalletBalance},
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
          'note': 'Auto [$dedupKey]: $displayNote',
          'isSynced': 0,
          'eventId': generatedEventId,
        },
      );
    });

    if (isDuplicate) return;

    onTransactionAdded.add(true);

    try {
      String typeText = isExpense ? 'Chi tiêu' : 'Thu nhập';
      String formattedAmount = _formatMoney(amount);
      await NotificationService.instance.showNotification(
        'SmartMoney - $typeText tự động',
        'Đã ghi nhận $typeText ${isExpense ? "-" : "+"}$formattedAmount đ tại ví "$walletName".',
      );
    } catch (e) {
      debugPrint("Notification error in background: $e");
    }

    // Unawaited network sync on main isolate event loop so notification listener completes immediately
    unawaited(Future.microtask(() async {
      try {
        await SyncService.instance.syncUnsyncedWallets(walletUserId);
        final freshWallet = await DatabaseHelper.instance.getWalletById(walletId);
        final serverWalletId = (freshWallet != null ? freshWallet['serverId'] : null) as int?;

        final txData = {
          'id': insertedTxId,
          'eventId': generatedEventId,
          'amount': amount,
          'type': isExpense ? 'expense' : 'income',
          'walletId': serverWalletId ?? walletId,
          'walletName': walletName,
          'bankName': walletName,
          'packageName': packageName,
          'categoryName': isExpense ? 'Hóa đơn' : 'Tiền lương',
          'date': DateTime.now().toIso8601String(),
          'note': 'Auto [$dedupKey]: $displayNote',
        };
        await SyncService.instance.syncTransaction(txData);
      } catch (e) {
        debugPrint("Auto background sync error: $e");
      }
    }));
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
