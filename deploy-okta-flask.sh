#!/usr/bin/env bash
set -euo pipefail

DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"

echo "📦 Installing Docker, Nginx & Certbot..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io nginx certbot python3-certbot-nginx git

echo "🚀 Enabling Docker..."
systemctl enable --now docker

# Initial Nginx placeholder to allow Certbot validation
echo "⚙️ Setting up temporary Nginx config for domain verification..."
cat > "$NGINX_CONF_DIR/$DOMAIN.init" <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  location / {
    return 200 'OK';
    add_header Content-Type text/plain;
  }
}
EOF
ln -sf "$NGINX_CONF_DIR/$DOMAIN.init" "$NGINX_ENABLED_DIR/$DOMAIN.init"
systemctl reload nginx

echo "🔐 Obtaining SSL certificate..."
certbot --non-interactive --agree-tos --nginx -m "$EMAIL" \
  -d "$DOMAIN"

# Remove placeholder and write final SSL-enabled config
echo "🛠️ Writing final Nginx config with SSL..."
cat > "$NGINX_CONF_DIR/$DOMAIN" <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}
server {
  listen 443 ssl http2;
  server_name $DOMAIN;

  ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
  include             /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    proxy_pass http://localhost:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

# Swap configs
rm -f "$NGINX_ENABLED_DIR/$DOMAIN.init"
ln -sf "$NGINX_CONF_DIR/$DOMAIN" "$NGINX_ENABLED_DIR/$DOMAIN"
systemctl reload nginx

echo "🐳 Launching your application via Docker Compose..."
docker-compose up --build -d

echo -n "⏳ Waiting for your app to respond..."
until curl -fs http://localhost:8080 >/dev/null; do
  printf "."
  sleep 2
done

echo "✅ Application is ready at https://$DOMAIN!"
