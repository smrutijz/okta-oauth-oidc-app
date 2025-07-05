#!/usr/bin/env bash
set -euo pipefail

DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

echo "📦 Installing Docker, Nginx, Certbot & Git..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io nginx certbot python3-certbot-nginx git

echo "🚀 Enabling Docker..."
systemctl enable --now docker

echo "🔁 Starting initial HTTP-only Nginx config..."
cat > "$NGINX_AVAILABLE/$DOMAIN" <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }
  location / {
    return 200 'OK';
    add_header Content-Type text/plain;
  }
}
EOF

ln -sf "$NGINX_AVAILABLE/$DOMAIN" "$NGINX_ENABLED/$DOMAIN"
nginx -t
systemctl reload nginx

echo "🔐 Issuing SSL certificate for $DOMAIN..."
certbot --non-interactive --agree-tos --email "$EMAIL" \
  --nginx -d "$DOMAIN"

echo "⚙️ Writing final HTTPS Nginx config..."
cat > "$NGINX_AVAILABLE/$DOMAIN" <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  http2 on;

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

systemctl reload nginx

echo "🐳 Building and launching your Flask app..."
docker-compose up --build -d

echo -n "⏳ Waiting for the app to become available..."
until curl -fs http://localhost:8080 >/dev/null; do
  printf "."
  sleep 2
done

echo "✅ Deployment successful! Your application is available at: https://$DOMAIN"
