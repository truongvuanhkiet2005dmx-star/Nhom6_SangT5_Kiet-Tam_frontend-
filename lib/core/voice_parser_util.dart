class VoiceParserUtil {
  static Map<String, dynamic> parseVoiceInput(String text) {
    if (text.trim().isEmpty) {
      return {'amount': 0, 'category': 'Khác', 'note': text};
    }

    String lower = text.toLowerCase();
    int amount = 0;

    // F1 Fix: Dùng (?!\p{L}) thay vì \b để regex hoạt động đúng với Tiếng Việt có dấu
    // 1. Shorthand "50k", "100k", "20k"
    final kRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngàn)(?!\p{L})', caseSensitive: false, unicode: true);
    final kMatch = kRegex.firstMatch(lower);
    if (kMatch != null) {
      double numVal = double.tryParse(kMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      amount = (numVal * 1000).round();
    }

    // 2. Shorthand "1.5 triệu", "2 tr", "1 triệu"
    if (amount == 0) {
      final trieuRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(triệu|tr(?!\p{L}))', caseSensitive: false, unicode: true);
      final trieuMatch = trieuRegex.firstMatch(lower);
      if (trieuMatch != null) {
        double numVal = double.tryParse(trieuMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 1000000).round();
      }
    }

    // 3. Shorthand "200 trăm nghìn"
    if (amount == 0) {
      final tramNghinRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(trăm nghìn|trăm ngàn)', caseSensitive: false, unicode: true);
      final tramNghinMatch = tramNghinRegex.firstMatch(lower);
      if (tramNghinMatch != null) {
        double numVal = double.tryParse(tramNghinMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 100000).round();
      }
    }

    // 4. Raw digits e.g. "50000"
    if (amount == 0) {
      final digitRegex = RegExp(r'(\d{4,12})');
      final digitMatch = digitRegex.firstMatch(lower);
      if (digitMatch != null) {
        amount = int.tryParse(digitMatch.group(1)!) ?? 0;
      }
    }

    // 5. Full Vietnamese word-number parser (Fix #1 & #28)
    if (amount == 0 && (lower.contains('ngàn') || lower.contains('nghìn') || lower.contains('trăm') || lower.contains('triệu') || lower.contains('mươi') || lower.contains('mười'))) {
      amount = _parseVietnameseWordsToNumber(lower);
    }

    String category = 'Khác';
    if (lower.contains('ăn') || lower.contains('cà phê') || lower.contains('phở') || lower.contains('cơm') || lower.contains('uống') || lower.contains('trà')) {
      category = 'Đồ ăn';
    } else if (lower.contains('xe') || lower.contains('xăng') || lower.contains('grab') || lower.contains('đi lại') || lower.contains('bus')) {
      category = 'Đi lại';
    } else if (lower.contains('mua') || lower.contains('shopee') || lower.contains('sắm') || lower.contains('quần áo')) {
      category = 'Mua sắm';
    } else if (lower.contains('điện thoại') || lower.contains('nạp thẻ') || lower.contains('4g')) {
      category = 'Điện thoại';
    } else if (lower.contains('phim') || lower.contains('xem') || lower.contains('chơi') || lower.contains('game')) {
      category = 'Giải trí';
    } else if (lower.contains('lương') || lower.contains('thưởng')) {
      category = 'Lương';
    }

    return {
      'amount': amount,
      'category': category,
      'note': text,
    };
  }

  static int _parseVietnameseWordsToNumber(String text) {
    int total = 0;

    // Phân tách nhánh hàng Triệu
    if (text.contains('triệu') || text.contains(' tr ')) {
      final parts = text.split(RegExp(r'triệu|tr(?!\p{L})', unicode: true));
      int millions = _parseSubThousand(parts[0]);
      if (millions == 0) millions = 1; // e.g. "một triệu"
      total += millions * 1000000;

      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        total += _parseSubMillions(parts[1]);
      }
      return total;
    }

    return _parseSubMillions(text);
  }

  static int _parseSubMillions(String text) {
    int total = 0;
    if (text.contains('nghìn') || text.contains('ngàn')) {
      final parts = text.split(RegExp(r'nghìn|ngàn'));
      int thousands = _parseSubThousand(parts[0]);
      if (thousands == 0) thousands = 1;
      total += thousands * 1000;

      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        total += _parseSubThousand(parts[1]);
      }
      return total;
    }

    return _parseSubThousand(text);
  }

  // F2 Fix: Tách token từ từ trái sang phải, bóc tách cụm đã khớp để không bao giờ bị cộng dồn trùng lặp
  static int _parseSubThousand(String text) {
    int sum = 0;
    String t = text;

    final numMatch = RegExp(r'(\d+)').firstMatch(t);
    if (numMatch != null) {
      return int.tryParse(numMatch.group(1)!) ?? 0;
    }

    final hundreds = [
      ['chín trăm', 900], ['tám trăm', 800], ['bảy trăm', 700], ['sáu trăm', 600],
      ['năm trăm', 500], ['bốn trăm', 400], ['ba trăm', 300], ['hai trăm', 200],
      ['một trăm', 100], ['trăm', 100]
    ];
    for (var h in hundreds) {
      if (t.contains(h[0] as String)) {
        sum += h[1] as int;
        t = t.replaceFirst(h[0] as String, '');
        break;
      }
    }

    final tensList = [
      ['chín mươi', 90], ['tám mươi', 80], ['bảy mươi', 70], ['sáu mươi', 60],
      ['năm mươi', 50], ['bốn mươi', 40], ['ba mươi', 30], ['hai mươi', 20],
      ['mười', 10]
    ];
    bool hasTens = false;
    for (var tens in tensList) {
      if (t.contains(tens[0] as String)) {
        sum += tens[1] as int;
        t = t.replaceFirst(tens[0] as String, '');
        hasTens = true;
        break;
      }
    }

    final units = [
      ['lăm', 5], ['mốt', 1], ['chín', 9], ['tám', 8], ['bảy', 7],
      ['sáu', 6], ['năm', 5], ['bốn', 4], ['tư', 4], ['ba', 3], ['hai', 2], ['một', 1]
    ];
    for (var u in units) {
      if (t.contains(u[0] as String)) {
        if (u[0] == 'năm' && !hasTens) {
          sum += 5;
        } else if (u[0] != 'năm') {
          sum += u[1] as int;
        } else if (hasTens) {
          sum += 5;
        }
        break;
      }
    }

    return sum;
  }
}