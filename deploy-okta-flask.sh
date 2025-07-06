#!/usr/bin/env bash
set -euo pipefail

# Load parameters
DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

echo "🏷️ Installing for domain: $DOMAIN with email: $EMAIL"

# Install Docker Engine
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo tee /etc/apt/keyrings/docker.asc > /dev/null
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose plugin
sudo apt-get install -y docker-compose-plugin

echo "✅ Docker Compose installed and available as 'docker compose'"

# Install Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# Create temporary HTTP-only Nginx config for Let's Encrypt
sudo tee /etc/nginx/sites-available/$DOMAIN.tmp >/dev/null <<EOF
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
sudo ln -sf /etc/nginx/sites-available/$DOMAIN.tmp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Request SSL certificate via Certbot
sudo certbot --non-interactive --agree-tos --email "$EMAIL" --nginx -d "$DOMAIN"

# Create final HTTPS Nginx config
sudo tee /etc/nginx/sites-available/$DOMAIN >/dev/null <<EOF
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
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Launch the Flask app using Docker Compose
echo "🚀 Launching Flask app via Docker Compose..."
sudo systemctl start docker
sudo docker compose up --build -d

echo "✅ Deployment complete! 🎉"
echo "👉 Your app is available at: https://$DOMAIN"
