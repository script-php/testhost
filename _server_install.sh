#!/bin/bash
# Improved Server Installation Script
# This script installs and configures:
# - SSH with secure settings
# - Fail2ban for security
# - Nginx as frontend
# - Apache as backend
# - PHP-FPM with optimized settings
# - MySQL/MariaDB
# - phpMyAdmin

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        log "SUCCESS: $1"
    else
        log "ERROR: $1"
        echo "An error occurred. Check the log for details."
        exit 1
    fi
}

# Function to create a secure root password
configure_root_ssh() {
    log "Configuring SSH for root access..."
    
    # Backup original sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Configure SSH
    sed -i -e 's/^\#\?PermitRootLogin\s[a-zA-Z\-]*$/PermitRootLogin yes/m' \
           -e 's/^\#\?PasswordAuthentication\s[a-zA-Z\-]*$/PasswordAuthentication yes/m' \
           -e 's/^\#\?PermitEmptyPasswords\s[a-zA-Z\-]*$/PermitEmptyPasswords no/' \
           -e 's/^\#\?LoginGraceTime/LoginGraceTime/m' \
           -e 's/^\#\?StrictModes/StrictModes/m' \
           -e 's/^\#\?MaxAuthTries/MaxAuthTries/m' \
           -e 's/^\#\?MaxSessions/MaxSessions/m' /etc/ssh/sshd_config
    
    check_status "SSH configuration"
    
    log "Setting root password..."
    echo "Please enter a strong password for root:"
    passwd
    check_status "Password setup"
    
    log "Restarting SSH service..."
    systemctl restart sshd
    check_status "SSH service restart"
}

# Function to install fail2ban
install_fail2ban() {
    log "Installing and configuring fail2ban..."
    
    apt-get install -y fail2ban
    check_status "Fail2ban installation"
    
    cat > /etc/fail2ban/jail.local << EOL
[sshd]
enabled = true
maxretry = 5
findtime = 1d
bantime = 4w
ignoreip = 127.0.0.1/8 192.168.1.0/24
EOL
    
    check_status "Fail2ban configuration"
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    check_status "Fail2ban service setup"
}

