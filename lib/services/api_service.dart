import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static final ApiService instance = ApiService._init();
  final http.Client _client = http.Client();

  final ValueNotifier<bool> isAuthenticatedNotifier = ValueNotifier<bool>(false);

  ApiService._init();

  Future<String> get baseUrl async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('custom_backend_url');
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      return customUrl.trim();
    }
    return AppConstants.backendBaseUrl;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('accessToken');
    if (savedToken != null && savedToken.isNotEmpty) {
      return savedToken;
    }
    return null;
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accessToken', token);
    isAuthenticatedNotifier.value = true;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('userProfile');
    isAuthenticatedNotifier.value = false;
  }

  Future<Map<String, String>> _headers({bool withAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };

    if (withAuth) {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  dynamic _processResponse(http.Response response) {
    final statusCode = response.statusCode;
    String responseBody = response.body;

    dynamic parsedBody;
    try {
      if (responseBody.isNotEmpty) {
        parsedBody = jsonDecode(responseBody);
      }
    } catch (_) {
      parsedBody = null;
    }

    if (statusCode >= 200 && statusCode < 300) {
      return parsedBody ?? {};
    }

    if (statusCode == 401) {
      final uriStr = response.request?.url.toString() ?? '';
      final isPublicAuth = uriStr.contains('/auth/login') ||
          uriStr.contains('/auth/register') ||
          uriStr.contains('/auth/otp/');
      if (!isPublicAuth) {
        clearToken();
      }

      String message = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      if (parsedBody is Map && parsedBody.containsKey('detail') && parsedBody['detail'] != null && parsedBody['detail'].toString().isNotEmpty) {
        message = parsedBody['detail'].toString();
      } else if (parsedBody is Map && parsedBody.containsKey('message') && parsedBody['message'] != null && parsedBody['message'].toString().isNotEmpty) {
        message = parsedBody['message'].toString();
      }
      throw ApiException(message, statusCode: 401);
    }

    if (statusCode == 429) {
      throw ApiException(
        'Bạn thao tác quá nhanh, vui lòng thử lại sau 1 phút.',
        statusCode: 429,
      );
    }

    String errorMessage = 'Lỗi máy chủ ($statusCode)';
    if (parsedBody is Map) {
      if (parsedBody.containsKey('detail') && parsedBody['detail'] != null && parsedBody['detail'].toString().isNotEmpty) {
        errorMessage = parsedBody['detail'].toString();
      } else if (parsedBody.containsKey('message') && parsedBody['message'] != null && parsedBody['message'].toString().isNotEmpty) {
        errorMessage = parsedBody['message'].toString();
      } else if (parsedBody.containsKey('title') && parsedBody['title'] != null && parsedBody['title'].toString().isNotEmpty) {
        errorMessage = parsedBody['title'].toString();
      } else if (parsedBody.containsKey('error') && parsedBody['error'] != null && parsedBody['error'].toString().isNotEmpty) {
        errorMessage = parsedBody['error'].toString();
      }
    } else if (parsedBody is String && parsedBody.isNotEmpty) {
      errorMessage = parsedBody;
    } else if (responseBody.isNotEmpty) {
      errorMessage = responseBody;
    }

    throw ApiException(errorMessage, statusCode: statusCode);
  }

  // Health check
  Future<Map<String, dynamic>> healthCheck() async {
    final base = await baseUrl;
    try {
      final uriApi = Uri.parse('$base/health');
      final responseApi = await _client.get(uriApi).timeout(const Duration(seconds: 5));
      final data = _processResponse(responseApi);
      return data is Map<String, dynamic> ? data : {};
    } catch (_) {
      try {
        final uriRoot = Uri.parse('${base.replaceAll('/api', '')}/health');
        final responseRoot = await _client.get(uriRoot).timeout(const Duration(seconds: 5));
        final dataRoot = _processResponse(responseRoot);
        return dataRoot is Map<String, dynamic> ? dataRoot : {};
      } catch (e) {
        return {'status': 'offline', 'error': e.toString()};
      }
    }
  }

  String normalizeWalletType(String type) {
    final lower = type.toLowerCase().trim();
    if (lower == 'cash' || lower == 'bank' || lower == 'ewallet') {
      return lower;
    }
    if (lower.contains('momo') || lower.contains('zalopay') || lower.contains('zalo') || lower.contains('vnpay') || lower.contains('vi dien tu') || lower.contains('ví điện tử')) {
      return 'ewallet';
    }
    if (lower.contains('tien mat') || lower.contains('mặt') || lower.contains('cash')) {
      return 'cash';
    }
    return 'bank';
  }

  // 1. Auth Endpoints
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/auth/register');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: false),
            body: jsonEncode({
              'email': email,
              'password': password,
              'displayName': displayName,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = _processResponse(response) as Map<String, dynamic>;
      if (data.containsKey('accessToken')) {
        await saveToken(data['accessToken'].toString());
      }
      return data;
    } on SocketException {
      throw ApiException('Không thể kết nối máy chủ ($base). Hãy kiểm tra lại kết nối mạng hoặc backend.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi đăng ký: $e');
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/auth/login');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: false),
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = _processResponse(response) as Map<String, dynamic>;
      if (data.containsKey('accessToken')) {
        await saveToken(data['accessToken'].toString());
      }
      return data;
    } on SocketException {
      throw ApiException('Không thể kết nối máy chủ ($base). Hãy kiểm tra lại kết nối mạng.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi đăng nhập: $e');
    }
  }

  Future<Map<String, dynamic>> loginWithGoogle({required String idToken}) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/auth/google');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: false),
            body: jsonEncode({
              'idToken': idToken,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = _processResponse(response) as Map<String, dynamic>;
      if (data.containsKey('accessToken')) {
        await saveToken(data['accessToken'].toString());
      }
      return data;
    } on SocketException {
      throw ApiException('Không thể kết nối máy chủ ($base).');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi đăng nhập Google với backend: $e');
    }
  }

  Future<Map<String, dynamic>> requestOtp({required String email}) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/auth/otp/request');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: false),
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } on SocketException {
      throw ApiException('Không thể kết nối máy chủ ($base). Hãy kiểm tra lại kết nối mạng.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi yêu cầu mã OTP: $e');
    }
  }

  Future<Map<String, dynamic>> verifyOtp({required String email, required String code}) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/auth/otp/verify');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: false),
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'otp': code.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = _processResponse(response) as Map<String, dynamic>;
      final token = data['accessToken']?.toString();
      if (token != null && token.isNotEmpty) {
        await saveToken(token);
      }
      return data;
    } on SocketException {
      throw ApiException('Không thể kết nối máy chủ ($base). Hãy kiểm tra lại kết nối mạng.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi xác minh mã OTP: $e');
    }
  }

  Future<Map<String, dynamic>> getProfile() async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/auth/me');

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {};
    } on SocketException {
      throw ApiException('Không thể kết nối máy chủ ($base).');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy thông tin cá nhân: $e');
    }
  }

  // 2. Device Notification Tokens
  Future<void> registerDeviceToken(String token) async {
    if (token.isEmpty) return;
    final base = await baseUrl;
    final uri = Uri.parse('$base/devices/token');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));

      _processResponse(response);
    } catch (e) {
      debugPrint('[ApiService] Register device token warning: $e');
    }
  }

  Future<void> deleteDeviceToken(String token) async {
    if (token.isEmpty) return;
    final base = await baseUrl;
    final uri = Uri.parse('$base/devices/token');

    try {
      final response = await _client
          .delete(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));

      _processResponse(response);
    } catch (e) {
      debugPrint('[ApiService] Delete device token warning: $e');
    }
  }

  // 3. Family Group Endpoints
  Future<List<dynamic>> getFamilies() async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/families');

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      if (data is List) return data;
      if (data is Map && data.containsKey('families') && data['families'] is List) {
        return data['families'] as List;
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy danh sách nhóm gia đình: $e');
    }
  }

  Future<Map<String, dynamic>> createFamily({
    required String name,
    required String displayName,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/families');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode({
              'name': name,
              'displayName': displayName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi tạo nhóm gia đình: $e');
    }
  }

  Future<Map<String, dynamic>> joinFamily({
    required String inviteCode,
    required String displayName,
    required String relationship,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/families/join');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode({
              'inviteCode': inviteCode,
              'displayName': displayName,
              'relationship': relationship,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi tham gia nhóm gia đình: $e');
    }
  }

  Future<void> leaveFamily(int familyGroupId) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/families/$familyGroupId/leave');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi rời nhóm gia đình: $e');
    }
  }

  Future<void> deleteFamily(int familyGroupId) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/families/$familyGroupId');

    try {
      final response = await _client
          .delete(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi xóa nhóm gia đình: $e');
    }
  }

  // 4. Wallet Endpoints
  Future<List<dynamic>> getWallets() async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets');

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      if (data is List) return data;
      if (data is Map && data.containsKey('wallets') && data['wallets'] is List) {
        return data['wallets'] as List;
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy danh sách ví: $e');
    }
  }

  Future<Map<String, dynamic>> getWallet(int id) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets/$id');

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy chi tiết ví: $e');
    }
  }

  Future<Map<String, dynamic>> createWallet({
    required String name,
    required int balance,
    required String type,
    String? accountNumber,
    String? clientId,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets');

    final validParams = {
      'name': name,
      'initialBalance': balance,
      'type': normalizeWalletType(type),
      if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode(validParams),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi tạo ví: $e');
    }
  }

  Future<Map<String, dynamic>> updateWallet(
    int id, {
    required String name,
    required String type,
    String? accountNumber,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets/$id');

    final validParams = {
      'name': name,
      'type': normalizeWalletType(type),
    };

    try {
      final response = await _client
          .put(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode(validParams),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi cập nhật ví: $e');
    }
  }

  Future<void> deleteWallet(int id) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets/$id');

    try {
      final response = await _client
          .delete(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi xóa ví: $e');
    }
  }

  // 5. Transaction Endpoints
  Future<List<dynamic>> getTransactions({int? year, int? month, int page = 1, int pageSize = 100}) async {
    final base = await baseUrl;
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (year != null) queryParams['year'] = year.toString();
    if (month != null) queryParams['month'] = month.toString();

    final uri = Uri.parse('$base/transactions').replace(queryParameters: queryParams);

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      if (data is List) return data;
      if (data is Map) {
        if (data.containsKey('data') && data['data'] is List) return data['data'] as List;
        if (data.containsKey('items') && data['items'] is List) return data['items'] as List;
        if (data.containsKey('transactions') && data['transactions'] is List) return data['transactions'] as List;
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy danh sách giao dịch từ C# backend: $e');
    }
  }

  Future<Map<String, dynamic>> createTransaction(Map<String, dynamic> payload) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/transactions');

    DateTime dateObj;
    final rawDate = payload['occurredAtUtc'] ?? payload['occurredAt'] ?? payload['date'];
    if (rawDate != null && rawDate.toString().isNotEmpty) {
      dateObj = DateTime.tryParse(rawDate.toString())?.toUtc() ?? DateTime.now().toUtc();
    } else {
      dateObj = DateTime.now().toUtc();
    }
    var isoUtc = dateObj.toIso8601String();
    if (!isoUtc.endsWith('Z')) {
      isoUtc = '${isoUtc}Z';
    }

    final dtoPayload = <String, dynamic>{
      'eventId': payload['eventId']?.toString() ?? '',
      'amount': (payload['amount'] as num?)?.toInt().abs() ?? 0,
      'type': payload['type']?.toString() ?? 'expense',
      'source': payload['source']?.toString() ?? payload['walletName']?.toString() ?? 'Ví tài khoản',
      'bankName': payload['bankName']?.toString() ?? '',
      'packageName': payload['packageName']?.toString() ?? '',
      'occurredAtUtc': isoUtc,
      'categoryName': payload['categoryName']?.toString() ?? 'Khác',
      'note': payload['note']?.toString() ?? '',
    };

    if (payload.containsKey('adjustmentDirection') && payload['adjustmentDirection'] != null) {
      dtoPayload['adjustmentDirection'] = payload['adjustmentDirection'];
    }
    if (payload.containsKey('walletId') && payload['walletId'] != null) {
      dtoPayload['walletId'] = payload['walletId'];
    }
    if (payload.containsKey('toWalletId') && payload['toWalletId'] != null) {
      dtoPayload['toWalletId'] = payload['toWalletId'];
    }
    if (payload.containsKey('familyGroupId') && payload['familyGroupId'] != null) {
      dtoPayload['familyGroupId'] = payload['familyGroupId'];
    }

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode(dtoPayload),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lưu giao dịch lên C# backend: $e');
    }
  }

  Future<Map<String, dynamic>> updateTransaction(int id, Map<String, dynamic> payload) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/transactions/$id');

    try {
      final response = await _client
          .put(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi sửa giao dịch: $e');
    }
  }

  Future<void> deleteTransaction(int id) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/transactions/$id');

    try {
      final response = await _client
          .delete(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi xóa giao dịch: $e');
    }
  }

  // 6. Reports & Budgets Endpoints
  Future<Map<String, dynamic>> getMonthlyReport({
    required int year,
    required int month,
    int? familyGroupId,
  }) async {
    final base = await baseUrl;
    final queryParams = <String, String>{
      'year': year.toString(),
      'month': month.toString(),
    };
    if (familyGroupId != null && familyGroupId > 0) {
      queryParams['familyGroupId'] = familyGroupId.toString();
    }

    final uri = Uri.parse('$base/reports/monthly').replace(queryParameters: queryParams);

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy báo cáo hàng tháng: $e');
    }
  }

  Future<Map<String, dynamic>> getBudget(int familyGroupId, {required int year, required int month}) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/budgets/$familyGroupId').replace(queryParameters: {
      'year': year.toString(),
      'month': month.toString(),
    });

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy hạn mức ngân sách nhóm: $e');
    }
  }

  Future<Map<String, dynamic>> setBudget(
    int familyGroupId, {
    required int year,
    required int month,
    required int monthlyLimit,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/budgets/$familyGroupId');

    try {
      final response = await _client
          .put(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode({
              'year': year,
              'month': month,
              'monthlyLimit': monthlyLimit,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi cập nhật hạn mức ngân sách nhóm: $e');
    }
  }
}
