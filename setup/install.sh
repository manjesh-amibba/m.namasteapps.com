#!/bin/bash
set -e

# Domains
MAIN_DOMAIN="namasteapps.com"
SUB_DOMAIN="m.$MAIN_DOMAIN"

# Document Roots
MAIN_DOC_ROOT="/var/www/$MAIN_DOMAIN/public"
SUB_DOC_ROOT="/var/www/$SUB_DOMAIN/public"

# Git Root Paths
MAIN_GIT_ROOT="/var/www/$MAIN_DOMAIN"
SUB_GIT_ROOT="/var/www/$SUB_DOMAIN"

# Apache Configs
MAIN_CONF="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"
SUB_CONF="/etc/apache2/sites-available/$SUB_DOMAIN.conf"

# Git Repositories
MAIN_REPO="git@github.com:manjesh-amibba/namasteapps.com.git"
SUB_REPO="https://github.com/manjesh-amibba/m.namasteapps.com.git"

# SSL Paths
SSL_SRC_MAIN="/etc/letsencrypt/live/$MAIN_DOMAIN"
SSL_DEST_MAIN="$MAIN_GIT_ROOT/ssl"

SSL_SRC_SUB="/etc/letsencrypt/live/$SUB_DOMAIN"
SSL_DEST_SUB="$SUB_GIT_ROOT/ssl"

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
clone_or_pull() {
  local REPO=$1
  local DIR=$2

  if [ -d "$DIR/.git" ]; then
    echo "=== Pulling latest changes for $DIR ==="
    git -C "$DIR" reset --hard
    git -C "$DIR" pull
  elif [ -z "$(ls -A $DIR)" ]; then
    echo "=== Cloning repository into $DIR ==="
    git clone "$REPO" "$DIR"
  else
    echo "⚠️ $DIR exists and is not a git repository. Skipping clone."
  fi
}

clone_or_pull "$MAIN_REPO" "$MAIN_GIT_ROOT"
clone_or_pull "$SUB_REPO" "$SUB_GIT_ROOT"

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
add_https_redirect() {
  local CONF=$1
  if ! grep -q "RewriteCond %{HTTPS}" "$CONF"; then
    sed -i '/<\/VirtualHost>/i \
    RewriteEngine On\n    RewriteCond %{HTTPS} off\n    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]\n' "$CONF"
  fi
}

add_https_redirect "$MAIN_CONF"
add_https_redirect "$SUB_CONF"

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
    target="$DEST/$DOMAIN.${file/.pem/.crt}"
    if [ "$SRC/$file" -nt "$target" ] || [ ! -f "$target" ]; then
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
