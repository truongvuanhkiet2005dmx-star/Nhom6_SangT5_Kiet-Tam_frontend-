# SmartMoney Frontend (Flutter)

Ứng dụng quản lý chi tiêu cá nhân và gia đình.

## Trạng thái hiện tại
- **Phân tích tĩnh (Static Analysis):** Lệnh `flutter analyze` chạy thành công (0 errors).
- **Trạng thái Build:** Lệnh `flutter build apk --debug` hiện đang gặp lỗi. Nguyên nhân do thư viện `speech_to_text-6.6.2` sử dụng `jcenter()` không còn tương thích với cấu hình Android Gradle Plugin (AGP) hiện tại.
- **Cấu hình Firebase:** `applicationId` trong `android/app/build.gradle.kts` (`com.example.frontend_nhom6_kiet_tam_app_quanlychitieu`) chưa khớp với package_name trong `android/app/google-services.json` (`com.example.smart_money_v2`). Cần cập nhật trên Firebase Console và áp dụng plugin `com.google.gms.google-services` vào Gradle để các tính năng Firebase/Google Login hoạt động chính xác.

## Chạy thử
- Cần Flutter SDK, điện thoại Android bật gỡ lỗi USB (hoặc emulator).
- Chạy `flutter pub get`.
- Chạy đoạn PowerShell này MỘT LẦN (sửa compileSdk của 2 plugin cũ), rồi mới build:
  ```powershell
  foreach ($p in "telephony-*","flutter_notification_listener-*") {
    Get-ChildItem "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev" -Directory -Filter $p | ForEach-Object {
      $f = Join-Path $_.FullName "android\build.gradle"
      if (Test-Path $f) { (Get-Content $f) -replace 'compileSdk(Version)?\s*=?\s*\d+','compileSdkVersion 36' | Set-Content $f }
    }
  }
  ```
- Rồi `flutter run` (hoặc `flutter build apk --debug`). Ghi chú: app gọi backend qua địa chỉ ngrok mặc định trong lib/core/constants.dart, muốn đổi thì thêm `--dart-define=BACKEND_URL=<địa chỉ kết thúc bằng /api>`.
- Ghi chú: backend phải đang chạy thì đăng ký và đăng nhập mới được.
