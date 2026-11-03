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

  // Stream notifying auth status when token expires (401)
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
    return prefs.getString('accessToken');
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
      clearToken();
      throw ApiException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        statusCode: 401,
      );
    }

    if (statusCode == 403) {
      throw ApiException(
        'Bạn không có quyền thực hiện thao tác này.',
        statusCode: 403,
      );
    }

    String errorMessage = 'Lỗi máy chủ ($statusCode)';
    if (parsedBody is Map) {
      if (parsedBody.containsKey('message') && parsedBody['message'] != null) {
        errorMessage = parsedBody['message'].toString();
      } else if (parsedBody.containsKey('error') && parsedBody['error'] != null) {
        errorMessage = parsedBody['error'].toString();
      } else if (parsedBody.containsKey('title') && parsedBody['title'] != null) {
        errorMessage = parsedBody['title'].toString();
      }
    } else if (responseBody.isNotEmpty) {
      errorMessage = responseBody;
    }

    throw ApiException(errorMessage, statusCode: statusCode);
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

  String normalizeWalletType(String type) {
    final lower = type.toLowerCase().trim();
    if (lower == 'cash' || lower == 'bank' || lower == 'ewallet') {
      return lower;
    }
    if (lower.contains('momo') || lower.contains('zalo') || lower.contains('vi')) {
      return 'ewallet';
    }
    if (lower.contains('tien mat') || lower.contains('mặt')) {
      return 'cash';
    }
    return 'bank';
  }

  Future<Map<String, dynamic>> createWallet({
    required String name,
    required int balance,
    required String type,
    String? accountNumber,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets');

    final validParams = {
      'name': name,
      'balance': balance,
      'type': normalizeWalletType(type),
      if (accountNumber != null && accountNumber.isNotEmpty) 'accountNumber': accountNumber,
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
    required int balance,
    required String type,
    String? accountNumber,
  }) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/wallets/$id');

    final validParams = {
      'name': name,
      'balance': balance,
      'type': normalizeWalletType(type),
      if (accountNumber != null && accountNumber.isNotEmpty) 'accountNumber': accountNumber,
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
  Future<List<dynamic>> getTransactions({int? year, int? month}) async {
    final base = await baseUrl;
    final queryParams = <String, String>{};
    if (year != null) queryParams['year'] = year.toString();
    if (month != null) queryParams['month'] = month.toString();

    final uri = Uri.parse('$base/transactions').replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    try {
      final response = await _client
          .get(
            uri,
            headers: await _headers(withAuth: true),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      if (data is List) return data;
      if (data is Map && data.containsKey('transactions') && data['transactions'] is List) {
        return data['transactions'] as List;
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi lấy danh sách giao dịch: $e');
    }
  }

  Future<Map<String, dynamic>> createTransaction(Map<String, dynamic> payload) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/transactions');

    try {
      final response = await _client
          .post(
            uri,
            headers: await _headers(withAuth: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      final data = _processResponse(response);
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Lỗi tạo giao dịch: $e');
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
