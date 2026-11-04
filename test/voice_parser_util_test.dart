import 'package:flutter_test/flutter_test.dart';
import 'package:smart_money_v2/core/voice_parser_util.dart';

void main() {
  group('VoiceParserUtil Tests', () {
    test('1. "Ăn sáng hai mươi nghìn"', () {
      const input = 'Ăn sáng hai mươi nghìn';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(20000));
      expect(result['category'], equals('Đồ ăn'));
      expect(result['note'], equals(input));
    });

    test('2. "Cà phê năm mươi nghìn"', () {
      const input = 'Cà phê năm mươi nghìn';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(50000));
      expect(result['category'], equals('Đồ ăn'));
      expect(result['note'], equals(input));
    });

    test('3. "Mua đồ hai trăm nghìn"', () {
      const input = 'Mua đồ hai trăm nghìn';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(200000));
      expect(result['category'], equals('Mua sắm'));
      expect(result['note'], equals(input));
    });

    test('4. "Tiền nhà 1 triệu rưỡi"', () {
      const input = 'Tiền nhà 1 triệu rưỡi';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(1500000));
      expect(result['category'], equals('Hóa đơn'));
      expect(result['note'], equals(input));
    });

    test('5. "Trà sữa 50k"', () {
      const input = 'Trà sữa 50k';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(50000));
      expect(result['category'], equals('Đồ ăn'));
      expect(result['note'], equals(input));
    });

    test('6. "Xăng xe 50000"', () {
      const input = 'Xăng xe 50000';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(50000));
      expect(result['category'], equals('Đi lại'));
      expect(result['note'], equals(input));
    });

    test('7. "Gửi xe 20.000 đ"', () {
      const input = 'Gửi xe 20.000 đ';
      final result = VoiceParserUtil.parseVoiceInput(input);

      expect(result['amount'], equals(20000));
      expect(result['category'], equals('Đi lại'));
      expect(result['note'], equals(input));
    });
  });
}
