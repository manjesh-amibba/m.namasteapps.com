#!/bin/bash

# Variables
DOMAIN="m.namasteapps.com"
DOC_ROOT="/var/www/$DOMAIN"
APACHE_CONF="/etc/apache2/sites-available/$DOMAIN.conf"

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

echo "=== Updating system packages ==="
apt update && apt upgrade -y

echo "=== Installing Apache & Certbot ==="
apt install -y apache2 certbot python3-certbot-apache

echo "=== Creating Document Root ==="
mkdir -p "$DOC_ROOT"
chown -R www-data:www-data "$DOC_ROOT"
chmod -R 755 "$DOC_ROOT"

# Create a sample index.html
if [ ! -f "$DOC_ROOT/index.html" ]; then
  echo "<h1>Welcome to $DOMAIN</h1>" > "$DOC_ROOT/index.html"
fi

echo "=== Creating Apache VirtualHost file ==="
cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $DOC_ROOT

    <Directory $DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Redirect www to non-www
    RewriteEngine On
    RewriteCond %{HTTP_HOST} ^www\.$DOMAIN$ [NC]
    RewriteRule ^(.*)$ https://$DOMAIN/\$1 [L,R=301]

</VirtualHost>
EOF

echo "=== Enabling Apache Modules and Site ==="
a2enmod rewrite ssl headers
a2ensite "$DOMAIN.conf"
a2dissite 000-default.conf
systemctl reload apache2

echo "=== Obtaining SSL Certificate with Let's Encrypt ==="
certbot --apache -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

echo "=== Forcing HTTPS Redirect ==="
# Modify conf to always redirect HTTP -> HTTPS
sed -i '/<\/VirtualHost>/i \
    RewriteEngine On\n    RewriteCond %{HTTPS} off\n    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]\n' "$APACHE_CONF"

echo "=== Restarting Apache ==="
systemctl restart apache2

echo "=== Setup Completed Successfully for $DOMAIN ==="
