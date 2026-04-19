# Production deployment (Ubuntu VPS)

**Target domain:** `five-small-snowflake.site`  
**Node app port (internal):** `3000` (Nginx terminates 80/443 and proxies to 127.0.0.1:3000)

## 0. DNS (you must verify from your PC)

A record: `five-small-snowflake.site` → `103.116.38.49` (or your current VPS IP).  
Check when DNS has propagated:

```bash
dig +short five-small-snowflake.site A
nslookup five-small-snowflake.site
```

## 1. Firewall (UFW)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Node should **not** be exposed on 3000 publicly if Nginx is used; only Nginx listens on 80/443.

## 2. Install Node.js 20 LTS

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v
```

## 3. App on the server

```bash
cd /var/www
sudo git clone <your-repo-url> plant-iot
sudo chown -R $USER:$USER plant-iot
cd plant-iot/server
cp .env.example .env
nano .env
```

Set at least: `API_KEY` (≥32 random chars), `DB_PATH`, `UPLOADS_DIR`, `HOST=0.0.0.0`, `PORT=3000`, and `CORS_ORIGINS` (include `https://five-small-snowflake.site` after SSL; for tests you can leave empty to allow all).

```bash
npm install --production
node -c server.js
cd .. && pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup
```

## 4. Nginx

```bash
sudo apt install -y nginx
sudo cp deploy/nginx-five-small-snowflake.site.conf /etc/nginx/sites-available/five-small-snowflake.site
# Before SSL: use a temporary server { listen 80; ... proxy_pass; } or certbot standalone
sudo certbot --nginx -d five-small-snowflake.site
sudo ln -s /etc/nginx/sites-available/five-small-snowflake.site /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

**Before Let’s Encrypt:** use a simple HTTP-only `server { listen 80; server_name ...; location / { proxy_pass http://127.0.0.1:3000; ... } }` then replace with the full SSL config after `certbot`.

## 5. Smoke tests

From your laptop:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://five-small-snowflake.site/health
curl -sS -H "X-API-KEY: YOUR_KEY" https://five-small-snowflake.site/api/sensors/latest
```

On VPS:

```bash
sudo ss -tlnp | grep -E ':80|:443|:3000'
curl -sS http://127.0.0.1:3000/health
```

## 6. ESP32 checklist

Same base URL as the app (HTTPS after SSL): `https://five-small-snowflake.site`

| Item | Detail |
|------|--------|
| Headers | `X-API-KEY: <same as server API_KEY>` |
| POST sensors | `POST /api/sensors` JSON body |
| POST relay | `POST /api/relay` JSON `relay_id` + `state` **or** `action`: `shade_on` / `shade_off` / `pump_on` / `pump_off` |
| Socket.IO | Connect with header `X-API-KEY` (required); path `/socket.io/` |

Relay IDs expected by defaults: **1 = shade**, **2 = pump** (match firmware).

## 7. Flutter app

Default server URL is `http://five-small-snowflake.site` (see `lib/config/server_defaults.dart`). After HTTPS is live, open **Cài đặt** and set `https://five-small-snowflake.site` and the same API key as in `.env`.
