#!/usr/bin/env bash
#
# One-shot setup for the Seamly FastAPI backend on an Oracle Cloud Free Tier VM.
#
# BEFORE RUNNING:
#   1) Create a free Oracle Cloud VM (Ubuntu 22.04/24.04, SSH key, open ports 80 & 443
#      in the VCN security list).
#   2) Make sure the Seamly backend code is on the VM at /opt/seamly/backend
#      (e.g.  scp -r backend root@<vm-ip>:/opt/seamly/backend )
#   3) Create a free DuckDNS subdomain (https://duckdns.org) and note its token:
#          DUCKDNS_DOMAIN  e.g. seamly-backend  (-> seamly-backend.duckdns.org)
#          DUCKDNS_TOKEN   token from the DuckDNS account page
#      Point the DuckDNS A record at your VM's public IP (the script can do this
#      automatically with the token; empty "ip=" uses your source IP).
#   4) Set FRONTEND_ORIGIN to your Firebase-hosted frontend origin.
#
# RUN (as root):
#   FRONTEND_ORIGIN=https://seamly-web.web.app \
#   DUCKDNS_DOMAIN=seamly-backend \
#   DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#   bash oracle_setup.sh
#
set -euo pipefail

FRONTEND_ORIGIN="${FRONTEND_ORIGIN:-}"
DUCKDNS_DOMAIN="${DUCKDNS_DOMAIN:-seamly-backend}"
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"
DOMAIN="${DUCKDNS_DOMAIN}.duckdns.org"
ACME_EMAIL="${ACME_EMAIL:-seamly@example.com}"
DATABASE_URL="${DATABASE_URL:-}"
APP_DIR="/opt/seamly/backend"

if [ -z "$FRONTEND_ORIGIN" ]; then
  echo "ERROR: set FRONTEND_ORIGIN (the origin of the Firebase web app)." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "Run this script on Ubuntu via sudo." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating system and installing packages..."
apt-get update -y
apt-get install -y python3 python3-venv python3-pip nginx certbot python3-certbot-nginx curl

echo "==> Pointing DuckDNS A record at this VM..."
if [ -n "$DUCKDNS_TOKEN" ]; then
  curl -s "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" || true
else
  echo "    Skipped (no DUCKDNS_TOKEN). Set the A record manually in the DuckDNS dashboard."
fi

echo "==> Installing Python dependencies..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

echo "==> Creating backend systemd service..."
cat > /etc/systemd/system/seamly-api.service <<EOF
[Unit]
Description=Seamly FastAPI backend
After=network.target

[Service]
WorkingDirectory=${APP_DIR}
Environment=CORS_ALLOWED_ORIGINS=${FRONTEND_ORIGIN}
Environment=DATABASE_URL=${DATABASE_URL}
ExecStart=${APP_DIR}/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now seamly-api

echo "==> Starting service and checking /health..."
sleep 3
curl -fsS http://127.0.0.1:8000/health || {
  echo "Backend /health check failed - see: journalctl -u seamly-api" >&2
  exit 1
}

echo "==> Configuring nginx reverse proxy..."
cat > /etc/nginx/sites-available/seamly <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/seamly /etc/nginx/sites-enabled/seamly
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> Enabling firewall for HTTP/HTTPS..."
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

echo "==> Requesting HTTPS certificate with Let's Encrypt..."
certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${ACME_EMAIL}" --redirect || {
  echo "certbot failed. Check that ${DOMAIN} resolves to this VM's public IP and that ports 80/443 are open." >&2
  echo "Backend is still running at http://127.0.0.1:8000" >&2
  exit 1
}
systemctl enable certbot.timer >/dev/null 2>&1 || true

echo
echo "============================================================"
echo " DONE. Backend is live at:"
echo "   https://${DOMAIN}"
echo "   https://${DOMAIN}/health"
echo
echo " Frontend must be built with API_BASE_URL=https://${DOMAIN}"
echo " CORS allows origin: ${FRONTEND_ORIGIN}"
echo " Logs: journalctl -u seamly-api -f"
echo "============================================================"