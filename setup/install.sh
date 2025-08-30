#!/bin/bash
set -e

# Domains
MAIN_DOMAIN="namasteapps.com"
SUB_DOMAIN="m.$MAIN_DOMAIN"

# Document Roots
MAIN_DOC_ROOT="/var/www/$MAIN_DOMAIN/public"
SUB_DOC_ROOT="/var/www/$SUB_DOMAIN/public"

# Apache Configs
MAIN_CONF="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"
SUB_CONF="/etc/apache2/sites-available/$SUB_DOMAIN.conf"

# Git Repositories
MAIN_REPO="git@github.com:manjesh-amibba/namasteapps.com.git"
SUB_REPO="https://github.com/manjesh-amibba/m.namasteapps.com.git"

# SSL Paths
SSL_SRC_MAIN="/etc/letsencrypt/live/$MAIN_DOMAIN"
SSL_DEST_MAIN="/var/www/$MAIN_DOMAIN/ssl"

SSL_SRC_SUB="/etc/letsencrypt/live/$SUB_DOMAIN"
SSL_DEST_SUB="/var/www/$SUB_DOMAIN/ssl"

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

echo "=== Installing Apache, Git & Certbot if missing ==="
apt update
apt install -y apache2 git certbot python3-certbot-apache

# Create Document Roots
echo "=== Creating Document Roots if missing ==="
mkdir -p "$MAIN_DOC_ROOT" "$SUB_DOC_ROOT"
chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/

# Clone or Pull Git Repositories
if [ -d "$MAIN_DOC_ROOT/.git" ]; then
  echo "=== Pulling latest changes for $MAIN_DOMAIN ==="
  git -C "$MAIN_DOC_ROOT" reset --hard
  git -C "$MAIN_DOC_ROOT" pull
else
  echo "=== Cloning repository for $MAIN_DOMAIN ==="
  git clone "$MAIN_REPO" "$MAIN_DOC_ROOT"
fi

if [ -d "$SUB_DOC_ROOT/.git" ]; then
  echo "=== Pulling latest changes for $SUB_DOMAIN ==="
  git -C "$SUB_DOC_ROOT" reset --hard
  git -C "$SUB_DOC_ROOT" pull
else
  echo "=== Cloning repository for $SUB_DOMAIN ==="
  git clone "$SUB_REPO" "$SUB_DOC_ROOT"
fi

# Ensure writable folders exist
echo "=== Ensuring writable folders ==="
mkdir -p "$MAIN_DOC_ROOT/writable" "$SUB_DOC_ROOT/writable"
chown -R www-data:www-data "$MAIN_DOC_ROOT/writable" "$SUB_DOC_ROOT/writable"
chmod -R 775 "$MAIN_DOC_ROOT/writable" "$SUB_DOC_ROOT/writable"

# Create Apache VirtualHost configs only if missing
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

    RewriteEngine On
    RewriteCond %{HTTP_HOST} ^www\.$MAIN_DOMAIN$ [NC]
    RewriteRule ^(.*)$ https://$MAIN_DOMAIN/\$1 [L,R=301]
</VirtualHost>
EOF
fi

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
a2enmod rewrite ssl headers || true
a2ensite "$MAIN_DOMAIN.conf" "$SUB_DOMAIN.conf" || true
systemctl reload apache2

# Obtain SSL Certificates only if not already valid
echo "=== Checking SSL Certificates ==="
if ! certbot certificates | grep -q "$MAIN_DOMAIN"; then
  echo "=== Obtaining SSL Certificates ==="
  certbot --apache -d $MAIN_DOMAIN -d www.$MAIN_DOMAIN -d $SUB_DOMAIN --non-interactive --agree-tos -m admin@$MAIN_DOMAIN
else
  echo "=== SSL Certificates already exist, skipping ==="
fi

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

# Copy SSL files only if updated
copy_ssl_files() {
  local SRC=$1
  local DEST=$2
  local DOMAIN=$3

  echo "=== Syncing SSL files for $DOMAIN ==="
  mkdir -p "$DEST"

  for file in cert.pem chain.pem privkey.pem; do
    if [ "$SRC/$file" -nt "$DEST/$DOMAIN.${file/.pem/.crt}" ]; then
      case $file in
        cert.pem) cp "$SRC/$file" "$DEST/$DOMAIN.crt" ;;
        chain.pem) cp "$SRC/$file" "$DEST/$DOMAIN.chain.crt" ;;
        privkey.pem) cp "$SRC/$file" "$DEST/$DOMAIN.key" ;;
      esac
    fi
  done
}

copy_ssl_files "$SSL_SRC_MAIN" "$SSL_DEST_MAIN" "$MAIN_DOMAIN"
copy_ssl_files "$SSL_SRC_SUB" "$SSL_DEST_SUB" "$SUB_DOMAIN"

echo "=== Setup Completed Successfully for $MAIN_DOMAIN and $SUB_DOMAIN ==="
