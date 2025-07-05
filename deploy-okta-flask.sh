#!/usr/bin/env bash
set -euo pipefail

# Ensure domain and email are provided
DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

# Define paths
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
APP_DIR="/app"

# Install necessary packages
echo "📦 Installing Docker, Nginx & Certbot..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io \
  nginx \
  certbot \
  python3-certbot-nginx \
  git

# Enable Docker service
echo "🚀 Enabling Docker..."
systemctl enable --now docker


# Configure Nginx for the domain
echo "🛠️ Configuring Nginx..."
mkdir -p $NGINX_CONF_DIR
cat <<EOF > $NGINX_CONF_DIR/$DOMAIN
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

# Enable the Nginx site configuration
ln -sf $NGINX_CONF_DIR/$DOMAIN $NGINX_ENABLED_DIR/$DOMAIN

# Reload Nginx to apply changes
systemctl reload nginx

# Obtain SSL certificate using Certbot
echo "🔐 Obtaining SSL certificate..."
certbot --non-interactive --agree-tos --nginx --redirect -m "$EMAIL" -d "$DOMAIN"

# Build and start the application using Docker Compose
echo "🐳 Building and starting the application..."
docker-compose up --build -d

# Wait for the application to be ready
echo -n "⏳ Waiting for the application to start..."
until curl -fs http://localhost:8080 >/dev/null; do
  printf "."
  sleep 2
done
echo " ✅ Application is ready!"

echo "🎉 Deployment complete — access your application at: https://$DOMAIN"