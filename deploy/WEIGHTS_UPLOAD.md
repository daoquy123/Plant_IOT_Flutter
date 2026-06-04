# Upload model weights lên VPS (không nằm trong Git)

File `.h5` / `.keras` quá nặng — không đẩy lên GitHub. Sau khi `git clone` trên VPS, copy từ máy dev:

```bash
# Từ máy Windows (PowerShell) — chỉnh user@IP
scp app/checkpoints/vgg16_cbam_best.weights.h5 root@103.116.38.192:/var/www/plant-iot/app/checkpoints/
scp app/checkpoints/resnet50_best.weights.h5 root@103.116.38.192:/var/www/plant-iot/app/checkpoints/
```

Trên VPS:

```bash
ls -lh /var/www/plant-iot/app/checkpoints/
pm2 restart plant-ai
```

Tối thiểu cần: `vgg16_cbam_best.weights.h5` (model mặc định).
