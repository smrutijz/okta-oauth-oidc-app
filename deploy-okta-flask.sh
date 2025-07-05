#!/usr/bin/env bash
set -euo pipefail

# Load parameters
DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

echo "🏷️ Installing for domain: $DOMAIN with email: $EMAIL"

# 🐳 Docker Engine & Compose installation
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

# Docker Compose plugin install
DOCKER_COMPOSE_VERSION="v2.38.1"
sudo mkdir -p ~/.docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-$(dpkg --print-architecture)" \
  -o ~/.docker/cli-plugins/docker-compose
sudo chmod +x ~/.docker/cli-plugins/docker-compose

echo "– Docker Compose installed as 'docker compose'"

# 🔐 Certbot install
sudo apt-get install -y certbot python3-certbot-nginx

# 🛠️ Nginx temp config for HTTP
sudo tee /etc/nginx/sites-available/$DOMAIN <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  location / {
    return 200 'OK';
    add_header Content-Type text/plain;
  }
}
EOF
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx

# 🔐 Obtain SSL cert
sudo certbot --non-interactive --agree-tos \
  --email "$EMAIL" --nginx -d "$DOMAIN"

# 🛡️ Final HTTPS Nginx config
sudo tee /etc/nginx/sites-available/$DOMAIN <<EOF
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
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx

# 🚀 Run the app using Docker Compose
echo "🔧 Building and launching the Flask app..."
docker compose up --build -d

echo "✅ Deployment complete! 🎉"
echo "👉 Open https://$DOMAIN in your browser."