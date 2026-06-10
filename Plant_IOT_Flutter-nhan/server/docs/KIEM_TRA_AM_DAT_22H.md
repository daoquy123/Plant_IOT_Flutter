# Kiểm tra tự động 22:00 — ẩm đất & sức khỏe lá

Hệ thống tự điều chỉnh lịch tưới: **bình thường 2 lần/ngày** (6h, 17h), **tăng 3 lần** (6h, 12h, 17h) khi cần. Chatbot “Gợi ý lịch tưới” đồng bộ số lần từ server.

## Ẩm đất (22:00)

Mỗi ngày 22:00 kiểm tra **ẩm đất trung bình** trong ngày. Không có dữ liệu: bỏ qua. Thấp hơn **45%**: Gmail báo cáo chi tiết, từ ngày mai tưới **3 lần**, chatbot gợi ý 3. Ẩm đất ổn lại (≥ 45%): về **2 lần**, có thông báo. Ban đầu đủ ngưỡng: không đổi.

## Lá vàng+ (22:00)

Mỗi giờ **:20** server phân tích ảnh camera bằng **ResNet** và ghi log (`la_vang`, `la_sau`, `sau`). Lúc **22:00** đếm số lần lá vàng trở lên trong ngày: **≥ 10 lần** và ẩm đất TB **≤ 60%** (45% + 15%): Gmail báo cây không ổn, tưới **3 lần** từ ngày mai. Dưới 10 lần: về **2 lần**, có thông báo. Đủ điều kiện từ đầu: không đổi.

## API (test)

- `GET /api/settings/watering-plan` — lịch tưới, đếm lá hôm nay
- `POST /api/settings/watering-plan/check` — chạy logic 22:00 (ẩm đất + lá)
- `POST /api/settings/leaf-health/scan` — phân tích lá ngay (cần AI port 8000)