# Function to install and configure Nginx
install_nginx() {
    log "Installing Nginx..."
    
    apt-get install -y nginx
    check_status "Nginx installation"
    
    # Backup default sites if they exist
    if [ -d "/etc/nginx/sites-enabled" ]; then
        mkdir -p /etc/nginx/sites-enabled.bak
        cp -a /etc/nginx/sites-enabled/. /etc/nginx/sites-enabled.bak/
    fi
    
    if [ -d "/etc/nginx/sites-available" ]; then
        mkdir -p /etc/nginx/sites-available.bak
        cp -a /etc/nginx/sites-available/. /etc/nginx/sites-available.bak/
    fi
    
    # Remove default sites
    rm -rf /etc/nginx/sites-enabled
    rm -rf /etc/nginx/sites-available
    
    # Create directories for configurations
    mkdir -p /etc/nginx/conf.d
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    # Create optimized nginx.conf
    cat > /etc/nginx/nginx.conf << 'EOL'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

events {
    worker_connections 10240;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # Timeouts
    client_header_timeout 60;
    client_body_timeout 60;
    send_timeout 60;
    keepalive_timeout 65;
    
    # Buffers
    client_header_buffer_size 2k;
    client_body_buffer_size 256k;
    client_max_body_size 256m;
    large_client_header_buffers 4 8k;
    
    # Other settings
    reset_timedout_connection on;
    server_tokens off;
    server_name_in_redirect off;
    server_names_hash_max_size 512;
    server_names_hash_bucket_size 512;
    types_hash_max_size 2048;
    
    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    # Set to 'on' if you need detailed logs
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    # Gzip settings
    gzip on;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_min_length 1000;
    gzip_buffers 16 8k;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript application/x-font-ttf image/svg+xml font/opentype;
    gzip_proxied any;
    gzip_disable "MSIE [1-6]\.";
    
    # Cloudflare IP ranges
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 2400:cb00::/32;
    set_real_ip_from 2606:4700::/32;
    set_real_ip_from 2803:f800::/32;
    set_real_ip_from 2405:b500::/32;
    set_real_ip_from 2405:8100::/32;
    set_real_ip_from 2a06:98c0::/29;
    set_real_ip_from 2c0f:f248::/32;
    real_ip_header CF-Connecting-IP;
    
    # Default server block
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        
        location / {
            return 444;
        }
        
        # phpMyAdmin location block
        location /phpmyadmin {
            root /usr/share/;
            index index.php index.html index.htm;
            location ~ ^/phpmyadmin/(.+\.php)$ {
                try_files $uri =404;
                root /usr/share/;
                fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                include fastcgi_params;
            }
            
            location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
                root /usr/share/;
            }
        }
    }
    
    # Load virtual host configurations
    include /etc/nginx/sites-enabled/*.conf;
    include /etc/nginx/conf.d/*.conf;
}
EOL
    
    check_status "Nginx configuration"
    
    systemctl enable nginx
    check_status "Nginx service enabled"
}

# Function to install and configure Apache
install_apache() {
    log "Installing Apache..."
    
    apt-get install -y apache2
    check_status "Apache installation"
    
    # Enable necessary modules
    a2enmod proxy proxy_http proxy_balancer lbmethod_byrequests rewrite headers
    check_status "Apache modules enabled"
    
    # Set Apache to listen on localhost:8080
    sed -i 's/Listen 80/Listen 127.0.0.1:8080/' /etc/apache2/ports.conf
    
    # Create a default virtual host
    cat > /etc/apache2/sites-available/000-default.conf << 'EOL'
<VirtualHost 127.0.0.1:8080>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL
    
    check_status "Apache default virtual host configuration"
    
    # Enable the site
    a2ensite 000-default
    
    systemctl enable apache2
    check_status "Apache service enabled"
}

# Function to install and configure PHP-FPM
install_php() {
    log "Adding PHP repository..."
    
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update
    
    log "Installing multiple PHP versions (7.4, 8.0, 8.1, 8.2)..."
    
    # Install PHP 7.4
    apt-get install -y php7.4-fpm php7.4-cli php7.4-common php7.4-curl \
                       php7.4-gd php7.4-intl php7.4-mbstring php7.4-mysql \
                       php7.4-opcache php7.4-readline php7.4-xml php7.4-zip
    
    # Install PHP 8.0
    apt-get install -y php8.0-fpm php8.0-cli php8.0-common php8.0-curl \
                       php8.0-gd php8.0-intl php8.0-mbstring php8.0-mysql \
                       php8.0-opcache php8.0-readline php8.0-xml php8.0-zip
    
    # Install PHP 8.1
    apt-get install -y php8.1-fpm php8.1-cli php8.1-common php8.1-curl \
                       php8.1-gd php8.1-intl php8.1-mbstring php8.1-mysql \
                       php8.1-opcache php8.1-readline php8.1-xml php8.1-zip
    
    # Install PHP 8.2
    apt-get install -y php8.2-fpm php8.2-cli php8.2-common php8.2-curl \
                       php8.2-gd php8.2-intl php8.2-mbstring php8.2-mysql \
                       php8.2-opcache php8.2-readline php8.2-xml php8.2-zip
    
    check_status "PHP versions installation"
    
    # Configure PHP-FPM for each version
    for VERSION in 7.4 8.0 8.1 8.2; do
        # Configure PHP-FPM global settings
        sed -i -e 's/^include=/\nemergency_restart_threshold = 10\nemergency_restart_interval = 1m\nprocess_control_timeout = 10s\ninclude=/' "/etc/php/${VERSION}/fpm/php-fpm.conf"
        
        # Configure PHP-FPM pool settings
        sed -i -e 's/^[\;\s]*\?pm\s=\s[a-z]*$/pm = ondemand/m' \
               -e 's/^[\;\s]*\?pm.max_children\s=\s[0-9]*$/pm.max_children = 100/m' \
               -e 's/^[\;\s]*\?pm.process_idle_timeout\s=\s[0-9]*$/pm.process_idle_timeout = 10/m' \
               -e 's/^[\;\s]*\?pm.max_requests\s=\s[0-9]*$/pm.max_requests = 500/m' "/etc/php/${VERSION}/fpm/pool.d/www.conf"
        
        # Create a custom pool for each PHP version
        cp "/etc/php/${VERSION}/fpm/pool.d/www.conf" "/etc/php/${VERSION}/fpm/pool.d/custom.conf"
        sed -i -e "s/\[www\]/\[php${VERSION}\]/g" \
               -e "s/^user = .*/user = www-data/g" \
               -e "s/^group = .*/group = www-data/g" \
               -e "s/^listen = .*/listen = \/run\/php\/php${VERSION}-fpm-custom.sock/g" "/etc/php/${VERSION}/fpm/pool.d/custom.conf"
        
        # Adjust PHP.ini settings
        for SAPI in cli fpm; do
            # Set timezone
            sed -i "s/;date.timezone =.*/date.timezone = UTC/" "/etc/php/${VERSION}/${SAPI}/php.ini"
            
            # Set memory limit
            sed -i "s/memory_limit = .*/memory_limit = 256M/" "/etc/php/${VERSION}/${SAPI}/php.ini"
            
            # Set upload limits
            sed -i "s/upload_max_filesize = .*/upload_max_filesize = 64M/" "/etc/php/${VERSION}/${SAPI}/php.ini"
            sed -i "s/post_max_size = .*/post_max_size = 64M/" "/etc/php/${VERSION}/${SAPI}/php.ini"
            
            # Set maximum execution time
            sed -i "s/max_execution_time = .*/max_execution_time = 300/" "/etc/php/${VERSION}/${SAPI}/php.ini"
        done
        
        # Disable OpCache for development (enable in production)
        sed -i -e 's/zend/;zend/' "/etc/php/${VERSION}/fpm/conf.d/"*opcache*
        
        # Enable PHP-FPM service
        systemctl enable "php${VERSION}-fpm"
    done
    
    check_status "PHP-FPM versions configuration"
    
    # Create PHP version switching script
    cat > /usr/local/bin/switch-php << 'EOL'
