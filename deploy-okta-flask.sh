# ... after installing Docker, Nginx, Certbot ...

echo "⚙️ Configuring temporary Nginx for HTTP validation..."
cat > "$NGINX_CONF_DIR/$DOMAIN.init" <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 200 'OK';
}
EOF
ln -sf "$NGINX_CONF_DIR/$DOMAIN.init" "$NGINX_ENABLED_DIR/$DOMAIN.init"
systemctl reload nginx

echo "🔐 Running Certbot to obtain SSL cert..."
certbot --non-interactive --agree-tos --nginx -m "$EMAIL" -d "$DOMAIN"

echo "🛠️ Writing full HTTPS Nginx config..."
cat > "$NGINX_CONF_DIR/$DOMAIN" <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  http2 on;
  server_name $DOMAIN;

  ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
  include             /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    proxy_pass http://localhost:8080;
    # ... proxy headers ...
  }
}
EOF

rm -f "$NGINX_ENABLED_DIR/$DOMAIN.init"
ln -sf "$NGINX_CONF_DIR/$DOMAIN" "$NGINX_ENABLED_DIR/$DOMAIN"
systemctl reload nginx
