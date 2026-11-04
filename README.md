# SmartMoney Frontend (Flutter)

Ứng dụng quản lý chi tiêu cá nhân và gia đình.

## Trạng thái hiện tại
- **Phân tích tĩnh (Static Analysis):** Lệnh `flutter analyze` chạy thành công (0 errors).
- **Trạng thái Build:** Lệnh `flutter build apk --debug` hiện đang gặp lỗi. Nguyên nhân do thư viện `speech_to_text-6.6.2` sử dụng `jcenter()` không còn tương thích với cấu hình Android Gradle Plugin (AGP) hiện tại.
- **Cấu hình Firebase:** `applicationId` trong `android/app/build.gradle.kts` (`com.example.frontend_nhom6_kiet_tam_app_quanlychitieu`) chưa khớp với package_name trong `android/app/google-services.json` (`com.example.smart_money_v2`). Cần cập nhật trên Firebase Console và áp dụng plugin `com.google.gms.google-services` vào Gradle để các tính năng Firebase/Google Login hoạt động chính xác.

## Hướng dẫn chạy (chế độ Dev)

- Trên Android Emulator (Port 5087 HTTP):
  ```bash
  flutter run -d android --dart-define=BACKEND_URL=http://10.0.2.2:5087/api
  ```
- Trên Windows Desktop:
  ```bash
  flutter run -d windows --dart-define=BACKEND_URL=http://localhost:5087/api
  ```
