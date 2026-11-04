import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Top-level isolate entry point for PBKDF2 background calculation
String _pbkdf2Isolate(Map<String, dynamic> params) {
  final password = params['password'] as String;
  final saltString = params['salt'] as String;
  final iterations = params['iterations'] as int? ?? 100000;
  return DatabaseHelper.instance.pbkdf2HmacSha256(password, saltString, iterations: iterations);
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smart_money_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final sw = Stopwatch()..start();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 12,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
    sw.stop();
    debugPrint("[Performance] DatabaseHelper._initDB completed in ${sw.elapsedMilliseconds}ms");
    return db;
  }

  String generateRandomSalt([int length = 16]) {
    final Random rng = Random.secure();
    final List<int> values = List<int>.generate(length, (i) => rng.nextInt(256));
    return base64Url.encode(values);
  }

  String generateUuid() {
    final Random rng = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 1

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  String pbkdf2HmacSha256(String password, String saltString, {int iterations = 100000}) {
    final List<int> passwordBytes = utf8.encode(password);
    final List<int> saltBytes = utf8.encode(saltString);

    final hmac = Hmac(sha256, passwordBytes);

    List<int> block1Salt = List<int>.from(saltBytes)..addAll([0, 0, 0, 1]);
    List<int> u = hmac.convert(block1Salt).bytes;
    List<int> result = List<int>.from(u);

    for (int i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }

    return base64Url.encode(result);
  }

  Future<String> hashPasswordAsync(String password, String saltString, {int iterations = 100000}) async {
    try {
      return await compute(_pbkdf2Isolate, {
        'password': password,
        'salt': saltString,
        'iterations': iterations,
      });
    } catch (_) {
      return pbkdf2HmacSha256(password, saltString, iterations: iterations);
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password TEXT,
        firebaseUid TEXT UNIQUE,
        salt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serverId INTEGER,
        clientId TEXT,
        userId INTEGER NOT NULL,
        name TEXT NOT NULL,
        balance INTEGER NOT NULL DEFAULT 0,
        initialBalance INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL,
        accountNumber TEXT,
        FOREIGN KEY (userId) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_wallets_user_clientId ON wallets(userId, clientId) WHERE clientId IS NOT NULL;
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serverId INTEGER,
        userId INTEGER NOT NULL,
        walletId INTEGER,
        toWalletId INTEGER,
        familyGroupId INTEGER,
        amount INTEGER NOT NULL,
        type TEXT NOT NULL,
        adjustmentDirection TEXT,
        isExpense INTEGER NOT NULL,
        categoryName TEXT NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        isSynced INTEGER NOT NULL DEFAULT 0,
        eventId TEXT,
        FOREIGN KEY (userId) REFERENCES users(id),
        FOREIGN KEY (walletId) REFERENCES wallets(id),
        FOREIGN KEY (toWalletId) REFERENCES wallets(id)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_eventId ON transactions(eventId) WHERE eventId IS NOT NULL;
    ''');

    await db.execute('''
      CREATE TABLE savings_goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        name TEXT NOT NULL,
        targetAmount INTEGER NOT NULL,
        currentAmount INTEGER NOT NULL DEFAULT 0,
        colorHex TEXT,
        date TEXT,
        FOREIGN KEY (userId) REFERENCES users(id)
      )
    ''');
  }

  Future<void> _onUpgrade(
      Database db,
      int oldVersion,
      int newVersion,
      ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE wallets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          name TEXT NOT NULL,
          balance INTEGER NOT NULL DEFAULT 0,
          type TEXT NOT NULL
        )
      ''');

      await db.execute('''
        ALTER TABLE transactions
        ADD COLUMN userId INTEGER NOT NULL DEFAULT 0
      ''');

      await db.execute('''
        ALTER TABLE transactions
        ADD COLUMN walletId INTEGER
      ''');

      await db.execute('''
        ALTER TABLE transactions
        ADD COLUMN toWalletId INTEGER
      ''');

      await db.execute('''
        ALTER TABLE transactions
        ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'
      ''');
    }

    if (oldVersion < 3) {
      try {
        await db.execute('''
          ALTER TABLE wallets
          ADD COLUMN accountNumber TEXT
        ''');
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS savings_goals (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          name TEXT NOT NULL,
          targetAmount INTEGER NOT NULL,
          currentAmount INTEGER NOT NULL DEFAULT 0,
          colorHex TEXT,
          date TEXT,
          FOREIGN KEY (userId) REFERENCES users(id)
        )
      ''');
    }

    if (oldVersion < 4) {
      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN isSynced INTEGER NOT NULL DEFAULT 0
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN eventId TEXT
        ''');
      } catch (_) {}
    }

    if (oldVersion < 5) {
      try {
        await db.execute('''
          ALTER TABLE users
          ADD COLUMN firebaseUid TEXT
        ''');
      } catch (_) {}

      try {
        await db.execute("UPDATE users SET firebaseUid = NULL WHERE firebaseUid = '' OR firebaseUid = 'null'");
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_users_firebaseUid ON users(firebaseUid) WHERE firebaseUid IS NOT NULL
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          ALTER TABLE users
          ADD COLUMN salt TEXT
        ''');
      } catch (_) {}
    }

    if (oldVersion < 6) {
      try {
        await db.execute('''
          ALTER TABLE wallets
          ADD COLUMN serverId INTEGER
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN serverId INTEGER
        ''');
      } catch (_) {}
    }

    if (oldVersion < 7) {
      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN eventId TEXT
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN serverId INTEGER
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          ALTER TABLE wallets
          ADD COLUMN serverId INTEGER
        ''');
      } catch (_) {}
    }

    if (oldVersion < 8) {
      try {
        final rowsWithoutEventId = await db.query(
          'transactions',
          where: "eventId IS NULL OR eventId = '' OR eventId = 'tx_0' OR eventId LIKE 'tx_%'",
        );
        for (final row in rowsWithoutEventId) {
          final id = row['id'] as int;
          final newUuid = generateUuid();
          await db.update(
            'transactions',
            {'eventId': newUuid},
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_eventId ON transactions(eventId) WHERE eventId IS NOT NULL
        ''');
      } catch (e) {
        debugPrint("[DatabaseHelper] Migration v8 warning: $e");
      }
    }

    if (oldVersion < 9) {
      try {
        await db.execute('''
          ALTER TABLE wallets
          ADD COLUMN clientId TEXT
        ''');
      } catch (_) {}

      try {
        final walletsWithoutClientId = await db.query(
          'wallets',
          where: "clientId IS NULL OR clientId = ''",
        );
        for (final row in walletsWithoutClientId) {
          final id = row['id'] as int;
          final newClientId = generateUuid();
          await db.update(
            'wallets',
            {'clientId': newClientId},
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_wallets_user_clientId ON wallets(userId, clientId) WHERE clientId IS NOT NULL
        ''');
      } catch (e) {
        debugPrint("[DatabaseHelper] Migration v9 warning: $e");
      }
    }

    if (oldVersion < 10) {
      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN adjustmentDirection TEXT
        ''');
      } catch (e) {
        debugPrint("[DatabaseHelper] Migration v10 warning: $e");
      }
    }

    if (oldVersion < 11) {
      final swV11 = Stopwatch()..start();
      try {
        await db.execute('''
          ALTER TABLE wallets
          ADD COLUMN initialBalance INTEGER NOT NULL DEFAULT 0
        ''');

        final sourceEffects = await db.rawQuery('''
          SELECT walletId AS wId,
                 SUM(CASE
                       WHEN type = 'income' THEN ABS(amount)
                       WHEN type = 'expense' THEN -ABS(amount)
                       WHEN type = 'transfer' THEN -ABS(amount)
                       WHEN type = 'adjustment' AND (adjustmentDirection = 'increase' OR isExpense = 0) THEN ABS(amount)
                       WHEN type = 'adjustment' THEN -ABS(amount)
                       ELSE 0
                     END) AS effect
          FROM transactions
          WHERE walletId IS NOT NULL
          GROUP BY walletId
        ''');

        final targetEffects = await db.rawQuery('''
          SELECT toWalletId AS wId,
                 SUM(ABS(amount)) AS effect
          FROM transactions
          WHERE type = 'transfer' AND toWalletId IS NOT NULL
          GROUP BY toWalletId
        ''');

        final Map<int, int> walletEffects = {};
        for (var row in sourceEffects) {
          final wId = row['wId'] as int?;
          final effect = (row['effect'] as num?)?.toInt() ?? 0;
          if (wId != null) walletEffects[wId] = (walletEffects[wId] ?? 0) + effect;
        }
        for (var row in targetEffects) {
          final wId = row['wId'] as int?;
          final effect = (row['effect'] as num?)?.toInt() ?? 0;
          if (wId != null) walletEffects[wId] = (walletEffects[wId] ?? 0) + effect;
        }

        final allWallets = await db.query('wallets');
        for (final wallet in allWallets) {
          final wId = wallet['id'] as int;
          final curBal = (wallet['balance'] as num?)?.toInt() ?? 0;
          final totalEffect = walletEffects[wId] ?? 0;
          final calculatedInitial = curBal - totalEffect;

          await db.update(
            'wallets',
            {'initialBalance': calculatedInitial},
            where: 'id = ?',
            whereArgs: [wId],
          );
        }
      } catch (e) {
        debugPrint("[DatabaseHelper] Migration v11 warning: $e");
      }
      swV11.stop();
      debugPrint("[Performance] DatabaseHelper Migration v11 completed in ${swV11.elapsedMilliseconds}ms");
    }

    if (oldVersion < 12) {
      try {
        await db.execute('''
          ALTER TABLE transactions
          ADD COLUMN familyGroupId INTEGER
        ''');
      } catch (e) {
        debugPrint("[DatabaseHelper] Migration v12 warning: $e");
      }
    }
  }

  Future<int> registerUser(
      String username,
      String password,
      ) async {
    final db = await instance.database;
    final salt = generateRandomSalt();
    final hashedPassword = await hashPasswordAsync(password, salt);

    final userId = await db.insert(
      'users',
      {
        'username': username,
        'password': hashedPassword,
        'salt': salt,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await db.insert('wallets', {
      'userId': userId,
      'name': 'Ví tiền mặt',
      'balance': 0,
      'initialBalance': 0,
      'type': 'cash',
      'accountNumber': '',
      'clientId': generateUuid(),
    });

    return userId;
  }

  Future<Map<String, dynamic>?> loginUser(
      String username,
      String password,
      ) async {
    final db = await instance.database;

    final userRows = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (userRows.isEmpty) {
      return null;
    }

    final user = userRows.first;
    final storedPassword = user['password']?.toString();
    final storedSalt = user['salt']?.toString();
    final userId = user['id'] as int;

    if (storedSalt != null && storedSalt.isNotEmpty && storedPassword != null) {
      final hashedCandidate = await hashPasswordAsync(password, storedSalt);
      if (hashedCandidate == storedPassword) {
        return user;
      }
    }

    final sha256Candidate = sha256.convert(utf8.encode(password)).toString();
    if (storedPassword == sha256Candidate) {
      final newSalt = generateRandomSalt();
      final newHashedPassword = await hashPasswordAsync(password, newSalt);

      await db.update(
        'users',
        {
          'password': newHashedPassword,
          'salt': newSalt,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      final updatedUser = await getUserById(userId);
      return updatedUser ?? user;
    }

    return null;
  }

  Future<Map<String, dynamic>> findOrCreateUserByFirebaseUid({
    required String firebaseUid,
    required String email,
    String? displayName,
  }) async {
    final db = await instance.database;

    var result = await db.query(
      'users',
      where: 'firebaseUid = ?',
      whereArgs: [firebaseUid],
      limit: 1,
    );

    int userId;
    if (result.isNotEmpty) {
      userId = result.first['id'] as int;
      if (result.first['username'] != email) {
        await db.update(
          'users',
          {'username': email},
          where: 'id = ?',
          whereArgs: [userId],
        );
      }
    } else {
      final emailResult = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [email],
        limit: 1,
      );

      if (emailResult.isNotEmpty) {
        userId = emailResult.first['id'] as int;
        await db.update(
          'users',
          {'firebaseUid': firebaseUid},
          where: 'id = ?',
          whereArgs: [userId],
        );
      } else {
        userId = await db.insert('users', {
          'username': email,
          'firebaseUid': firebaseUid,
          'password': null,
          'salt': null,
        });
      }
    }

    return {
      'id': userId,
      'username': email,
      'firebaseUid': firebaseUid,
    };
  }

  Future<Map<String, dynamic>> findOrCreateUserByEmail({
    required String email,
    String? displayName,
  }) async {
    final db = await instance.database;
    final normalizedEmail = email.trim().toLowerCase();

    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [normalizedEmail],
      limit: 1,
    );

    int userId;
    if (result.isNotEmpty) {
      return result.first;
    } else {
      userId = await db.insert('users', {
        'username': normalizedEmail,
        'firebaseUid': null,
        'password': null,
        'salt': null,
      });
    }

    final user = await getUserById(userId);
    return user ?? {
      'id': userId,
      'username': normalizedEmail,
    };
  }

  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final db = await instance.database;

    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<int> insertWallet(
      Map<String, dynamic> wallet,
      ) async {
    final db = await instance.database;
    final walletMap = Map<String, dynamic>.from(wallet);

    if (walletMap['clientId'] == null || walletMap['clientId'].toString().isEmpty) {
      walletMap['clientId'] = generateUuid();
    }

    if (!walletMap.containsKey('initialBalance')) {
      walletMap['initialBalance'] = walletMap['balance'] ?? 0;
    }

    return await db.insert(
      'wallets',
      walletMap,
    );
  }

  Future<List<Map<String, dynamic>>> getWallets(
      int userId,
      ) async {
    final db = await instance.database;

    return await db.query(
      'wallets',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
  }

  Future<Map<String, dynamic>?> getWalletById(
      int walletId,
      ) async {
    final db = await instance.database;

    final result = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [walletId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  Future<int> updateWalletBalance(
      int walletId,
      int newBalance,
      ) async {
    final db = await instance.database;

    return await db.update(
      'wallets',
      {
        'balance': newBalance,
      },
      where: 'id = ?',
      whereArgs: [walletId],
    );
  }

  Future<int> updateWallet(
      int walletId,
      Map<String, dynamic> walletData,
      ) async {
    final db = await instance.database;

    return await db.update(
      'wallets',
      walletData,
      where: 'id = ?',
      whereArgs: [walletId],
    );
  }

  Future<int> deleteWallet(
      int walletId,
      ) async {
    final db = await instance.database;

    return await db.delete(
      'wallets',
      where: 'id = ?',
      whereArgs: [walletId],
    );
  }

  Future<int> insertSavingsGoal(
      Map<String, dynamic> goal,
      ) async {
    final db = await instance.database;

    return await db.insert(
      'savings_goals',
      goal,
    );
  }

  Future<List<Map<String, dynamic>>> getSavingsGoals(
      int userId,
      ) async {
    final db = await instance.database;

    return await db.query(
      'savings_goals',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateSavingsGoalAmount(
      int goalId,
      int newCurrentAmount,
      ) async {
    final db = await instance.database;

    return await db.update(
      'savings_goals',
      {
        'currentAmount': newCurrentAmount,
      },
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  Future<int> deleteSavingsGoal(
      int goalId,
      ) async {
    final db = await instance.database;

    return await db.delete(
      'savings_goals',
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  Future<int> insertTransaction(
      Map<String, dynamic> transaction,
      ) async {
    final db = await instance.database;
    final txMap = Map<String, dynamic>.from(transaction);

    if (txMap['eventId'] == null || txMap['eventId'].toString().isEmpty) {
      txMap['eventId'] = generateUuid();
    }

    final id = await db.insert(
      'transactions',
      txMap,
    );

    return id;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedTransactions(int userId) async {
    final db = await instance.database;
    final results = await db.rawQuery('''
      SELECT t.*, w.name AS walletName
      FROM transactions t
      LEFT JOIN wallets w ON t.walletId = w.id
      WHERE t.userId = ? AND (t.isSynced IS NULL OR t.isSynced = 0)
      ORDER BY t.id ASC
    ''', [userId]);

    return results;
  }

  Future<void> markTransactionSynced(int id) async {
    final db = await instance.database;
    await db.update(
      'transactions',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllTransactions(
      int userId,
      ) async {
    final db = await instance.database;

    return await db.query(
      'transactions',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionsByDate(
      int userId,
      String date,
      ) async {
    final db = await instance.database;

    return await db.query(
      'transactions',
      where: 'userId = ? AND date LIKE ?',
      whereArgs: [userId, '$date%'],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionsByType(
      int userId,
      String type,
      ) async {
    final db = await instance.database;

    return await db.query(
      'transactions',
      where: 'userId = ? AND type = ?',
      whereArgs: [userId, type],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<int> getTotalBalance(
      int userId,
      ) async {
    final db = await instance.database;

    final result = await db.rawQuery('''
      SELECT SUM(balance) AS total
      FROM wallets
      WHERE userId = ?
    ''', [userId]);

    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getTotalIncome(
      int userId,
      ) async {
    final db = await instance.database;

    final result = await db.rawQuery('''
      SELECT SUM(amount) AS total
      FROM transactions
      WHERE userId = ?
      AND type = 'income'
    ''', [userId]);

    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getTotalExpense(
      int userId,
      ) async {
    final db = await instance.database;

    final result = await db.rawQuery('''
      SELECT SUM(amount) AS total
      FROM transactions
      WHERE userId = ?
      AND type = 'expense'
    ''', [userId]);

    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getMonthIncome(int userId, int year, int month) async {
    final db = await instance.database;
    final monthStr = month < 10 ? '0$month' : '$month';
    final pattern = '$year-$monthStr%';

    final result = await db.rawQuery('''
      SELECT SUM(amount) AS total
      FROM transactions
      WHERE userId = ?
      AND type = 'income'
      AND date LIKE ?
    ''', [userId, pattern]);

    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getMonthExpense(int userId, int year, int month) async {
    final db = await instance.database;
    final monthStr = month < 10 ? '0$month' : '$month';
    final pattern = '$year-$monthStr%';

    final result = await db.rawQuery('''
      SELECT SUM(amount) AS total
      FROM transactions
      WHERE userId = ?
      AND type = 'expense'
      AND date LIKE ?
    ''', [userId, pattern]);

    return (result.first['total'] as int?) ?? 0;
  }

  // ServerId and Unsynced Wallets Helpers
  Future<List<Map<String, dynamic>>> getUnsyncedWallets(int userId) async {
    final db = await instance.database;
    return await db.query(
      'wallets',
      where: 'userId = ? AND (serverId IS NULL OR serverId = 0)',
      whereArgs: [userId],
    );
  }

  Future<bool> hasUnsyncedTransactionsForWallet(int localWalletId) async {
    final db = await instance.database;
    final res = await db.query(
      'transactions',
      where: '(walletId = ? OR toWalletId = ?) AND (isSynced IS NULL OR isSynced = 0)',
      whereArgs: [localWalletId, localWalletId],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  Future<void> updateWalletServerId(int localId, int serverId) async {
    final db = await instance.database;
    await db.update(
      'wallets',
      {'serverId': serverId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateTransactionServerId(int localId, int serverId) async {
    final db = await instance.database;
    await db.update(
      'transactions',
      {'serverId': serverId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<Map<String, dynamic>?> getWalletByServerId(int serverId, [int? userId]) async {
    final db = await instance.database;
    final result = await db.query(
      'wallets',
      where: userId != null ? 'serverId = ? AND userId = ?' : 'serverId = ?',
      whereArgs: userId != null ? [serverId, userId] : [serverId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<Map<String, dynamic>?> getTransactionByEventId(String eventId, [int? userId]) async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      where: userId != null ? 'eventId = ? AND userId = ?' : 'eventId = ?',
      whereArgs: userId != null ? [eventId, userId] : [eventId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  // Upsert local records from backend
  Future<int> upsertWalletFromBackend(int localUserId, Map<String, dynamic> remoteWallet) async {
    final db = await instance.database;
    final serverId = (remoteWallet['id'] ?? remoteWallet['walletId']) as int?;
    final clientId = remoteWallet['clientId']?.toString();
    final name = remoteWallet['name']?.toString() ?? 'Ví';
    final balance = (remoteWallet['currentBalance'] ?? remoteWallet['balance'] ?? remoteWallet['initialBalance'] as num?)?.toInt() ?? 0;
    final initialBalance = (remoteWallet['initialBalance'] as num?)?.toInt() ?? balance;
    final type = remoteWallet['type']?.toString() ?? 'bank';

    if (serverId != null && serverId > 0) {
      final existingByServerId = await db.query(
        'wallets',
        where: 'serverId = ? AND userId = ?',
        whereArgs: [serverId, localUserId],
        limit: 1,
      );

      if (existingByServerId.isNotEmpty) {
        final localId = existingByServerId.first['id'] as int;
        final hasPending = await hasUnsyncedTransactionsForWallet(localId);

        await db.update(
          'wallets',
          {
            'name': name,
            if (!hasPending) 'balance': balance,
            if (!hasPending) 'initialBalance': initialBalance,
            'type': type,
            if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return localId;
      }
    }

    if (clientId != null && clientId.isNotEmpty) {
      final existingByClientId = await db.query(
        'wallets',
        where: 'clientId = ? AND userId = ?',
        whereArgs: [clientId, localUserId],
        limit: 1,
      );

      if (existingByClientId.isNotEmpty) {
        final localId = existingByClientId.first['id'] as int;
        final hasPending = await hasUnsyncedTransactionsForWallet(localId);

        await db.update(
          'wallets',
          {
            'serverId': serverId,
            'name': name,
            if (!hasPending) 'balance': balance,
            if (!hasPending) 'initialBalance': initialBalance,
            'type': type,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return localId;
      }
    }

    return await db.insert('wallets', {
      'serverId': serverId,
      'clientId': clientId ?? generateUuid(),
      'userId': localUserId,
      'name': name,
      'balance': balance,
      'initialBalance': initialBalance,
      'type': type,
    });
  }

  Future<void> upsertTransactionFromBackend(int localUserId, Map<String, dynamic> remoteTx) async {
    final db = await instance.database;
    final serverId = (remoteTx['id'] ?? remoteTx['transactionId']) as int?;
    final eventId = remoteTx['eventId']?.toString();
    final familyGroupId = (remoteTx['familyGroupId'] as num?)?.toInt();
    final amount = (remoteTx['amount'] as num?)?.toInt().abs() ?? 0;
    final type = remoteTx['type']?.toString() ?? 'expense';
    final adjustmentDirection = remoteTx['adjustmentDirection']?.toString();
    final isExpense = (type == 'expense' || (type == 'adjustment' && adjustmentDirection == 'decrease')) ? 1 : 0;
    final categoryName = remoteTx['categoryName']?.toString() ?? 'Khác';
    final date = remoteTx['occurredAtUtc']?.toString() ?? remoteTx['occurredAt']?.toString() ?? DateTime.now().toUtc().toIso8601String();
    final note = remoteTx['note']?.toString() ?? '';

    int? localWalletId;
    final remoteWalletId = (remoteTx['walletId'] as num?)?.toInt();
    if (remoteWalletId != null && remoteWalletId > 0) {
      final localWallet = await getWalletByServerId(remoteWalletId, localUserId);
      if (localWallet != null) {
        localWalletId = localWallet['id'] as int?;
      }
    }

    int? localToWalletId;
    final remoteToWalletId = (remoteTx['toWalletId'] as num?)?.toInt();
    if (remoteToWalletId != null && remoteToWalletId > 0) {
      final localToWallet = await getWalletByServerId(remoteToWalletId, localUserId);
      if (localToWallet != null) {
        localToWalletId = localToWallet['id'] as int?;
      }
    }

    if (eventId != null && eventId.isNotEmpty) {
      final existingByEvent = await getTransactionByEventId(eventId, localUserId);
      if (existingByEvent != null) {
        final localId = existingByEvent['id'] as int;
        await db.update(
          'transactions',
          {
            'serverId': serverId,
            'amount': amount,
            'type': type,
            if (familyGroupId != null) 'familyGroupId': familyGroupId,
            if (adjustmentDirection != null) 'adjustmentDirection': adjustmentDirection,
            'isExpense': isExpense,
            'categoryName': categoryName,
            'date': date,
            'note': note,
            'isSynced': 1,
            if (localWalletId != null) 'walletId': localWalletId,
            if (localToWalletId != null) 'toWalletId': localToWalletId,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;
      }
    }

    if (serverId != null && serverId > 0) {
      final existingByServer = await db.query(
        'transactions',
        where: 'serverId = ? AND userId = ?',
        whereArgs: [serverId, localUserId],
        limit: 1,
      );

      if (existingByServer.isNotEmpty) {
        final localId = existingByServer.first['id'] as int;
        await db.update(
          'transactions',
          {
            'amount': amount,
            'type': type,
            if (familyGroupId != null) 'familyGroupId': familyGroupId,
            if (adjustmentDirection != null) 'adjustmentDirection': adjustmentDirection,
            'isExpense': isExpense,
            'categoryName': categoryName,
            'date': date,
            'note': note,
            'isSynced': 1,
            if (eventId != null) 'eventId': eventId,
            if (localWalletId != null) 'walletId': localWalletId,
            if (localToWalletId != null) 'toWalletId': localToWalletId,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;
      }
    }

    await db.insert('transactions', {
      'serverId': serverId,
      'userId': localUserId,
      'walletId': localWalletId,
      'toWalletId': localToWalletId,
      'familyGroupId': familyGroupId,
      'amount': amount,
      'type': type,
      'adjustmentDirection': adjustmentDirection,
      'isExpense': isExpense,
      'categoryName': categoryName,
      'date': date,
      'note': note,
      'isSynced': 1,
      'eventId': eventId ?? generateUuid(),
    });
  }
}
