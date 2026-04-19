# Plant IoT Flutter - Smart Garden System

## 📱 Hệ thống IoT vườn thông minh

Ứng dụng Flutter kết nối với backend Node.js để quản lý hệ thống IoT vườn thông minh, bao gồm:

### ✨ Tính năng chính
- **📊 Dashboard**: Xem dữ liệu cảm biến real-time (nhiệt độ, độ ẩm, độ ẩm đất, ánh sáng)
- **💧 Điều khiển relay**: Bật/tắt bơm nước, rèm che nắng từ xa qua app
- **📷 Camera stream**: Xem ảnh thời gian thực từ ESP32-CAM
- **🤖 Chat AI**: Tư vấn chăm sóc cây thông minh với AI
- **📈 Analytics**: Phân tích lịch sử sensor, tối ưu hóa tưới tiêu
- **🔔 Notifications**: Cảnh báo khi có bất thường
- **🌐 Socket.io**: Real-time updates không cần polling

---

## 🚀 Quick Start (Local Development)

### Backend Setup
```bash
cd server
npm install
cp .env.example .env
# Edit .env with your API key
npm start
```

### Flutter App
```bash
cd ..
flutter pub get
flutter run
```

**Settings → Server URL**: `http://localhost:3000`
**API Key**: (từ .env)

---

## 📦 Cấu trúc dự án

```
Plant_IOT_Flutter/
├── lib/
│   ├── main.dart
│   ├── data/                      # API clients, database
│   │   ├── esp32_client.dart      # HTTP client
│   │   ├── preferences_service.dart# SharedPreferences
│   │   └── preference_keys.dart
│   ├── models/                    # Data models
│   ├── providers/                 # State management (Provider)
│   │   ├── garden_provider.dart   # Main logic, Socket.io
│   │   ├── settings_provider.dart # Config storage
│   │   └── ...
│   ├── screens/                   # UI screens
│   └── widgets/                   # Reusable components
├── server/
│   ├── server.js                  # Main entry point
│   ├── package.json
│   ├── .env.example               # Environment template
│   ├── config/
│   │   ├── database.js            # SQLite setup
│   │   └── env.js                 # Config validation
│   ├── middleware/                # Express middlewares
│   │   ├── auth.js                # API key validation
│   │   ├── errorHandler.js
│   │   ├── logger.js              # Morgan logs
│   │   └── rateLimiter.js
│   ├── src/routes/                # API endpoints
│   │   ├── sensors.js             # GET/POST sensor
│   │   ├── relay.js               # Relay control
│   │   ├── camera.js              # Image upload/download
│   │   ├── history.js             # Historical data
│   │   └── health.js              # Health check
│   ├── services/                  # Business logic
│   │   ├── sensorService.js
│   │   ├── relayService.js
│   │   └── cameraService.js
│   ├── uploads/                   # ESP32-CAM images
│   ├── logs/                      # Server logs
│   ├── data/                      # SQLite database
│   └── scripts/                   # Utilities (backup)
├── ecosystem.config.js            # PM2 config
├── DEPLOY_GUIDE.md               # Production deployment
└── README.md                      # This file
```

---

## 🛠️ System Architecture

```
┌─────────────┐
│ Flutter App │ Socket.io (real-time)
└──────┬──────┘ HTTPS API
       │
       ├──→ Nginx Reverse Proxy (SSL)
       │
       └──→ Node.js Backend (port 3000)
           │
           ├── SQLite Database
           │   (sensor readings, relay states, images)
           │
           └── Image uploads directory
               (/uploads)

┌─────────┐         ┌───────────────┐
│ ESP32   │─HTTP→   │ Node.js API   │
│ Sensors │         │ /api/sensors  │
└─────────┘         └───────────────┘

┌─────────────┐     ┌──────────────────┐
│ ESP32-CAM   │─HTTP→  Node.js API    │
│ Camera      │     │ /api/camera/    │
└─────────────┘     │ upload          │
                    └──────────────────┘
```

---

## 🔐 Security

### API Authentication
- Dùng `X-API-KEY` header cho mọi request
- API key tối thiểu 32 ký tự random
- Không hardcode key trong code

### HTTPS/SSL
- Let's Encrypt free certificates
- Auto-renew với Certbot
- Nginx redirect HTTP → HTTPS

### Rate Limiting
- 200 requests / 15 minutes per IP
- Tránh spam và DDOS

### CORS
- Cho phép Flutter app kết nối
- Restricted origins trên production

---

## 📡 API Endpoints

