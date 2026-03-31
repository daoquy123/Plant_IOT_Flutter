# Plant IoT Flutter

Hệ thống gồm 2 phần chính:

- `lib/`, `android/`, `windows/` → ứng dụng Flutter
- `server/` → backend Node.js nhận dữ liệu cảm biến, ảnh và relay command

## Cấu trúc đề xuất

```text
Plant_IOT_Flutter/
├─ lib/
├─ android/
├─ windows/
├─ server/
│  ├─ server.js
│  ├─ package.json
│  ├─ package-lock.json
│  ├─ node_modules/
│  └─ uploads/
└─ README.md
```

## Chạy Node.js server

Lần đầu:

```powershell
cd "c:\Users\LENOVO\Documents\GitHub\Plant_IOT_Flutter\server"
npm install
npm start
```

Những lần sau:

```powershell
cd "c:\Users\LENOVO\Documents\GitHub\Plant_IOT_Flutter\server"
npm start
```

Server mặc định chạy tại:

```text
http://localhost:3000
```

## API nhanh

- `GET /` → kiểm tra server
- `POST /api/sensor` → ESP32 gửi sensor
- `GET /api/sensor/latest` → lấy sensor mới nhất
- `POST /api/image` → ESP32-CAM gửi ảnh
- `GET /api/image/latest` → lấy ảnh mới nhất
- `POST /api/relay` → Flutter gửi lệnh
- `GET /api/command` → ESP32 lấy lệnh

