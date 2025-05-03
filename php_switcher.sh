#!/bin/bash
# PHP Version Switcher for Websites
# Usage: switch-site-php domain.com php_version

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 
   exit 1
fi

# Check parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 domain.com php_version"
    echo "Available PHP versions: 7.4, 8.0, 8.1, 8.2"
    exit 1
fi

DOMAIN=$1
PHP_VERSION=$2

# Validate PHP version
if [[ ! "$PHP_VERSION" =~ ^(7.4|8.0|8.1|8.2)$ ]]; then
    echo "Error: Invalid PHP version. Available versions: 7.4, 8.0, 8.1, 8.2"
    exit 1
fi

# Check if PHP version is installed
if [ ! -f "/usr/sbin/php-fpm$PHP_VERSION" ]; then
    echo "Error: PHP $PHP_VERSION is not installed"
    exit 1
fi

# Check if site exists
if [ ! -f "/etc/nginx/sites-available/$DOMAIN.conf" ]; then
    echo "Error: Site $DOMAIN does not exist"
    exit 1
fi

echo "Switching $DOMAIN to PHP $PHP_VERSION..."

# Update Nginx configuration
sed -i "s|fastcgi_pass unix:/var/run/php/php[0-9]\.[0-9]-fpm.sock;|fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;|g" "/etc/nginx/sites-available/$DOMAIN.conf"

# Update Apache configuration if it exists
if [ -f "/etc/apache2/sites-available/$DOMAIN.conf" ]; then
    sed -i "s|SetHandler \"proxy:unix:/var/run/php/php[0-9]\.[0-9]-fpm.sock|fcgi://localhost\"|SetHandler \"proxy:unix:/var/run/php/php$PHP_VERSION-fpm.sock|fcgi://localhost\"|g" "/etc/apache2/sites-available/$DOMAIN.conf"
fi

# Create an info file to track PHP version
echo "$PHP_VERSION" > "/sites/$DOMAIN/php_version.txt"

# Reload web servers
systemctl reload nginx
systemctl reload apache2

echo "Site $DOMAIN is now using PHP $PHP_VERSION"

# Show current PHP info page
echo "Creating PHP info page..."
cat > "/sites/$DOMAIN/public_html/phpinfo.php" << EOL
<?php
// Show all information, defaults to INFO_ALL
phpinfo();
?>
EOL

echo "PHP info page created at http://$DOMAIN/phpinfo.php"
echo "Remember to delete this file in production environments!"
