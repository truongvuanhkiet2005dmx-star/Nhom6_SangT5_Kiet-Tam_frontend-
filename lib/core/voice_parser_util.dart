class VoiceParserUtil {
  static Map<String, dynamic> parseVoiceInput(String text) {
    if (text.trim().isEmpty) {
      return {'amount': 0, 'category': 'Khác', 'note': text};
    }

    String lower = text.toLowerCase();
    int amount = 0;

    // 1. Combined Millions + Thousands with digits (e.g. "2 triệu 500 nghìn", "1 triệu 200k", "2 triệu 500")
    final combinedTrieuRegex = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:triệu|tr(?!\p{L}))\s*(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngàn|trăm)?(?!\p{L})',
      caseSensitive: false,
      unicode: true,
    );
    final combinedTrieuMatch = combinedTrieuRegex.firstMatch(lower);
    if (combinedTrieuMatch != null) {
      double millions = double.tryParse(combinedTrieuMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      double remainder = double.tryParse(combinedTrieuMatch.group(2)!.replaceAll(',', '.')) ?? 0;
      String? unit = combinedTrieuMatch.group(3)?.toLowerCase();

      int subAmount = 0;
      if (unit == 'trăm') {
        subAmount = (remainder * 100000).round();
      } else if (unit == 'k' || unit == 'nghìn' || unit == 'ngàn' || unit == null) {
        subAmount = remainder < 10 ? (remainder * 100000).round() : (remainder * 1000).round();
      }

      amount = (millions * 1000000).round() + subAmount;
    }

    // 2. Combined Hundreds + Thousands with digits (e.g. "5 trăm 50 nghìn")
    if (amount == 0) {
      final combinedTramRegex = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*trăm\s*(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngàn)?(?!\p{L})',
        caseSensitive: false,
        unicode: true,
      );
      final combinedTramMatch = combinedTramRegex.firstMatch(lower);
      if (combinedTramMatch != null) {
        double hundreds = double.tryParse(combinedTramMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        double remainder = double.tryParse(combinedTramMatch.group(2)!.replaceAll(',', '.')) ?? 0;

        amount = (hundreds * 100000).round() + (remainder * 1000).round();
      }
    }

    // 3. Shorthand "triệu rưỡi", "1 triệu rưỡi", "1.5 triệu", "1.5 tr"
    if (amount == 0) {
      final trieuRuoiRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:triệu|tr(?!\p{L}))\s*rưỡi', caseSensitive: false, unicode: true);
      final trieuRuoiMatch = trieuRuoiRegex.firstMatch(lower);
      if (trieuRuoiMatch != null) {
        double numVal = double.tryParse(trieuRuoiMatch.group(1)!.replaceAll(',', '.')) ?? 1;
        amount = (numVal * 1000000 + 500000).round();
      } else if (lower.contains('triệu rưỡi') || lower.contains('tr rưỡi')) {
        amount = 1500000;
      }
    }

    // 4. Shorthand "củ" (e.g. "5 củ", "1.5 củ")
    if (amount == 0) {
      final cuRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(củ)(?!\p{L})', caseSensitive: false, unicode: true);
      final cuMatch = cuRegex.firstMatch(lower);
      if (cuMatch != null) {
        double numVal = double.tryParse(cuMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 1000000).round();
      }
    }

    // 5. Full Vietnamese word-number parser (e.g. "hai triệu năm trăm nghìn", "hai mươi nghìn")
    if (amount == 0 && (lower.contains('ngàn') || lower.contains('nghìn') || lower.contains('trăm') || lower.contains('triệu') || lower.contains('mươi') || lower.contains('mười'))) {
      amount = _parseVietnameseWordsToNumber(lower);
    }

    // 6. Single unit "triệu"
    if (amount == 0) {
      final trieuRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(triệu|tr(?!\p{L}))', caseSensitive: false, unicode: true);
      final trieuMatch = trieuRegex.firstMatch(lower);
      if (trieuMatch != null) {
        double numVal = double.tryParse(trieuMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 1000000).round();
      }
    }

    // 7. Single unit "k", "nghìn", "ngàn"
    if (amount == 0) {
      final kRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngàn)(?!\p{L})', caseSensitive: false, unicode: true);
      final kMatch = kRegex.firstMatch(lower);
      if (kMatch != null) {
        double numVal = double.tryParse(kMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 1000).round();
      }
    }

    // 8. Shorthand "trăm rưỡi", "1 trăm rưỡi"
    if (amount == 0 && (lower.contains('trăm rưỡi') || lower.contains('trăm rưỡ'))) {
      final tramRuoiRegex = RegExp(r'(\d+)\s*trăm\s*rưỡi', caseSensitive: false, unicode: true);
      final tramRuoiMatch = tramRuoiRegex.firstMatch(lower);
      if (tramRuoiMatch != null) {
        int numVal = int.tryParse(tramRuoiMatch.group(1)!) ?? 1;
        amount = numVal * 100000 + 50000;
      } else {
        amount = 150000;
      }
    }

    // 9. Shorthand "lít", "xị", "sị" (Ví dụ: "2 lít" = 200.000đ)
    if (amount == 0) {
      final litRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(lít|xị|sị)(?!\p{L})', caseSensitive: false, unicode: true);
      final litMatch = litRegex.firstMatch(lower);
      if (litMatch != null) {
        double numVal = double.tryParse(litMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 100000).round();
      }
    }

    // 10. Formatted digits or raw digits e.g. "20.000" or "1,500,000" or "50000"
    if (amount == 0) {
      final formattedDigitRegex = RegExp(r'\b(\d{1,3}(?:[.,]\d{3})+|\d{4,12})\b');
      final formattedDigitMatch = formattedDigitRegex.firstMatch(text);
      if (formattedDigitMatch != null) {
        final rawNumStr = formattedDigitMatch.group(1)!.replaceAll('.', '').replaceAll(',', '');
        final parsedNum = int.tryParse(rawNumStr) ?? 0;
        if (parsedNum >= 1000) {
          amount = parsedNum;
        }
      }
    }

    String category = 'Khác';
    if (lower.contains('tiền nhà') || lower.contains('hóa đơn') || lower.contains('tiền điện') || lower.contains('tiền nước') || lower.contains('điện') || lower.contains('nước') || lower.contains('internet') || lower.contains('truyền hình')) {
      category = 'Hóa đơn';
    } else if (lower.contains('ăn sáng') || lower.contains('ăn trưa') || lower.contains('ăn tối') || lower.contains('đồ ăn') || lower.contains('cà phê') || lower.contains('phở') || lower.contains('cơm') || lower.contains('uống') || lower.contains('trà') || lower.contains('bún') || lower.contains('lẩu') || lower.contains('bánh') || RegExp(r'(?<=^|\s)ăn(?=$|\s)').hasMatch(lower)) {
      category = 'Đồ ăn';
    } else if (lower.contains('xe') || lower.contains('xăng') || lower.contains('grab') || lower.contains('đi lại') || lower.contains('bus') || lower.contains('gửi xe') || lower.contains('taxi')) {
      category = 'Đi lại';
    } else if (lower.contains('mua') || lower.contains('shopee') || lower.contains('sắm') || lower.contains('quần áo') || lower.contains('giày') || lower.contains('siêu thị') || lower.contains('lazada') || lower.contains('tiki')) {
      category = 'Mua sắm';
    } else if (lower.contains('điện thoại') || lower.contains('nạp thẻ') || lower.contains('4g') || lower.contains('mạng') || lower.contains('wifi')) {
      category = 'Điện thoại';
    } else if (lower.contains('thuốc') || lower.contains('bệnh viện') || lower.contains('khám') || lower.contains('sức khỏe') || lower.contains('nha khoa')) {
      category = 'Sức khỏe';
    } else if (lower.contains('phim') || lower.contains('xem') || lower.contains('chơi') || lower.contains('game') || lower.contains('karaoke')) {
      category = 'Giải trí';
    } else if (lower.contains('lương') || lower.contains('thưởng') || lower.contains('thu nhập')) {
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

    if (text.contains('triệu') || text.contains(' tr ')) {
      final parts = text.split(RegExp(r'triệu|tr(?!\p{L})', unicode: true));
      int millions = _parseSubThousand(parts[0]);
      if (millions == 0) millions = 1;
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
