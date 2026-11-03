import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../core/app_colors.dart';

class BillScannerScreen extends StatefulWidget {
  const BillScannerScreen({super.key});

  @override
  State<BillScannerScreen> createState() => _BillScannerScreenState();
}

class _BillScannerScreenState
    extends State<BillScannerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  final ImagePicker _picker = ImagePicker();

  File? _imageFile;
  Uint8List? _webImageBytes;
  bool _isPickingImage = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _processImage(ImageSource source) async {
    if (_isPickingImage) return;
    _isPickingImage = true;

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        if (!mounted) return;
        setState(() {
          _webImageBytes = bytes;
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tính năng AI Quét Hóa Đơn Camera hỗ trợ tốt nhất trên điện thoại Android & iOS. Vui lòng nhập số tiền trực tiếp trên Web!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      setState(() {
        _imageFile = File(pickedFile.path);
        _isScanning = true;
      });

      String extractedText = '';

      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      extractedText = recognizedText.text;
      await textRecognizer.close();

      final extractedAmount = _extractMoneyFromText(extractedText);

      if (!mounted) return;

      setState(() {
        _isScanning = false;
      });

      final result = await _showResultDialog(extractedAmount);

      // F1 Fix: Thêm await trước _processImage đệ quy để chống double-pick race condition
      if (result == 'RECAPTURE') {
        _isPickingImage = false;
        if (mounted) {
          setState(() {
            _imageFile = null;
            _webImageBytes = null;
          });
        }
        await _processImage(ImageSource.camera);
        return;
      }

      if (result != null && result.isNotEmpty && mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isScanning = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không thể đọc hóa đơn! Vui lòng thử lại.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isPickingImage = false;
    }
  }

  String _removeAccents(String str) {
    var withAccents = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    var withoutAccents = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    for (int i = 0; i < withAccents.length; i++) {
      str = str.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return str;
  }

  String _extractMoneyFromText(String text) {
    if (text.isEmpty) return '0';
    final lines = text.split('\n');

    final totalKeywords = [
      'tong tien hang', 'tong tien', 'tuyen tien', 'tong thanh toan',
      'can thanh toan', 'can thanh toan', 'tien can thanh toan', 'tien thanh toan',
      'tong cong', 'thanh toan', 'so tien', 'total', 'amount', 'sum', 'net',
      'chi phi', 'gia tri'
    ];

    final noiseKeywords = [
      'hotline', 'mst', 'ma cqt', 'msch', 'ptt', 'nv', 'chiet khau', 'km',
      'tel', 'phone', 'www', '.vn', '.com', 'chịu trách nhiệm', 'phút'
    ];

    final numberRegex = RegExp(r'(?<!\d)(?:\d{1,3}(?:[.,]\d{3})+|\d{4,})(?!\d)');

    for (final line in lines) {
      final normalizedLine = _removeAccents(line.toLowerCase());

      bool isNoise = noiseKeywords.any((kw) => normalizedLine.contains(kw));
      if (isNoise) continue;

      if (totalKeywords.any((kw) => normalizedLine.contains(kw))) {
        final lineMatches = numberRegex.allMatches(line);
        final List<int> lineNumbers = [];

        for (final match in lineMatches) {
          final raw = match.group(0) ?? '';
          final cleaned = raw.replaceAll('.', '').replaceAll(',', '');
          final number = int.tryParse(cleaned);
          if (number != null && number >= 1000 && number <= 500000000) {
            lineNumbers.add(number);
          }
        }

        if (lineNumbers.isNotEmpty) {
          lineNumbers.sort();
          return _formatMoney(lineNumbers.last);
        }
      }
    }

    final List<int> validAmounts = [];
    for (final line in lines) {
      final normalizedLine = _removeAccents(line.toLowerCase());
      bool isNoise = noiseKeywords.any((kw) => normalizedLine.contains(kw));
      if (isNoise) continue;

      final lineMatches = numberRegex.allMatches(line);
      for (final match in lineMatches) {
        final raw = match.group(0) ?? '';
        final cleaned = raw.replaceAll('.', '').replaceAll(',', '');
        final number = int.tryParse(cleaned);
        if (number != null && number >= 1000 && number <= 500000000) {
          validAmounts.add(number);
        }
      }
    }

    if (validAmounts.isNotEmpty) {
      validAmounts.sort();
      return _formatMoney(validAmounts.last);
    }

    return '0';
  }

  String _formatMoney(int amount) {
    final text = amount.toString();
    String result = '';

    for (int i = text.length - 1, count = 1; i >= 0; i--, count++) {
      result = text[i] + result;
      if (count % 3 == 0 && i != 0) {
        result = ',$result';
      }
    }

    return result;
  }

  Future<String?> _showResultDialog(String detectedAmount) async {
    final now = DateTime.now();
    final today = '${now.day}/${now.month}/${now.year}';
    final amountController = TextEditingController(text: detectedAmount);

    final String? dialogResult = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
              ),
              SizedBox(width: 8),
              Text(
                'Quét hoàn tất',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResultRow('Ngày:', today),
              const SizedBox(height: 12),
              const Text('Số tiền quét được (có thể sửa):', style: TextStyle(color: AppColors.textSub, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 20),
                decoration: const InputDecoration(
                  suffixText: 'đ',
                  suffixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Danh mục gợi ý: Hóa đơn / Mua sắm',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, 'RECAPTURE');
              },
              child: const Text(
                'Chụp lại',
                style: TextStyle(
                  color: AppColors.textSub,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final finalAmount = amountController.text.trim();
                Navigator.pop(
                  context,
                  finalAmount.isEmpty ? '0' : finalAmount,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Áp dụng',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    amountController.dispose();
    return dialogResult;
  }

  Widget _buildResultRow(
      String label,
      String value, {
        bool isTotal = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSub,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isTotal ? 18 : 14,
                color: isTotal ? AppColors.primary : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_imageFile != null && !kIsWeb)
            Positioned.fill(
              child: Image.file(
                _imageFile!,
                fit: BoxFit.cover,
              ),
            )
          else if (_webImageBytes != null && kIsWeb)
            Positioned.fill(
              child: Image.memory(
                _webImageBytes!,
                fit: BoxFit.cover,
              ),
            )
          else
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_enhance_outlined,
                      size: 64,
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chạm nút camera bên dưới để chụp hóa đơn\nhoặc chọn ảnh từ thư viện',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Positioned(
                        top: _animationController.value *
                            (MediaQuery.of(context).size.height * 0.6 - 2),
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary,
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          if (_isScanning)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'AI đang bóc tách dữ liệu hóa đơn...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  'Quét Hóa Đơn AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.photo_library,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: _isScanning
                      ? null
                      : () => _processImage(
                    ImageSource.gallery,
                  ),
                ),
                GestureDetector(
                  onTap: _isScanning
                      ? null
                      : () => _processImage(
                    ImageSource.camera,
                  ),
                  child: Container(
                    height: 76,
                    width: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 3.5,
                      ),
                      color: AppColors.primary,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.black,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}