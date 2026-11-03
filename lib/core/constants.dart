import 'package:flutter/foundation.dart';

class AppConstants {
  static const String googleServerClientId =
      '1012237002765-669qvmkevs7p6dclujhd0tm2ofab0kkb.apps.googleusercontent.com';

  // API Base URL cho ASP.NET Core Backend (Port 5087, HTTP)
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: kIsWeb
        ? 'http://localhost:5087/api'
        : 'http://10.0.2.2:5087/api',
  );

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