#!/bin/bash
# PHP Version Switcher for Command Line
# Usage: switch-php 7.4|8.0|8.1|8.2

if [ -z "$1" ]; then
    echo "Usage: switch-php VERSION"
    echo "Available versions:"
    echo "  7.4, 8.0, 8.1, 8.2"
    exit 1
fi

VERSION=$1

# Check if version exists
if [ ! -d "/etc/php/${VERSION}" ]; then
    echo "PHP version ${VERSION} is not installed"
    exit 1
fi

# Update alternatives for PHP CLI
update-alternatives --set php /usr/bin/php${VERSION}
update-alternatives --set phar /usr/bin/phar${VERSION}
update-alternatives --set phar.phar /usr/bin/phar.phar${VERSION}

echo "Switched CLI PHP to version ${VERSION}"
php -v
EOL
    
    chmod +x /usr/local/bin/switch-php
    
    # Set PHP 8.0 as default for CLI
    update-alternatives --set php /usr/bin/php8.0
    update-alternatives --set phar /usr/bin/phar8.0
    update-alternatives --set phar.phar /usr/bin/phar.phar8.0
    
    log "PHP versions installed and configured"
    log "Use switch-php [version] to change PHP CLI version"
}

# Function to install and configure MySQL
install_mysql() {
    log "Installing MySQL..."
    
    # Install MySQL with preset root password to avoid prompt
    DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
    check_status "MySQL installation"
    
    # Secure the MySQL installation
    log "Securing MySQL installation..."
    
    # Start MySQL if not already running
    systemctl start mysql
    
    # Create secure installation script
    cat > /tmp/mysql_secure.sql << EOL
UPDATE mysql.user SET Password=PASSWORD('CHANGE_THIS_PASSWORD') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOL
    
    # Run the secure installation script
    mysql < /tmp/mysql_secure.sql
    rm /tmp/mysql_secure.sql
    
    log "MySQL secured with default root password: CHANGE_THIS_PASSWORD"
    log "IMPORTANT: You should change this password immediately after installation!"
    
    systemctl enable mysql
    check_status "MySQL service enabled"
}

# Function to install phpMyAdmin
install_phpmyadmin() {
    log "Installing phpMyAdmin..."
    
    # Set debconf selections to avoid prompts
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password CHANGE_THIS_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password CHANGE_THIS_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password CHANGE_THIS_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin
    check_status "phpMyAdmin installation"
    
    log "phpMyAdmin installed with default password: CHANGE_THIS_PASSWORD"
    log "IMPORTANT: You should change this password immediately after installation!"
}

