import 'package:flutter/foundation.dart';

class AppConstants {
  static const String googleServerClientId =
      '1012237002765-669qvmkevs7p6dclujhd0tm2ofab0kkb.apps.googleusercontent.com';

  // API Base URL cho ASP.NET Core Backend (Port 5087, HTTP)
  static const String _envBackendUrl = String.fromEnvironment('BACKEND_URL');

  static String get defaultBackendBaseUrl {
    if (kIsWeb) return 'http://localhost:5087/api';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:5087/api';
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.iOS:
      default:
        return 'http://localhost:5087/api';
    }
  }

  static String get backendBaseUrl {
    if (_envBackendUrl.isNotEmpty) return _envBackendUrl;
    return defaultBackendBaseUrl;
  }

  static const List<String> allowedBankPackages = [
    'com.vietinbank.ipay',
    'com.vbmobile',
    'vn.momo.platform',
    'com.vcbancking',
    'com.vcb.digibank',
    'com.tpb.mbanking',
    'com.vpb.neo',
    'com.agribank.mobilebanking',
    'com.acb.mobile',
    'com.bidv.smartbanking',
    'com.msb.mobile',
    'com.mbbank.mobile',
    'com.zalopay.app',
    'com.android.mms',
    'com.samsung.android.messaging',
    'com.google.android.apps.messaging',
  ];
}