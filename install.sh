#!/bin/bash

# Web Server Installer Script
# This script installs and configures a complete web server with multiple PHP versions,
# Nginx, Apache2, phpMyAdmin, and various security measures.

# Exit on error
set -e

# Configuration variables
BASE_DIR="/cpanel"  # You can change this to your preferred directory

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display status messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
   error "This script must be run as root" 
   exit 1
fi

log "Starting web server installation..."

# Create base directory structure
log "Creating directory structure..."
mkdir -p $BASE_DIR
mkdir -p $BASE_DIR/apache2
mkdir -p $BASE_DIR/nginx
mkdir -p $BASE_DIR/php
mkdir -p $BASE_DIR/logs
mkdir -p $BASE_DIR/custom_panel
mkdir -p $BASE_DIR/ssl
mkdir -p $BASE_DIR/backup
mkdir -p $BASE_DIR/sites/default
mkdir -p $BASE_DIR/sites/custom

# Function to set base directory
set_base_directory() {
    log "Do you want to use the default base directory ($BASE_DIR)? (y/n)"
    read -r use_default_dir
    
    if [[ "$use_default_dir" =~ ^[Nn]$ ]]; then
        log "Please enter your preferred base directory path (e.g., /webserver):"
        read -r new_base_dir
        if [[ -n "$new_base_dir" ]]; then
            BASE_DIR="$new_base_dir"
            log "Base directory set to: $BASE_DIR"
        else
            log "Using default base directory: $BASE_DIR"
        fi
    else
        log "Using default base directory: $BASE_DIR"
    fi
}

# Function to update system packages
update_system() {
    log "Updating system packages..."
    apt update && apt upgrade -y
    apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y
}

# Install basic tools
install_basics() {
    log "Installing basic tools..."
    apt install -y curl wget unzip git software-properties-common apt-transport-https lsb-release ca-certificates net-tools
}

# Set up PHP repository
setup_php_repo() {
    log "Setting up PHP repository..."
    add-apt-repository -y ppa:ondrej/php
    apt update
}

# Install multiple PHP versions
install_php_versions() {
    log "Installing PHP versions..."
    
    # Define PHP versions to install
    PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
    
    for version in "${PHP_VERSIONS[@]}"; do
        log "Installing PHP $version..."
        apt install -y php$version php$version-fpm php$version-common php$version-mysql \
        php$version-xml php$version-xmlrpc php$version-curl php$version-gd \
        php$version-imagick php$version-cli php$version-dev php$version-imap \
        php$version-mbstring php$version-opcache php$version-soap php$version-zip php$version-intl
        
        # Configure PHP-FPM
        cp /etc/php/$version/fpm/pool.d/www.conf $BASE_DIR/php/php$version-fpm.conf
        
        # Create custom PHP-FPM configuration
        cat > $BASE_DIR/php/php$version-custom.conf << EOF
[global]
pid = /run/php/php$version-fpm.pid
error_log = $BASE_DIR/logs/php$version-fpm.log

[www]
user = www-data
group = www-data
listen = /run/php/php$version-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.status_path = /status
request_terminate_timeout = 300
EOF
        
        # Create symbolic links
        ln -sf $BASE_DIR/php/php$version-custom.conf /etc/php/$version/fpm/pool.d/www.conf
        
        # Restart PHP-FPM
        systemctl restart php$version-fpm
        systemctl enable php$version-fpm
    done
    
    # Set PHP 8.2 as default
    update-alternatives --set php /usr/bin/php8.2
}

