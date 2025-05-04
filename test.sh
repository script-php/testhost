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
