#!/bin/bash
set -e

# Domains
MAIN_DOMAIN="namasteapps.com"
SUB_DOMAIN="m.$MAIN_DOMAIN"

# Git Clone Paths
MAIN_GIT="/var/www/$MAIN_DOMAIN"
SUB_GIT="/var/www/$SUB_DOMAIN"

# Apache Document Roots (inside git repo)
MAIN_DOC_ROOT="$MAIN_GIT/public"
SUB_DOC_ROOT="$SUB_GIT/public"

# Apache Configs
MAIN_CONF="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"
SUB_CONF="/etc/apache2/sites-available/$SUB_DOMAIN.conf"

# Git Repositories
MAIN_REPO="git@github.com:manjesh-amibba/namasteapps.com.git"
SUB_REPO="git@github.com:manjesh-amibba/m.namasteapps.com.git"

# SSL Paths
SSL_SRC_MAIN="/etc/letsencrypt/live/$MAIN_DOMAIN"
SSL_DEST_MAIN="$MAIN_GIT/ssl"
SSL_SRC_SUB="/etc/letsencrypt/live/$SUB_DOMAIN"
SSL_DEST_SUB="$SUB_GIT/ssl"

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

echo "=== Installing Apache, Git & Certbot if missing ==="
apt update
apt install -y apache2 git certbot python3-certbot-apache

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

clone_or_pull "$MAIN_REPO" "$MAIN_GIT"
clone_or_pull "$SUB_REPO" "$SUB_GIT"

# Create Apache VirtualHost configs if missing
create_vhost() {
  local DOMAIN=$1
  local DOC_ROOT=$2
  local CONF=$3
  local ALIAS=$4

  if [ ! -f "$CONF" ]; then
    echo "=== Creating Apache VirtualHost for $DOMAIN ==="
    cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    $( [ -n "$ALIAS" ] && echo "ServerAlias $ALIAS" )
    DocumentRoot $DOC_ROOT

    <Directory $DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
  fi
}

create_vhost "$MAIN_DOMAIN" "$MAIN_DOC_ROOT" "$MAIN_CONF" "www.$MAIN_DOMAIN"
create_vhost "$SUB_DOMAIN" "$SUB_DOC_ROOT" "$SUB_CONF" ""

# Enable Apache modules and sites
echo "=== Enabling Apache Modules and Sites ==="
a2enmod rewrite ssl headers || true
a2ensite "$MAIN_DOMAIN.conf" "$SUB_DOMAIN.conf" || true
systemctl reload apache2

# Obtain SSL Certificates if missing
echo "=== Checking SSL Certificates ==="
if ! certbot certificates | grep -q "$MAIN_DOMAIN"; then
  echo "=== Obtaining SSL Certificates ==="
  certbot --apache -d $MAIN_DOMAIN -d www.$MAIN_DOMAIN -d $SUB_DOMAIN --non-interactive --agree-tos -m admin@$MAIN_DOMAIN
else
  echo "=== SSL Certificates already exist, skipping ==="
fi

# Copy SSL files safely
copy_ssl() {
  local SRC=$1
  local DEST=$2
  local DOMAIN=$3

  echo "=== Copying SSL files for $DOMAIN ==="
  mkdir -p "$DEST"

  for file in cert.pem chain.pem privkey.pem; do
    target="$DEST/$DOMAIN.${file/.pem/.crt}"
    if [ ! -f "$target" ] || [ "$SRC/$file" -nt "$target" ]; then
      case $file in
        cert.pem) cp "$SRC/$file" "$DEST/$DOMAIN.crt" ;;
        chain.pem) cp "$SRC/$file" "$DEST/$DOMAIN.chain.crt" ;;
        privkey.pem) cp "$SRC/$file" "$DEST/$DOMAIN.key" ;;
      esac
    fi
  done
}

copy_ssl "$SSL_SRC_MAIN" "$SSL_DEST_MAIN" "$MAIN_DOMAIN"
copy_ssl "$SSL_SRC_SUB" "$SSL_DEST_SUB" "$SUB_DOMAIN"

# Restart Apache safely
echo "=== Restarting Apache ==="
systemctl restart apache2


# Ensure writable folders exist for runtime
echo "=== Ensuring runtime writable folders ==="
for dir in "$MAIN_GIT/writable" "$SUB_GIT/writable"; do
    mkdir -p "$dir"
    chown -R www-data:www-data "$dir"
    chmod -R 775 "$dir"
done


echo "=== Setup Completed Successfully for $MAIN_DOMAIN and $SUB_DOMAIN ==="
