import 'package:flutter/foundation.dart';

class ParsedBankMessage {
  final String bankName;
  final String? accountNumber;
  final int amount;
  final bool isExpense;
  final int? endingBalance;
  final String? displayNote;
  final String? refId;

  ParsedBankMessage({
    required this.bankName,
    this.accountNumber,
    required this.amount,
    required this.isExpense,
    this.endingBalance,
    this.displayNote,
    this.refId,
  });

  @override
  String toString() {
    return 'ParsedBankMessage(bank: $bankName, stk: $accountNumber, amount: $amount, isExpense: $isExpense, sdc: $endingBalance, ref: $refId, note: $displayNote)';
  }
}

class BankMessageParser {
  static ParsedBankMessage? parse(String content, {String packageName = ''}) {
    if (content.trim().isEmpty) return null;

    final lower = content.toLowerCase();

    // Must mention bank keywords or currency
    final isBankMsg = lower.contains('vnd') ||
        lower.contains('vnđ') ||
        lower.contains('đồng') ||
        lower.contains('so du') ||
        lower.contains('số dư') ||
        lower.contains('sdc') ||
        lower.contains('tai khoan') ||
        RegExp(r'\b(?:tk|gd|ps|stk)\b', caseSensitive: false).hasMatch(content);

    if (!isBankMsg) return null;

    // Detect Bank Name
    String bankName = 'Khác';
    if (lower.contains('vietcombank') || lower.contains('vcb') || packageName.contains('vcb')) {
      bankName = 'Vietcombank';
    } else if (lower.contains('vietinbank') || lower.contains('ctg') || lower.contains('vietin') || packageName.contains('vietinbank')) {
      bankName = 'VietinBank';
    } else if (lower.contains('mbbank') || lower.contains('mb bank') || lower.contains('mcbank') || packageName.contains('mbbank')) {
      bankName = 'MBBank';
    } else if (lower.contains('techcombank') || lower.contains('tcb') || packageName.contains('techcombank')) {
      bankName = 'Techcombank';
    } else if (lower.contains('bidv') || packageName.contains('bidv')) {
      bankName = 'BIDV';
    } else if (lower.contains('vpbank') || lower.contains('vpb') || packageName.contains('vpbank')) {
      bankName = 'VPBank';
    } else if (lower.contains('agribank') || packageName.contains('agribank')) {
      bankName = 'Agribank';
    } else if (lower.contains('acb') || packageName.contains('acb')) {
      bankName = 'ACB';
    } else if (lower.contains('tpbank') || lower.contains('tpb') || packageName.contains('tpb')) {
      bankName = 'TPBank';
    } else if (lower.contains('momo') || packageName.contains('momo')) {
      bankName = 'MoMo';
    } else if (lower.contains('zalopay') || packageName.contains('zalopay')) {
      bankName = 'ZaloPay';
    }

    // Pattern 1: Vietcombank specialized format
    // "Số dư TK VCB 1036583632 -603,300 VND lúc 19-07-2026 16:12:24. Số dư 233,893 VND. Ref..."
    final vcbRegex = RegExp(
      r'(?:Số\s*dư\s+)?TK\s*VCB\s*([0-9xX*]{6,16})\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)\s*(?:VND|đ|VNĐ|d)?\s*lúc\s*\d{2}[-/.]\d{2}[-/.]\d{2,4}\s+\d{2}:\d{2}(?::\d{2})?\.?\s*(?:Số\s*dư|SDC|SD)?\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)?',
      caseSensitive: false,
    );
    final vcbMatch = vcbRegex.firstMatch(content);
    if (vcbMatch != null) {
      final stk = vcbMatch.group(1);
      final rawAmountStr = vcbMatch.group(2) ?? '';
      final rawSdcStr = vcbMatch.group(3);

      final isExpense = rawAmountStr.startsWith('-');
      final cleanedAmt = rawAmountStr.replaceAll(RegExp(r'[^\d]'), '');
      final amount = int.tryParse(cleanedAmt) ?? 0;

      int? endingBalance;
      if (rawSdcStr != null && rawSdcStr.isNotEmpty) {
        endingBalance = int.tryParse(rawSdcStr.replaceAll(RegExp(r'[^\d]'), ''));
      }

      String? note;
      final gdMatch = RegExp(r'GD:\s*(.*)', caseSensitive: false).firstMatch(content);
      if (gdMatch != null) {
        note = gdMatch.group(1)?.trim();
      }

      String? refId;
      final refMatch = RegExp(r'Ref\s+([A-Za-z0-9_.-]+)', caseSensitive: false).firstMatch(content);
      if (refMatch != null) {
        refId = refMatch.group(1)?.trim();
      }

      if (amount >= 1000) {
        return ParsedBankMessage(
          bankName: 'Vietcombank',
          accountNumber: stk,
          amount: amount,
          isExpense: isExpense,
          endingBalance: endingBalance,
          displayNote: note ?? content,
          refId: refId,
        );
      }
    }

    // Pattern 2: Pipe-delimited format
    // "TK 99xxxx99 | GD: +1,000,000 VND | 06/07/24 20:56 | SD: 1,234,567 VND | ND: ..."
    final pipeRegex = RegExp(
      r'TK\s*([0-9xX*]{6,16})\s*\|\s*GD:\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)\s*(?:VND|đ|VNĐ|d)?\s*\|\s*[^|]+\|\s*(?:SD|SDC|Số\s*dư):\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)\s*(?:VND|đ|VNĐ|d)?(?:\s*\|\s*(?:ND|Nội\s*dung):\s*(.*))?',
      caseSensitive: false,
    );
    final pipeMatch = pipeRegex.firstMatch(content);
    if (pipeMatch != null) {
      final stk = pipeMatch.group(1);
      final rawAmountStr = pipeMatch.group(2) ?? '';
      final rawSdcStr = pipeMatch.group(3);
      final noteStr = pipeMatch.group(4);

      final isExpense = rawAmountStr.startsWith('-');
      final cleanedAmt = rawAmountStr.replaceAll(RegExp(r'[^\d]'), '');
      final amount = int.tryParse(cleanedAmt) ?? 0;

      int? endingBalance;
      if (rawSdcStr != null && rawSdcStr.isNotEmpty) {
        endingBalance = int.tryParse(rawSdcStr.replaceAll(RegExp(r'[^\d]'), ''));
      }

      if (amount >= 1000) {
        return ParsedBankMessage(
          bankName: bankName != 'Khác' ? bankName : 'Ngân hàng',
          accountNumber: stk,
          amount: amount,
          isExpense: isExpense,
          endingBalance: endingBalance,
          displayNote: noteStr?.trim() ?? content,
        );
      }
    }

    // Pattern 3: Standard Pattern (VietinBank, MB, VCB standard, etc.)
    // "VietinBank:... TK:104880072280 GD:+10,000 VND SDC:145,000 VND ND:..."
    String? stk;
    final stkMatch = RegExp(r'(?:TK|STK|SDTK|Tai\s*khoan|So\s*TK|acc|account|TK VCB)\s*[:=]?\s*([0-9xX*]{6,16})', caseSensitive: false).firstMatch(content);
    if (stkMatch != null) {
      stk = stkMatch.group(1);
    }

    int? endingBalance;
    final balanceMatch = RegExp(r'(?:SDC|SD|Số\s*dư|so\s*du|sodu)\s*[:=]?\s*([+-]?\d{1,3}(?:[.,]\d{3})+|[+-]?\d+)\s*(?:VND|đ|VNĐ|d)', caseSensitive: false).firstMatch(content);
    if (balanceMatch != null) {
      final rawBal = balanceMatch.group(1) ?? '0';
      endingBalance = int.tryParse(rawBal.replaceAll(RegExp(r'[^\d]'), ''));
    }

    // Extract transaction amount from GD: / PS: / amount pattern
    final gdMatch = RegExp(r'(?:GD|PS|So\s*tien|Số\s*tiền)\s*[:=]?\s*([+-]?\d+(?:[.,]\d+)?\s*(?:k\b|nghìn|ngàn|VND|đ|VNĐ|d)?)', caseSensitive: false).firstMatch(content);
    String? rawAmountStr;
    if (gdMatch != null) {
      rawAmountStr = gdMatch.group(1);
    } else {
      // Fallback regex for signed or unsigned amount
      final generalAmtMatch = RegExp(r'([+-]\s*\d+(?:[.,]\d+)?\s*(?:k\b|nghìn|ngàn|VND|đ|VNĐ|d)?)', caseSensitive: false).firstMatch(content);
      if (generalAmtMatch != null) {
        rawAmountStr = generalAmtMatch.group(1);
      }
    }

    if (rawAmountStr == null || rawAmountStr.isEmpty) {
      debugPrint("[BankMessageParser] Bỏ qua vì không xác định được số tiền giao dịch: $content");
      return null;
    }

    final lowerRaw = rawAmountStr.toLowerCase();
    final isK = lowerRaw.contains('k') || lowerRaw.contains('nghìn') || lowerRaw.contains('ngàn');

    final cleanedAmtStr = rawAmountStr.replaceAll(RegExp(r'[^\d]'), '');
    int amount = int.tryParse(cleanedAmtStr) ?? 0;
    if (isK) {
      amount = amount * 1000;
    }

    if (amount < 1000) return null;

    bool isIncome = rawAmountStr.contains('+') ||
        lower.contains('giao dịch +') ||
        lower.contains('gd: +') ||
        lower.contains('gd:+') ||
        lower.contains('ps:+') ||
        lower.contains('cộng') ||
        lower.contains('nhận');

    bool isExpense = rawAmountStr.contains('-') ||
        lower.contains('trừ') ||
        lower.contains('thanh toan') ||
        lower.contains('thanh toán') ||
        lower.contains('chi') ||
        lower.contains('rut tien') ||
        lower.contains('rút tiền');

    if (!isIncome && !isExpense) {
      debugPrint("[BankMessageParser] Bỏ qua vì không xác định được chiều giao dịch (thu/chi): $content");
      return null;
    }

    final finalIsExpense = isExpense && !isIncome;

    String? refId;
    final refMatch = RegExp(r'(?:REQ_ID|Ref|Mã\s*GD|Ma\s*GD|RefNo|TraceNo)\s*[:=]?\s*([A-Za-z0-9_.-]{6,32})', caseSensitive: false).firstMatch(content);
    if (refMatch != null) {
      refId = refMatch.group(1)?.trim();
    }

    String? note;
    final ndMatch = RegExp(r'\b(?:ND|Nội\s*dung)\b\s*[:=]?\s*(.*)', caseSensitive: false).firstMatch(content);
    if (ndMatch != null) {
      note = ndMatch.group(1)?.trim();
    }

    return ParsedBankMessage(
      bankName: bankName != 'Khác' ? bankName : 'Ngân hàng',
      accountNumber: stk,
      amount: amount,
      isExpense: finalIsExpense,
      endingBalance: endingBalance,
      displayNote: note ?? content,
      refId: refId,
    );
  }
}
