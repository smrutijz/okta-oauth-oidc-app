#!/usr/bin/env bash
set -euo pipefail

DOMAIN=${1:? "Usage: $0 <domain> <email>"}
EMAIL=${2:? "Usage: $0 <domain> <email>"}

echo "➡️ Deploying app for: $DOMAIN"

# 1. Install Docker from Ubuntu's universe (docker.io)
sudo apt-get update -y
sudo apt-get install -y docker.io docker-compose-plugin

# 2. Ensure Docker daemon is enabled
sudo systemctl enable --now docker

# 3. Add your user to the docker group (so `docker compose` works without sudo)
sudo groupadd -f docker
sudo usermod -aG docker "${SUDO_USER:-$USER}" || true

# 4. Build and start your Flask app
docker compose build
docker compose up -d

# 5. Install Nginx & Certbot
sudo apt-get install -y nginx certbot python3-certbot-nginx

# 6. Temporary Nginx conf for certificate issuance
sudo tee /etc/nginx/sites-available/$DOMAIN.tmp >/dev/null <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  location /.well-known/acme-challenge/ { root /var/www/html; }
  location / { return 200 'OK'; add_header Content-Type text/plain; }
}
EOF
sudo ln -sf /etc/nginx/sites-available/$DOMAIN.tmp /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 7. Obtain SSL certificate
sudo certbot --nginx --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

# 8. Final HTTPS reverse proxy setup
sudo tee /etc/nginx/sites-available/$DOMAIN >/dev/null <<EOF
server {
  listen 80;
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

echo "✅ Deployment complete for https://$DOMAIN"
echo "⚠️ Run 'newgrp docker' or re-login to use Docker without sudo."
