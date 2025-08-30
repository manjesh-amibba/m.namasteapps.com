#!/bin/bash
set -e

# Domains
MAIN_DOMAIN="namasteapps.com"
SUB_DOMAIN="m.namasteapps.com"

# Apache Document Roots
MAIN_DOC_ROOT="/var/www/namasteapps.com/public"
SUB_DOC_ROOT="/var/www/m.namasteapps.com/public"

# Apache Configs
MAIN_CONF="/etc/apache2/sites-available/$MAIN_DOMAIN.conf"
SUB_CONF="/etc/apache2/sites-available/$SUB_DOMAIN.conf"

# SSL Paths (already copied)
MAIN_SSL="/var/www/namasteapps.com/ssl"
SUB_SSL="/var/www/m.namasteapps.com/ssl"

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup_local.sh)"
  exit 1
fi

echo "=== Installing Apache if missing ==="
apt update
apt install -y apache2

# Enable required Apache modules
echo "=== Enabling Apache modules ==="
a2enmod ssl rewrite headers

# Create VirtualHost for MAIN domain
if [ ! -f "$MAIN_CONF" ]; then
  echo "=== Creating VirtualHost for $MAIN_DOMAIN ==="
  cat > "$MAIN_CONF" <<EOF
<VirtualHost *:443>
    ServerName $MAIN_DOMAIN
    DocumentRoot $MAIN_DOC_ROOT

    <Directory $MAIN_DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile $MAIN_SSL/$MAIN_DOMAIN.crt
    SSLCertificateKeyFile $MAIN_SSL/$MAIN_DOMAIN.key
    SSLCertificateChainFile $MAIN_SSL/$MAIN_DOMAIN.chain.crt
</VirtualHost>
EOF
fi

# Create VirtualHost for SUB domain
if [ ! -f "$SUB_CONF" ]; then
  echo "=== Creating VirtualHost for $SUB_DOMAIN ==="
  cat > "$SUB_CONF" <<EOF
<VirtualHost *:443>
    ServerName $SUB_DOMAIN
    DocumentRoot $SUB_DOC_ROOT

    <Directory $SUB_DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile $SUB_SSL/$SUB_DOMAIN.crt
    SSLCertificateKeyFile $SUB_SSL/$SUB_DOMAIN.key
    SSLCertificateChainFile $SUB_SSL/$SUB_DOMAIN.chain.crt
</VirtualHost>
EOF
fi

# Enable sites
a2ensite "$MAIN_DOMAIN.conf" "$SUB_DOMAIN.conf"

# Restart Apache
echo "=== Restarting Apache ==="
systemctl restart apache2

# Add writable folders if required
for dir in "/var/www/namasteapps.com/writable" "/var/www/m.namasteapps.com/writable"; do
    mkdir -p "$dir"
    chown -R www-data:www-data "$dir"
    chmod -R 775 "$dir"
done

# Add domains to /etc/hosts if missing
echo "=== Adding domains to /etc/hosts ==="
for domain in "namasteapps.com" "m.namasteapps.com"; do
    if ! grep -q "$domain" /etc/hosts; then
        echo "127.0.0.1 $domain" >> /etc/hosts
        echo "Added $domain to /etc/hosts"
    else
        echo "$domain already exists in /etc/hosts, skipping"
    fi
done


echo "=== Local setup completed for $MAIN_DOMAIN and $SUB_DOMAIN ==="
echo "You can now access them via https://$MAIN_DOMAIN and https://$SUB_DOMAIN (add entries in /etc/hosts if needed)"
