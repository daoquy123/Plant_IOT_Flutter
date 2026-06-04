# Deploy AI lên VPS `103.116.38.192`

AI service chạy **FastAPI + TensorFlow** (VGG16-CBAM / ResNet50), phục vụ Flutter app qua endpoint `/predict`.

## 1. Trên VPS (Ubuntu)

```bash
# Cài Python + PM2 (nếu chưa có)
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
sudo npm install -g pm2

# Clone hoặc pull repo
cd /var/www
sudo git clone https://github.com/daoquy123/Plant_IOT_Flutter.git plant-iot
sudo chown -R $USER:$USER plant-iot
cd plant-iot

# Deploy AI
bash deploy/deploy-ai.sh
```

Mở firewall port AI (nếu Flutter gọi trực tiếp `:8000`):

```bash
sudo ufw allow 8000/tcp
sudo ufw status
```

## 2. Kiểm tra

```bash
curl http://127.0.0.1:8000/health
curl -F "file=@dataset/test/la_khoe/000001.jpg" -F "model=vgg16" http://127.0.0.1:8000/predict
pm2 logs plant-ai --lines 50
```

Từ máy ngoài:

```bash
curl http://103.116.38.192:8000/health
```

## 3. Cấu hình Flutter app

**Cài đặt → URL AI Server:** `http://103.116.38.192:8000`

App tự gọi `http://103.116.38.192:8000/predict`.

| Trường | Giá trị |
|--------|---------|
| Server URL | `http://103.116.38.192` |
| API Key | (giống `API_KEY` trong `server/.env`) |
| URL AI Server | `http://103.116.38.192:8000` |

## 4. Model weights bắt buộc

Upload lên VPS (nếu chưa có trong git):

- `app/checkpoints/vgg16_cbam_best.weights.h5` — model mặc định
- `app/checkpoints/resnet50_best.weights.h5` — tuỳ chọn (ResNet)

```bash
scp app/checkpoints/vgg16_cbam_best.weights.h5 user@103.116.38.192:/var/www/plant-iot/app/checkpoints/
pm2 restart plant-ai
```

## 5. Cập nhật code sau này

```bash
cd /var/www/plant-iot
git pull origin main
bash deploy/deploy-ai.sh
```

## 6. Proxy qua Nginx (tuỳ chọn)

Xem `deploy/nginx-ai-snippet.conf`. Khi dùng proxy, Flutter nhập:

`http://103.116.38.192/ai/predict`