# Function to create website directories
create_website_dirs() {
    log "Creating website directories..."
    
    mkdir -p /sites
    chmod -R 755 /sites
    check_status "Website directories created"
}

# Function to add a new website
add_website() {
    if [ -z "$1" ]; then
        log "ERROR: No domain name provided"
        echo "Usage: add_website domain.com"
        return 1
    fi
    
    local DOMAIN=$1
    log "Adding website for $DOMAIN..."
    
    # Create website directory
    mkdir -p /sites/$DOMAIN/{public_html,logs}
    chmod -R 755 /sites/$DOMAIN
    chown -R www-data:www-data /sites/$DOMAIN
    
    # Create Nginx configuration
    cat > /etc/nginx/sites-available/$DOMAIN.conf << EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    access_log /sites/$DOMAIN/logs/access.log;
    error_log /sites/$DOMAIN/logs/error.log;
    
    root /sites/$DOMAIN/public_html;
    index index.php index.html;
    
    # Forward to Apache for PHP processing
    location ~ \.php$ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Static files handled by Nginx
    location ~* \.(jpg|jpeg|gif|png|css|js|ico|xml)$ {
        access_log off;
        log_not_found off;
        expires 30d;
    }
    
    # Deny access to .htaccess files
    location ~ /\.ht {
        deny all;
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
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog /sites/$DOMAIN/logs/apache-error.log
    CustomLog /sites/$DOMAIN/logs/apache-access.log combined
</VirtualHost>
EOL
    
    # Enable the sites
    ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
    a2ensite $DOMAIN
    
    # Create sample index file
    cat > /sites/$DOMAIN/public_html/index.php << EOL
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $DOMAIN</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            line-height: 1.6;
        }
        h1 {
            color: #333;
        }
    </style>
</head>
<body>
    <h1>Welcome to $DOMAIN</h1>
    <p>Your website is up and running!</p>
    <p>PHP Version: <?php echo phpversion(); ?></p>
    <p>Server time: <?php echo date('Y-m-d H:i:s'); ?></p>
</body>
</html>
EOL
    
    check_status "Website $DOMAIN added"
    
    # Reload services
    systemctl reload nginx
    systemctl reload apache2
    
    log "Website $DOMAIN has been set up successfully!"
    log "Files are located in /sites/$DOMAIN/public_html"
}

# Main installation function
main_install() {
    log "Starting server installation..."
    
    # Update system packages
    log "Updating system packages..."
    apt-get update && apt-get upgrade -y
    check_status "System update"
    
    # Install components
    configure_root_ssh
    install_fail2ban
    install_nginx
    install_apache
    install_php
    install_mysql
    install_phpmyadmin
    create_website_dirs
    
    # Restart services
    log "Restarting all services..."
    systemctl restart fail2ban
    systemctl restart mysql
    systemctl restart php8.0-fpm
    systemctl restart apache2
    systemctl restart nginx
    
    # System cleanup
    log "Cleaning up..."
    apt-get autoclean
    apt-get autoremove -y
    
    log "Installation complete!"
    log "======================="
    log "Important notes:"
    log "1. MySQL root password is set to: CHANGE_THIS_PASSWORD"
    log "2. phpMyAdmin password is set to: CHANGE_THIS_PASSWORD"
    log "3. CHANGE THESE PASSWORDS IMMEDIATELY!"
    log "4. To add a new website, run: add_website domain.com"
    log "5. Website files will be in: /sites/domain.com/public_html"
    log "======================="
}

# Function to display help
show_help() {
    echo "Server Installation Script"
    echo "Usage:"
    echo "  $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     - Install and configure the entire server"
    echo "  add-website - Add a new website (requires domain name)"
    echo "  help        - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 add-website example.com"
}

# Main script execution
case "$1" in
    install)
        main_install
        ;;
    add-website)
        if [ -z "$2" ]; then
            echo "Error: No domain name provided"
            echo "Usage: $0 add-website domain.com"
            exit 1
        fi
        add_website "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac

exit 0
