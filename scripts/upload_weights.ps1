$ErrorActionPreference = "Stop"
$Server = "root@103.116.38.192"
$Remote = "/var/www/plant-iot"
$Root = "d:\Downloads\Plant_IOT_Flutter"

$files = @(
    "$Root\app\checkpoints\vgg16_cbam_best.weights.h5",
    "$Root\app\checkpoints\resnet50_cbam_best.weights.h5",
    "$Root\app\ml\predictor.py"
)

foreach ($f in $files) {
    if (-not (Test-Path $f)) { throw "Missing: $f" }
}

Write-Host "Uploading weights + predictor to $Server ..."
scp $files "${Server}:${Remote}/app/checkpoints/"
# predictor.py landed in checkpoints by batch scp — move it
ssh $Server "mv -f ${Remote}/app/checkpoints/predictor.py ${Remote}/app/ml/predictor.py && ls -lh ${Remote}/app/checkpoints/*.h5 && pm2 restart plant-ai && sleep 3 && curl -fsS http://127.0.0.1:8000/health"
Write-Host "Done."
