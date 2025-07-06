#!/usr/bin/env bash
set -euo pipefail

DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

echo "➡️ Deploying Flask-Okta app at: $DOMAIN"

# 1. Install Docker & Compose plugin
echo "📦 Installing Docker & Compose..."
sudo apt-get update -y
sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release \
  docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 2. Start Docker and allow non-root access
echo "🚀 Enabling Docker..."
sudo systemctl enable --now docker
sudo groupadd -f docker
sudo usermod -aG docker "${SUDO_USER:-$USER}" || true

# 3. Prepare Flask project
echo "🔧 Building Flask container..."
docker compose build

echo "🧪 Starting Flask app..."
docker compose up -d

# 4. Install Nginx & Certbot
echo "📦 Installing Nginx & Certbot..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

# 5. Temporary Nginx setup for cert issuance
echo "🛡️ ./ Creating temp HTTP Nginx config..."
sudo tee /etc/nginx/sites-available/$DOMAIN.tmp >/dev/null <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  root /var/www/html;
  location /.well-known/acme-challenge/ { allow all; }
  location / { return 200 'OK'; add_header Content-Type text/plain; }
}
EOF
sudo ln -sf /etc/nginx/sites-available/$DOMAIN.tmp /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 6. Get SSL certificate
echo "🔐 Requesting SSL from Let's Encrypt..."
sudo certbot --non-interactive --agree-tos \
  --email "$EMAIL" --nginx -d "$DOMAIN"

# 7. Final HTTPS Nginx config
echo "🛡️ ./ Writing HTTPS reverse proxy config..."
sudo tee /etc/nginx/sites-available/$DOMAIN >/dev/null <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name $DOMAIN;

  ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
  include             /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    proxy_pass http://localhost:8080;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/$DOMAIN.tmp
sudo nginx -t && sudo systemctl reload nginx

echo "✅ Deployment complete!"
echo "Visit: https://$DOMAIN"
echo "ℹ️ If you want to run Docker without sudo, log out then back in (or run: newgrp docker)"
