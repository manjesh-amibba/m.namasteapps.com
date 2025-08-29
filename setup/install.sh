#!/bin/bash

# Domains
MAIN_DOMAIN="namasteapps.com"
SUB_DOMAIN="m.$MAIN_DOMAIN"

# Document Roots
MAIN_DOC_ROOT="/var/www/$MAIN_DOMAIN"
SUB_DOC_ROOT="/var/www/$SUB_DOMAIN"

# Apache Configs
MAIN_CONF="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"
SUB_CONF="/etc/apache2/sites-available/$SUB_DOMAIN.conf"

# Git Repositories
MAIN_REPO="git@github.com:manjesh-amibba/namasteapps.com.git"
SUB_REPO="https://github.com/manjesh-amibba/m.namasteapps.com.git"

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

echo "=== Installing Apache, Git & Certbot if missing ==="
apt update
apt install -y apache2 git certbot python3-certbot-apache

# Create Document Roots
echo "=== Creating Document Roots ==="
mkdir -p "$MAIN_DOC_ROOT" "$SUB_DOC_ROOT"
chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/

# Clone Git repositories if not already present
if [ ! -d "$MAIN_DOC_ROOT/.git" ]; then
  echo "=== Cloning repository for $MAIN_DOMAIN ==="
  git clone "$MAIN_REPO" "$MAIN_DOC_ROOT"
else
  echo "=== Repository already exists for $MAIN_DOMAIN, skipping clone ==="
fi

if [ ! -d "$SUB_DOC_ROOT/.git" ]; then
  echo "=== Cloning repository for $SUB_DOMAIN ==="
  git clone "$SUB_REPO" "$SUB_DOC_ROOT"
else
  echo "=== Repository already exists for $SUB_DOMAIN, skipping clone ==="
fi

# Ensure writable folders exist and set secure permissions
echo "=== Setting writable folder permissions (safe: 775 + www-data) ==="
mkdir -p "$MAIN_DOC_ROOT/writable" "$SUB_DOC_ROOT/writable"
chown -R www-data:www-data "$MAIN_DOC_ROOT/writable" "$SUB_DOC_ROOT/writable"
chmod -R 775 "$MAIN_DOC_ROOT/writable" "$SUB_DOC_ROOT/writable"

# Create Main Domain VirtualHost (only if not exists)
if [ ! -f "$MAIN_CONF" ]; then
  echo "=== Creating Apache VirtualHost for $MAIN_DOMAIN ==="
  cat > "$MAIN_CONF" <<EOF
<VirtualHost *:80>
    ServerName $MAIN_DOMAIN
    ServerAlias www.$MAIN_DOMAIN
    DocumentRoot $MAIN_DOC_ROOT

    <Directory $MAIN_DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Redirect www to non-www
    RewriteEngine On
    RewriteCond %{HTTP_HOST} ^www\.$MAIN_DOMAIN$ [NC]
    RewriteRule ^(.*)$ https://$MAIN_DOMAIN/\$1 [L,R=301]
</VirtualHost>
EOF
fi

# Create Subdomain VirtualHost (only if not exists)
if [ ! -f "$SUB_CONF" ]; then
  echo "=== Creating Apache VirtualHost for $SUB_DOMAIN ==="
  cat > "$SUB_CONF" <<EOF
<VirtualHost *:80>
    ServerName $SUB_DOMAIN
    DocumentRoot $SUB_DOC_ROOT

    <Directory $SUB_DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
fi

# Enable Apache Modules and Sites
echo "=== Enabling Apache Modules and Sites ==="
a2enmod rewrite ssl headers
a2ensite "$MAIN_DOMAIN.conf" "$SUB_DOMAIN.conf"
systemctl reload apache2

# Obtain SSL Certificates (safe, will not revoke existing certs)
echo "=== Obtaining SSL Certificates with Let's Encrypt ==="
certbot --apache -d $MAIN_DOMAIN -d www.$MAIN_DOMAIN -d $SUB_DOMAIN --non-interactive --agree-tos -m admin@$MAIN_DOMAIN

# Add HTTPS redirect if not already present
if ! grep -q "RewriteCond %{HTTPS}" "$MAIN_CONF"; then
  sed -i '/<\/VirtualHost>/i \
    RewriteEngine On\n    RewriteCond %{HTTPS} off\n    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]\n' "$MAIN_CONF"
fi

if ! grep -q "RewriteCond %{HTTPS}" "$SUB_CONF"; then
  sed -i '/<\/VirtualHost>/i \
    RewriteEngine On\n    RewriteCond %{HTTPS} off\n    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]\n' "$SUB_CONF"
fi

# Restart Apache safely
echo "=== Restarting Apache ==="
systemctl restart apache2

echo "=== Setup Completed Successfully for $MAIN_DOMAIN and $SUB_DOMAIN ==="