# Install and configure Nginx
install_nginx() {
    log "Installing Nginx..."
    apt install -y nginx
    
    # Create Nginx configuration
    cat > $BASE_DIR/nginx/nginx.conf << EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    # multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    # Logging Settings
    access_log $BASE_DIR/logs/nginx-access.log;
    error_log $BASE_DIR/logs/nginx-error.log;

    # Gzip Settings
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Virtual Host Configs
    include $BASE_DIR/nginx/sites-enabled/*;
}
EOF

    # Create default site configuration
    mkdir -p $BASE_DIR/nginx/sites-available
    mkdir -p $BASE_DIR/nginx/sites-enabled
    
    cat > $BASE_DIR/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root $BASE_DIR/sites/default;
    index index.php index.html index.htm;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # Pass PHP scripts to PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
    
    # Deny access to .htaccess files
    location ~ /\.ht {
        deny all;
    }
    
    # Custom panel location
    location /cpanel {
        return 301 http://\$host:8080;
    }
}

# Custom panel server block
server {
    listen 8080;
    listen [::]:8080;
    
    root $BASE_DIR/custom_panel;
    index index.php index.html index.htm;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # Pass PHP scripts to PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
    
    # Deny access to .htaccess files
    location ~ /\.ht {
        deny all;
    }
}

# phpMyAdmin server block
server {
    listen 80;
    listen [::]:80;
    
    server_name phpmyadmin.*;
    
    location / {
        proxy_pass http://localhost:81;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

    # Create phpMyAdmin configuration
    cat > $BASE_DIR/nginx/sites-available/phpmyadmin << EOF
server {
    listen 81;
    listen [::]:81;
    
    server_name localhost;
    
    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;
    
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    # Pass PHP scripts to PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
    
    # Deny access to .htaccess files
    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Enable the sites
    ln -sf $BASE_DIR/nginx/sites-available/default $BASE_DIR/nginx/sites-enabled/
    ln -sf $BASE_DIR/nginx/sites-available/phpmyadmin $BASE_DIR/nginx/sites-enabled/
    
    # Create symbolic links for Nginx configuration
    ln -sf $BASE_DIR/nginx/nginx.conf /etc/nginx/nginx.conf
    
    # Create "Server is working" page
    cat > $BASE_DIR/sites/default/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Server is working!</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            text-align: center;
        }
        h1 {
            color: #333;
        }
    </style>
</head>
<body>
    <h1>Server is working!</h1>
    <p>Your web server is successfully installed and configured.</p>
</body>
</html>
EOF
    
    # Restart Nginx
    systemctl restart nginx
    systemctl enable nginx
}

# Install and configure Apache2
install_apache() {
    log "Installing Apache2..."
    apt install -y apache2
    
    # Configure Apache2
    cat > $BASE_DIR/apache2/apache2.conf << EOF
# Global configuration
ServerRoot "/etc/apache2"
Timeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# MPM settings
<IfModule mpm_prefork_module>
    StartServers             5
    MinSpareServers          5
    MaxSpareServers         10
    MaxRequestWorkers      150
    MaxConnectionsPerChild   0
</IfModule>

# Default server configuration
<VirtualHost 127.0.0.1:8000>
    ServerAdmin webmaster@localhost
    DocumentRoot $BASE_DIR/sites/default
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
    
    <Directory $BASE_DIR/sites/default>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

# Include other configuration files
Include $BASE_DIR/apache2/sites-enabled/*.conf
EOF

    # Create directories for Apache configuration
    mkdir -p $BASE_DIR/apache2/sites-available
    mkdir -p $BASE_DIR/apache2/sites-enabled
    
    # Create symbolic links
    ln -sf $BASE_DIR/apache2/apache2.conf /etc/apache2/apache2.conf
    
    # Enable required Apache modules
    a2enmod rewrite
    a2enmod headers
    a2enmod ssl
    a2enmod proxy
    a2enmod proxy_fcgi
    a2enmod setenvif
    
    # Configure PHP with Apache
    a2enconf php7.4-fpm
    a2enconf php8.0-fpm
    a2enconf php8.1-fpm
    a2enconf php8.2-fpm
    a2enconf php8.3-fpm
    
    log "Apache base installation completed."
}

# Install and configure phpMyAdmin
install_phpmyadmin() {
    log "Installing phpMyAdmin..."
    
    # Install mariadb-server if not already installed
    if ! command -v mysql &> /dev/null; then
        apt install -y mariadb-server
        systemctl start mariadb
        systemctl enable mariadb
        
        # Secure MariaDB installation
        log "Securing MariaDB installation..."
        mysql_secure_installation
    fi
    
    # Install phpMyAdmin
    apt install -y phpmyadmin
    
    # Create symlink for Nginx access
    ln -sf /usr/share/phpmyadmin $BASE_DIR/sites/default/phpmyadmin
    
    # Additional phpMyAdmin security
    log "Enhancing phpMyAdmin security..."
    echo "<?php
\$cfg['blowfish_secret'] = '$(openssl rand -hex 16)';
\$cfg['ExecTimeLimit'] = 300;
\$cfg['DefaultLang'] = 'en';
\$cfg['ServerDefault'] = 1;
\$cfg['ForceSSL'] = false;
\$cfg['AllowArbitraryServer'] = false;
\$cfg['LoginCookieValidity'] = 1440;
?>" > /etc/phpmyadmin/conf.d/custom.inc.php
    
    log "phpMyAdmin installation completed."
}

# Configure UFW (Uncomplicated Firewall)
configure_ufw() {
    log "Configuring UFW..."
    apt install -y ufw
    
    # Configure UFW
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow custom panel port
    ufw allow 8080/tcp
    
    # Allow Apache port
    ufw allow 8000/tcp
    
    # Allow phpMyAdmin internal port
    ufw allow from 127.0.0.1 to any port 81 proto tcp
    
    # Enable UFW
    echo "y" | ufw enable
    
    log "UFW configured and enabled."
}

# Configure fail2ban
configure_fail2ban() {
    log "Configuring fail2ban..."
    apt install -y fail2ban
    
    # Configure fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
maxretry = 5
findtime = 1d
bantime = 4w
ignoreip = 127.0.0.1/8 192.168.1.0/24
EOF
    
    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    log "fail2ban configured and enabled."
}


# Configure Nginx as proxy for Apache
configure_nginx_as_proxy() {
    log "Configuring Nginx as a reverse proxy for Apache..."
    
    # Create vhosts directory
    mkdir -p $BASE_DIR/nginx/vhosts
    
    # Create a sample vhost configuration
    cat > $BASE_DIR/nginx/vhosts/sample.conf.disabled << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name example.com www.example.com;
    
    # Logs
    access_log $BASE_DIR/logs/example.com-access.log;
    error_log $BASE_DIR/logs/example.com-error.log;
    
    # Root directory
    root $BASE_DIR/sites/example.com;
    index index.php index.html index.htm;
    
    # Handle static files with Nginx
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|pdf)$ {
        expires 30d;
        access_log off;
        add_header Cache-Control "public";
        try_files \$uri =404;
    }
    
    # Pass PHP requests to Apache
    location ~ \.php$ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Pass WordPress and other CMS with pretty URLs to Apache
    location / {
        try_files \$uri \$uri/ @apache;
    }
    
    location @apache {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Deny access to sensitive files
    location ~ /\.(ht|git|svn) {
        deny all;
    }
}
EOF

    # Create a PHP selector configuration
    cat > $BASE_DIR/nginx/vhosts/php-selector.conf.disabled << EOF
# PHP Version Selector - Include this in your server block
# Usage: include $BASE_DIR/nginx/vhosts/php-selector.conf

# PHP 7.4
location ~ \.php74$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
}

# PHP 8.0
location ~ \.php80$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.0-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
}

# PHP 8.1
location ~ \.php81$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
}

# PHP 8.2
location ~ \.php82$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
}

# PHP 8.3
location ~ \.php83$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
}
EOF

    # Create a PHP info file to test PHP versions
    cat > $BASE_DIR/sites/default/info.php << EOF
<?php
phpinfo();
EOF

    # Create PHP version test files
    for ver in 74 80 81 82 83; do
        cat > $BASE_DIR/sites/default/info.php${ver} << EOF
<?php
phpinfo();
EOF
    done

    # Grant proper permissions
    chown -R www-data:www-data $BASE_DIR/sites/default
    chmod -R 755 $BASE_DIR/sites/default

    # Add nginx include directories to main nginx.conf
    sed -i "/include \/etc\/nginx\/conf\.d\/\*\.conf;/a \    include $BASE_DIR/nginx/vhosts/*.conf;" /etc/nginx/nginx.conf

    log "Nginx proxy configuration completed."
}


# Configure Apache as backend server
configure_apache_backend() {
    log "Configuring Apache as a backend server..."
    
    # Create vhosts directory
    mkdir -p $BASE_DIR/apache2/vhosts
    
    # Create a sample vhost configuration
    cat > $BASE_DIR/apache2/vhosts/sample.conf.disabled << EOF
<VirtualHost 127.0.0.1:8000>
    ServerName example.com
    ServerAlias www.example.com
    
    DocumentRoot $BASE_DIR/sites/example.com
    
    <Directory $BASE_DIR/sites/example.com>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/example.com-error.log
    CustomLog \${APACHE_LOG_DIR}/example.com-access.log combined
    
    # PHP-FPM Configuration
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php8.2-fpm.sock|fcgi://localhost"
    </FilesMatch>
</VirtualHost>
EOF

    # Create PHP version selector for Apache
    cat > $BASE_DIR/apache2/vhosts/php-selector.conf.disabled << EOF
# PHP Version Selector - Include this in your VirtualHost
# Usage: Include $BASE_DIR/apache2/vhosts/php-selector.conf

# PHP 7.4
<FilesMatch "\.php74$">
    SetHandler "proxy:unix:/run/php/php7.4-fpm.sock|fcgi://localhost"
</FilesMatch>

# PHP 8.0
<FilesMatch "\.php80$">
    SetHandler "proxy:unix:/run/php/php8.0-fpm.sock|fcgi://localhost"
</FilesMatch>

# PHP 8.1
<FilesMatch "\.php81$">
    SetHandler "proxy:unix:/run/php/php8.1-fpm.sock|fcgi://localhost"
</FilesMatch>

# PHP 8.2
<FilesMatch "\.php82$">
    SetHandler "proxy:unix:/run/php/php8.2-fpm.sock|fcgi://localhost"
</FilesMatch>

# PHP 8.3
<FilesMatch "\.php83$">
    SetHandler "proxy:unix:/run/php/php8.3-fpm.sock|fcgi://localhost"
</FilesMatch>
EOF

    # Create a main Apache vhost file to include all vhosts
    cat > $BASE_DIR/apache2/vhosts.conf << EOF
# Include all enabled virtual hosts
Include $BASE_DIR/apache2/vhosts/*.conf
EOF

    # Create symbolic link
    ln -sf $BASE_DIR/apache2/vhosts.conf /etc/apache2/conf-available/vhosts.conf
    
    # Enable the configuration
    a2enconf vhosts
    
    # Configure Apache to listen on port 8000 internally
    sed -i 's/Listen 80/Listen 127.0.0.1:8000/' /etc/apache2/ports.conf
    
    # Remove default site
    a2dissite 000-default
    
    # Create a default vhost
    cat > $BASE_DIR/apache2/vhosts/default.conf << EOF
<VirtualHost 127.0.0.1:8000>
    ServerAdmin webmaster@localhost
    DocumentRoot $BASE_DIR/sites/default
    
    <Directory $BASE_DIR/sites/default>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/default-error.log
    CustomLog \${APACHE_LOG_DIR}/default-access.log combined
    
    # PHP-FPM Configuration
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php8.2-fpm.sock|fcgi://localhost"
    </FilesMatch>
    
    # Include PHP version selector
    Include $BASE_DIR/apache2/vhosts/php-selector.conf.disabled
</VirtualHost>
EOF

    log "Apache backend configuration completed."
}


# Create a custom panel placeholder
create_custom_panel() {
    log "Creating custom panel placeholder..."
    
    # Create a simple index.php file
    cat > $BASE_DIR/custom_panel/index.php << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Custom Control Panel</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            text-align: center;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
        }
        .info {
            text-align: left;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Custom Control Panel</h1>
        <p>This is a placeholder for your custom control panel.</p>
        <p>Replace this with your own PHP panel.</p>
        
        <div class="info">
            <h3>System Information:</h3>
            <pre><?php
                echo "PHP Version: " . phpversion() . "\n";
                echo "Server Software: " . $_SERVER['SERVER_SOFTWARE'] . "\n";
                echo "Server IP: " . $_SERVER['SERVER_ADDR'] . "\n";
                echo "Document Root: " . $_SERVER['DOCUMENT_ROOT'] . "\n";
                
                // List installed PHP versions
                echo "\nInstalled PHP Versions:\n";
                $output = shell_exec('ls -l /usr/bin/php* | grep -v ".bak" | grep -v ".ini" | grep -v ".save" | grep -v ".conf"');
                echo $output;
                
                // Show disk usage
                echo "\nDisk Usage:\n";
                $output = shell_exec('df -h / | tail -n 1');
                echo $output;
            ?></pre>
        </div>
    </div>
</body>
</html>
EOF
    
    # Set proper permissions
    chown -R www-data:www-data $BASE_DIR/custom_panel
    chmod -R 755 $BASE_DIR/custom_panel
    chown -R www-data:www-data $BASE_DIR/sites
    chmod -R 755 $BASE_DIR/sites
    
    log "Custom panel placeholder created."
}

# Setup root SSH access if requested
setup_root_ssh() {
    log "Setting up root SSH access..."
    
    # Configure SSH
    sed -i -e 's/^\#\?PermitRootLogin\s[a-zA-Z\-]*$/PermitRootLogin yes/m' \
           -e 's/^\#\?PasswordAuthentication\s[a-zA-Z\-]*$/PasswordAuthentication yes/m' \
           -e 's/^\#\?PermitEmptyPasswords\s[a-zA-Z\-]*$/PermitEmptyPasswords no/' \
           -e 's/^\#\?LoginGraceTime/LoginGraceTime/m' \
           -e 's/^\#\?StrictModes/StrictModes/m' \
           -e 's/^\#\?MaxAuthTries/MaxAuthTries/m' \
           -e 's/^\#\?MaxSessions/MaxSessions/m' /etc/ssh/sshd_config
    
    # Prompt for root password
    clear
    echo "Please enter your root password in the next screen"
    passwd
    
    # Restart SSH service
    systemctl restart ssh
    systemctl restart sshd
    
    log "Root SSH access configured."
}

# Create setup completion file
create_setup_completion() {
    log "Creating setup completion info..."
    
    cat > $BASE_DIR/setup_info.txt << EOF
Web Server Installation Completed Successfully!

Server Information:
------------------
IP Address: $(hostname -I | awk '{print $1}')
Hostname: $(hostname)
OS: $(lsb_release -ds)

Installed Components:
-------------------
- Multiple PHP versions (7.4, 8.0, 8.1, 8.2, 8.3)
- Nginx (Front-end - Port 80)
- Apache (Back-end - Port 8000)
- phpMyAdmin (http://[server-ip]/phpmyadmin)
- Custom Panel (http://[server-ip]:8080)
- UFW Firewall
- fail2ban

Architecture:
-----------
- Nginx is configured as reverse proxy for Apache
- Static content is served directly by Nginx
- PHP processing is handled by Apache

Access Information:
-----------------
- Custom Panel: http://[server-ip]:8080
- phpMyAdmin: http://[server-ip]/phpmyadmin
- Default Website: http://[server-ip]
- PHP Info: http://[server-ip]/info.php

Open Ports:
----------
- SSH (22)
- HTTP (80)
- HTTPS (443)
- Custom Panel (8080)

Document Roots:
-------------
- Default Website: $BASE_DIR/sites/default
- Custom Panel: $BASE_DIR/custom_panel

Adding New Sites:
---------------
1. Create directory in $BASE_DIR/sites/[domain]
2. Copy and modify $BASE_DIR/nginx/vhosts/sample.conf.disabled to $BASE_DIR/nginx/vhosts/[domain].conf
3. Copy and modify $BASE_DIR/apache2/vhosts/sample.conf.disabled to $BASE_DIR/apache2/vhosts/[domain].conf
4. Restart Nginx and Apache: systemctl restart nginx apache2

Installation Date: $(date)
Base Directory: $BASE_DIR
EOF

    log "Setup completion info created at $BASE_DIR/setup_info.txt"
}

# Main execution
main() {
    set_base_directory
    update_system
    install_basics
    setup_php_repo
    install_php_versions
    install_nginx
    install_apache
    configure_nginx_as_proxy
    configure_apache_backend
    install_phpmyadmin
    configure_ufw
    configure_fail2ban
    create_custom_panel
    create_setup_completion
    
    # Restart services
    systemctl restart apache2
    systemctl enable apache2
    systemctl restart nginx
    systemctl enable nginx
    
    log "Would you like to set up root SSH access? (y/n)"
    read -r setup_ssh
    
    if [[ "$setup_ssh" =~ ^[Yy]$ ]]; then
        setup_root_ssh
        log "Root SSH access has been set up. The server will now reboot in 10 seconds. Please login as root after reboot."
        log "Installation completed successfully!"
        sleep 10
        reboot
    else
        log "Installation completed successfully!"
    fi
}

# Run the main function
main
