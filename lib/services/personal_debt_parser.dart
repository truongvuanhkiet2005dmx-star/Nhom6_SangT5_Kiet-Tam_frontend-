import 'package:flutter/foundation.dart';

class ParsedPersonalDebtMessage {
  final int amount;
  final bool isExpense;
  final String suggestedCategory;
  final String note;
  final String rawContent;
  final String dedupKey;
  final bool isPendingConfirmation;

  ParsedPersonalDebtMessage({
    required this.amount,
    required this.isExpense,
    required this.suggestedCategory,
    required this.note,
    required this.rawContent,
    required this.dedupKey,
    this.isPendingConfirmation = true,
  });
}

class PersonalDebtParser {
  static ParsedPersonalDebtMessage? parse(String content) {
    if (content.trim().isEmpty) return null;

    final lower = content.toLowerCase();

    // Skip if this is a standard bank transaction SMS/Notification
    if (lower.contains('sdc:') ||
        lower.contains('số dư tk') ||
        lower.contains('so du tk') ||
        lower.contains('req_id') ||
        lower.contains('tk:') ||
        lower.contains('stk:')) {
      return null;
    }

    // Must contain personal debt keywords
    final hasDebtKeyword = lower.contains('nợ') ||
        lower.contains('mượn') ||
        lower.contains('vay') ||
        lower.contains('đã trả') ||
        lower.contains('chuyển trả') ||
        lower.contains('trả nợ') ||
        lower.contains('đã nhận') ||
        lower.contains('thu nợ');

    if (!hasDebtKeyword) return null;

    // 1. Amount Extraction
    int amount = 0;

    // Pattern: 1.5tr, 1,5tr, 1 triệu, 2 tr
    final trieuRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:triệu|tr(?!\p{L}))', caseSensitive: false, unicode: true);
    final trieuMatch = trieuRegex.firstMatch(lower);
    if (trieuMatch != null) {
      double numVal = double.tryParse(trieuMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      amount = (numVal * 1000000).round();
    }

    // Pattern: 100k, 50k, 100 nghìn, 100 ngàn
    if (amount == 0) {
      final kRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngàn)(?!\p{L})', caseSensitive: false, unicode: true);
      final kMatch = kRegex.firstMatch(lower);
      if (kMatch != null) {
        double numVal = double.tryParse(kMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        amount = (numVal * 1000).round();
      }
    }

    // Pattern: 500.000đ, 500,000, 100000
    if (amount == 0) {
      final formattedDigitRegex = RegExp(r'\b(\d{1,3}(?:[.,]\d{3})+|\d{4,12})\b');
      final formattedDigitMatch = formattedDigitRegex.firstMatch(content);
      if (formattedDigitMatch != null) {
        final rawNumStr = formattedDigitMatch.group(1)!.replaceAll('.', '').replaceAll(',', '');
        final parsedNum = int.tryParse(rawNumStr) ?? 0;
        if (parsedNum >= 1000) {
          amount = parsedNum;
        }
      }
    }

    if (amount < 1000) {
      debugPrint("[PersonalDebtParser] Bỏ qua tin nhắn vì không tìm thấy số tiền hợp lệ (>= 1.000đ): $content");
      return null;
    }

    // 2. Direction & Category Deduction
    bool isExpense = true;
    String suggestedCategory = 'Nợ cá nhân';

    if (lower.contains('đã nhận') || lower.contains('thu nợ')) {
      isExpense = false;
      suggestedCategory = 'Thu nợ';
    } else if (lower.contains('cho mượn') || lower.contains('cho vay')) {
      isExpense = true;
      suggestedCategory = 'Cho vay';
    } else if (lower.contains('đã trả') || lower.contains('chuyển trả') || lower.contains('trả nợ')) {
      isExpense = true;
      suggestedCategory = 'Trả nợ';
    } else if (lower.contains('mượn') || lower.contains('vay') || lower.contains('nợ')) {
      // General debt / borrow statement (e.g. "Mình nợ bạn 100k tiền mặt nha")
      isExpense = true;
      suggestedCategory = 'Nợ cá nhân';
    } else {
      // Direction ambiguous -> skip
      debugPrint("[PersonalDebtParser] Bỏ qua SMS vì không xác định được chiều giao dịch rõ ràng: $content");
      return null;
    }

    final rawHash = content.trim().replaceAll(RegExp(r'\s+'), ' ').hashCode.abs();
    final dedupKey = "DEBT_$rawHash";

    return ParsedPersonalDebtMessage(
      amount: amount,
      isExpense: isExpense,
      suggestedCategory: suggestedCategory,
      note: content.trim(),
      rawContent: content,
      dedupKey: dedupKey,
      isPendingConfirmation: true,
    );
  }
}