| Method | Path | Mô tả |
|--------|------|-------|
| POST | `/api/sensors` | ESP32 gửi dữ liệu cảm biến |
| GET | `/api/sensors/latest` | Lấy sensor mới nhất |
| GET | `/api/sensors/history` | Lấy lịch sử sensor |
| POST | `/api/relay` | App gửi lệnh bật/tắt relay |
| GET | `/api/relay/status` | Lấy trạng thái relay hiện tại |
| POST | `/api/camera/upload` | ESP32-CAM gửi ảnh |
| GET | `/api/camera/latest` | Lấy ảnh mới nhất |
| GET | `/api/camera/list` | Danh sách ảnh |
| GET | `/health` | Health check server |

---

## 💾 Database Schema

### sensor_readings
Lưu trữ dữ liệu từ cảm biến (time-series).
```sql
- id (PK)
- temperature, humidity, light, soil_moisture, water_level
- recorded_at (indexed)
```

### relay_states
Lịch sử trạng thái relay.
```sql
- id (PK)
- relay_id, relay_name, state, triggered_by
- changed_at (indexed)
```

### camera_images
Metadata ảnh từ ESP32-CAM.
```sql
- id (PK)
- filename, filepath, file_size
- captured_at (indexed, auto-cleanup)
```

### alert_thresholds
Cấu hình ngưỡng cảnh báo.

### chat_messages
Lịch sử chat AI (sync với app SQLite).

### notifications
Danh sách thông báo.

### device_status
Thông tin heartbeat device (ESP32, ESP32-CAM).

---

## 🚀 Production Deployment

Xem chi tiết tại **[DEPLOY_GUIDE.md](./DEPLOY_GUIDE.md)**

### Quick summary:
1. Chuẩn bị VPS (Node.js 20, PM2, Nginx, Certbot)
2. Clone code, cài dependencies: `npm install --production`
3. Tạo `.env` với API key mạnh
4. Khởi động PM2: `pm2 start ecosystem.config.js --env production`
5. Cấu hình Nginx reverse proxy + SSL
6. Cập nhật URL server trong Flutter app
7. Kết nối ESP32 với WiFi, set server URL

---

## 🔧 Development

### Local testing dengan real devices
```bash
# Terminal 1: Backend
cd server
npm install
npm start  # Nghe port 3000

# Terminal 2: Flutter
flutter run  # Set server URL → http://your-IP:3000
```

### Thay đổi cấu trúc database
- Edit `server/config/database.js`
- Xoá `server/data/plant_iot.db`
- Server sẽ tự tạo schema mới khi khởi động

### Debugging
- Backend logs: `server/logs/server.log` hoặc `pm2 logs`
- Flutter: `flutter run -v` hoặc run DevTools
- Database: Dùng DB Browser for SQLite

---

## 📦 Dependencies

### Backend
- `express` - Web framework
- `socket.io` - Real-time communication
- `better-sqlite3` - SQLite database
- `multer` - File upload
- `cors`, `helmet` - Security
- `morgan` - HTTP logging
- `express-rate-limit` - Rate limiting

### Frontend (Flutter)
- `provider` - State management
- `socket_io_client` - WebSocket
- `shared_preferences` - Local storage
- `http` - HTTP client
- `sqflite` - Local database

---

## 🐛 Troubleshooting

### Flutter khônglàm được kết nối server
- Kiểm tra Settings → Server URL entry
- Ping server health endpoint: `flutter_run_offline_enabled=true`
- Xem logs: `flutter run -v`

### ESP32 không gửi dữ liệu
- Test API trực tiếp: `curl -H "X-API-KEY: xxx" https://api.yourdomain.com/health`
- Kiểm tra WiFi connection trên ESP
- Xem server logs: `pm2 logs plant-iot`

### Ảnh ESP32-CAM không upload
- Kiểm tra upload directory permissions: `chmod 755 server/uploads`
- Xem file size limit: `.env` → `MAX_FILE_SIZE_MB=5`
- Xem Nginx `client_max_body_size`: `/etc/nginx/sites-available/plant-iot` → `10M`

### Database file quá lớn
- Dữ liệu cũ tự xoá theo cấu hình (default: 30 ngày sensor, 7 ngày ảnh)
- Hoặc xoá thủ công: `rm server/data/plant_iot.db` (cảnh báo: mất dữ liệu)

---

## 📝 License

MIT License - Feel free to use and modify!

---

## 🤝 Contributing

Issues & Pull requests welcome!

---

**Made with ❤️ for smart gardening**
