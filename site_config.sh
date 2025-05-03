#!/bin/bash
# Website Configuration Script
# This script configures a new website on the server with:
# - Nginx as frontend
# - Apache as backend for PHP processing
# - Support for multiple PHP versions
# - Log directories
# - Basic security settings

if [ -z "$1" ]; then
    echo "Error: No domain name provided"
    echo "Usage: $0 domain.com [php_version]"
    echo "Available PHP versions: 7.4, 8.0, 8.1, 8.2 (default: 8.0)"
    exit 1
fi

DOMAIN=$1
PHP_VERSION="${2:-8.0}"  # Default to PHP 8.0 if not specified

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

echo "Adding website for $DOMAIN with PHP $PHP_VERSION..."

# Create website directory
mkdir -p /sites/$DOMAIN/{public_html,logs,backup}
chmod -R 755 /sites/$DOMAIN
chown -R www-data:www-data /sites/$DOMAIN

# Create Nginx configuration
cat > /etc/nginx/sites-available/$DOMAIN.conf << EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Logging
    access_log /sites/$DOMAIN/logs/access.log;
    error_log /sites/$DOMAIN/logs/error.log;
    
    # Document root
    root /sites/$DOMAIN/public_html;
    index index.php index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
    
    # Static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
    
    # Process PHP with specific PHP-FPM version
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_intercept_errors on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 256 16k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
    }
    
    # Try files or run PHP via Apache if .htaccess rewrites are needed
    location / {
        try_files $uri $uri/ @apache;
    }
    
    location @apache {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $DOMAIN;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-PHP-Version $PHP_VERSION;
    }
    
    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOL

# Create Apache configuration
cat > /etc/apache2/sites-available/$DOMAIN.conf << EOL
<VirtualHost 127.0.0.1:8080>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    
    DocumentRoot /sites/$DOMAIN/public_html
    
    <Directory /sites/$DOMAIN/public_html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # PHP configuration for this vhost
    <FilesMatch \.php$>
        # Using the specific PHP-FPM version
        SetHandler "proxy:unix:/var/run/php/php$PHP_VERSION-fpm.sock|fcgi://localhost"
    </FilesMatch>
    
    ErrorLog /sites/$DOMAIN/logs/apache-error.log
    CustomLog /sites/$DOMAIN/logs/apache-access.log combined
</VirtualHost>
EOL

# Create sample index file
cat > /sites/$DOMAIN/public_html/index.php << EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $DOMAIN</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        .container {
            width: 80%;
            margin: 30px auto;
            padding: 20px;
            background: #fff;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 1px solid #eee;
            padding-bottom: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        table, th, td {
            border: 1px solid #ddd;
        }
        th, td {
            padding: 10px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to $DOMAIN</h1>
        <p>Your website is now successfully set up and running!</p>
        
        <h2>Server Information</h2>
        <table>
            <tr>
                <th>Item</th>
                <th>Value</th>
            </tr>
            <tr>
                <td>PHP Version</td>
                <td><?php echo phpversion(); ?></td>
            </tr>
            <tr>
                <td>Server Software</td>
                <td><?php echo $_SERVER['SERVER_SOFTWARE']; ?></td>
            </tr>
            <tr>
                <td>Server Name</td>
                <td><?php echo $_SERVER['SERVER_NAME']; ?></td>
            </tr>
            <tr>
                <td>Document Root</td>
                <td><?php echo $_SERVER['DOCUMENT_ROOT']; ?></td>
            </tr>
            <tr>
                <td>Server Time</td>
                <td><?php echo date('Y-m-d H:i:s'); ?></td>
            </tr>
        </table>
    </div>
</body>
</html>
EOL

# Create .htaccess file with basic settings
cat > /sites/$DOMAIN/public_html/.htaccess << EOL
# Basic .htaccess file
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    
    # Redirect www to non-www
    # RewriteCond %{HTTP_HOST} ^www\.(.*)$ [NC]
    # RewriteRule ^(.*)$ http://%1/$1 [R=301,L]
    
    # Force HTTPS (uncomment if using SSL)
    # RewriteCond %{HTTPS} off
    # RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
    
    # Common WordPress rules (uncomment if using WordPress)
    # RewriteRule ^index\.php$ - [L]
    # RewriteCond %{REQUEST_FILENAME} !-f
    # RewriteCond %{REQUEST_FILENAME} !-d
    # RewriteRule . /index.php [L]
</IfModule>

# PHP settings
<IfModule mod_php8.c>
    php_value upload_max_filesize 64M
    php_value post_max_size 64M
    php_value max_execution_time 300
    php_value max_input_time 300
</IfModule>

# Security headers
<IfModule mod_headers.c>
    Header set X-Content-Type-Options "nosniff"
    Header set X-XSS-Protection "1; mode=block"
    Header always append X-Frame-Options SAMEORIGIN
</IfModule>

# Prevent directory listing
Options -Indexes

# Prevent access to sensitive files
<FilesMatch "^(\.htaccess|\.htpasswd|\.git|\.env|composer\.json|composer\.lock)">
    Order Allow,Deny
    Deny from all
</FilesMatch>
EOL

# Enable the sites
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
a2ensite $DOMAIN.conf

# Set permissions
chown -R www-data:www-data /sites/$DOMAIN

# Reload web servers
systemctl reload nginx
systemctl reload apache2

echo "Website $DOMAIN has been added successfully!"
echo "Website files are located in: /sites/$DOMAIN/public_html"
echo "Nginx config: /etc/nginx/sites-available/$DOMAIN.conf"
echo "Apache config: /etc/apache2/sites-available/$DOMAIN.conf"
