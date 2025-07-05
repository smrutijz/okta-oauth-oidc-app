#!/bin/bash

# Exit on error
set -e

# 🐳 Install Docker Engine
echo "🔧 Installing Docker Engine..."
sudo apt-get update
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# 🐳 Install Docker Compose Plugin (V2)
echo "🔧 Installing Docker Compose Plugin..."
sudo apt-get install -y docker-compose-plugin

# 🔁 Enable Docker service
echo "🔁 Enabling Docker service..."
sudo systemctl enable --now docker

# 🔐 Install Certbot for SSL
echo "🔐 Installing Certbot..."
sudo apt-get install -y certbot python3-certbot-nginx

# 🛠️ Configure Nginx
echo "🛠️ Configuring Nginx..."
sudo tee /etc/nginx/sites-available/okta.dev.smrutiaisolution.fun <<EOF
server {
  listen 80;
  server_name okta.dev.smrutiaisolution.fun;
  location / { return 200 'OK'; add_header Content-Type text/plain; }
}
EOF

# 🔗 Enable Nginx site
sudo ln -s /etc/nginx/sites-available/okta.dev.smrutiaisolution.fun /etc/nginx/sites-enabled/

# 🔄 Reload Nginx to apply changes
echo "🔄 Reloading Nginx..."
sudo nginx -t && sudo systemctl reload nginx

# 🔐 Obtain SSL certificate
echo "🔐 Obtaining SSL certificate..."
sudo certbot --non-interactive --agree-tos --nginx \
  -m "YOUR_EMAIL" -d okta.dev.smrutiaisolution.fun

# 🛠️ Final Nginx configuration
echo "🛠️ Finalizing Nginx configuration..."
sudo tee /etc/nginx/sites-available/okta.dev.smrutiaisolution.fun <<EOF
server {
  listen 80;
  server_name okta.dev.smrutiaisolution.fun;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  server_name okta.dev.smrutiaisolution.fun;

  ssl_certificate /etc/letsencrypt/live/okta.dev.smrutiaisolution.fun/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/okta.dev.smrutiaisolution.fun/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    proxy_pass http://localhost:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

# 🔗 Enable final Nginx site and reload
sudo ln -sf /etc/nginx/sites-available/okta.dev.smrutiaisolution.fun /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 🐳 Docker Compose setup
echo "🐳 Setting up Docker Compose..."
DOCKER_COMPOSE_VERSION="2.38.1"
DOCKER_COMPOSE_PATH="${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins/docker-compose"
mkdir -p "$(dirname "$DOCKER_COMPOSE_PATH")"
curl -SL "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64" -o "$DOCKER_COMPOSE_PATH"
chmod +x "$DOCKER_COMPOSE_PATH"

# 🐳 Docker Compose version check
echo "🐳 Verifying Docker Compose installation..."
docker compose version

# 🚀 Build and run Flask app using Docker Compose
echo "🚀 Building and running Flask app..."
docker compose -f ./docker-compose.yml up -d

echo "✅ Deployment complete!"
