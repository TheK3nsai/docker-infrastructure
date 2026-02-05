#!/bin/sh
set -e

echo "Checking InvoicePlane installation..."

# Check if already installed
if [ -f /var/www/invoiceplane/index.php ] && [ -f /var/www/invoiceplane/.version ] && [ "$(cat /var/www/invoiceplane/.version)" = "1.7.0" ]; then
    echo "InvoicePlane 1.7.0 already installed"
else
    echo "Downloading InvoicePlane 1.7.0..."

    # Download release
    wget -q -O /tmp/invoiceplane.zip https://github.com/InvoicePlane/InvoicePlane/releases/download/v1.7.0/v1.7.0.zip

    # Extract to shared volume
    echo "Extracting..."
    unzip -q /tmp/invoiceplane.zip -d /tmp/

    # Copy files (the zip extracts to 'ip' directory)
    cp -a /tmp/ip/. /var/www/invoiceplane/

    # Mark version
    echo "1.7.0" > /var/www/invoiceplane/.version

    # Cleanup
    rm -rf /tmp/invoiceplane.zip /tmp/ip

    echo "InvoicePlane 1.7.0 installed"
fi

# Ensure ipconfig.php exists
if [ ! -f /var/www/invoiceplane/ipconfig.php ] && [ -f /var/www/invoiceplane/ipconfig.php.example ]; then
    cp /var/www/invoiceplane/ipconfig.php.example /var/www/invoiceplane/ipconfig.php
    echo "Created ipconfig.php from example"
fi

# Set permissions
echo "Setting permissions..."
chown -R www-data:www-data /var/www/invoiceplane
chmod -R o+rX /var/www/invoiceplane

# Ensure uploads directory exists and is writable
mkdir -p /var/www/invoiceplane/uploads
chmod 775 /var/www/invoiceplane/uploads

echo "Init complete, starting PHP-FPM..."
exec docker-php-entrypoint php-fpm "$@"
