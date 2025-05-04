#!/bin/bash

# Website Manager for Web Server
# This script allows you to create, edit, and remove websites with PHP version selection

# Configuration - Make sure this matches your server installation
BASE_DIR="/cpanel"  # Update this if you changed it in the install.sh script
NGINX_VHOSTS_DIR="$BASE_DIR/nginx/vhosts"
APACHE_VHOSTS_DIR="$BASE_DIR/apache2/vhosts"
SITES_DIR="$BASE_DIR/sites"

# Color Definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
fi

# Function to create a new website
create_website() {
    clear
    echo -e "${BLUE}=== Create New Website ===${NC}"
    echo ""
    
    # Get domain name
    read -p "Enter domain name (e.g., example.com): " domain_name
    if [[ -z "$domain_name" ]]; then
        error "Domain name cannot be empty!"
    fi
    
    # Check if domain already exists
    if [[ -d "$SITES_DIR/$domain_name" || -f "$NGINX_VHOSTS_DIR/$domain_name.conf" ]]; then
        error "Website for $domain_name already exists!"
    fi
    
    # Get document root or use default
    read -p "Enter document root path (press Enter for $SITES_DIR/$domain_name): " doc_root
    if [[ -z "$doc_root" ]]; then
        doc_root="$SITES_DIR/$domain_name"
    fi
    
    # Select PHP version
    echo -e "\nSelect PHP version for $domain_name:"
    echo "1) PHP 7.4"
    echo "2) PHP 8.0"
    echo "3) PHP 8.1"
    echo "4) PHP 8.2"
    echo "5) PHP 8.3"
    read -p "Enter selection [1-5] (default: 4 - PHP 8.2): " php_choice
    
    case $php_choice in
        1) php_version="7.4" ;;
        2) php_version="8.0" ;;
        3) php_version="8.1" ;;
        5) php_version="8.3" ;;
        *) php_version="8.2" ;; # Default to PHP 8.2
    esac
    
    # Create website directory
    mkdir -p "$doc_root"
    
    # Create index.php file
    cat > "$doc_root/index.php" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $domain_name</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 40px;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        .info {
            background-color: #f8f9fa;
            border-left: 4px solid #5bc0de;
            padding: 15px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
        }
    </style>
</head>
<body>
    <h1>Welcome to $domain_name</h1>
    <div class="info">
        <p>This site is running on PHP $php_version</p>
        <p><?php echo 'Current PHP version: ' . phpversion(); ?></p>
        <p>Server time: <?php echo date('Y-m-d H:i:s'); ?></p>
    </div>
    <p>Replace this file with your website content.</p>
</body>
</html>
EOF

    # Create phpinfo.php file for testing
    cat > "$doc_root/phpinfo.php" << EOF
<?php
phpinfo();
EOF

    # Create Nginx vhost configuration
    cat > "$NGINX_VHOSTS_DIR/$domain_name.conf" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain_name www.$domain_name;
    
    # Logs
    access_log $BASE_DIR/logs/$domain_name-access.log;
    error_log $BASE_DIR/logs/$domain_name-error.log;
    
    # Root directory
    root $doc_root;
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
    
    # Pass other requests to Apache
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

    # Create Apache vhost configuration
    cat > "$APACHE_VHOSTS_DIR/$domain_name.conf" << EOF
<VirtualHost 127.0.0.1:8000>
    ServerName $domain_name
    ServerAlias www.$domain_name
    
    DocumentRoot $doc_root
    
    <Directory $doc_root>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/$domain_name-error.log
    CustomLog \${APACHE_LOG_DIR}/$domain_name-access.log combined
    
    # PHP-FPM Configuration
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php$php_version-fpm.sock|fcgi://localhost"
    </FilesMatch>
    
    # Include PHP selector config
    Include $BASE_DIR/apache2/vhosts/php-selector.conf.disabled
</VirtualHost>
EOF

    # Set permissions
    chown -R www-data:www-data "$doc_root"
    chmod -R 755 "$doc_root"
    
    # Store website configuration for future management
    mkdir -p "$BASE_DIR/website_manager/sites"
    cat > "$BASE_DIR/website_manager/sites/$domain_name.conf" << EOF
DOMAIN=$domain_name
DOCUMENT_ROOT=$doc_root
PHP_VERSION=$php_version
CREATED_DATE=$(date +%Y-%m-%d)
EOF

    # Restart web servers
    systemctl reload nginx
    systemctl reload apache2
    
    log "Website '$domain_name' successfully created with PHP $php_version!"
    log "Website URL: http://$domain_name"
    log "Document Root: $doc_root"
    log "PHP Info URL: http://$domain_name/phpinfo.php"
    log ""
    log "Don't forget to add the domain to your hosts file or DNS server"
}

# Function to list all websites
list_websites() {
    clear
    echo -e "${BLUE}=== Website List ===${NC}"
    echo ""
    
    # Check if any websites exist
    if [ ! "$(ls -A "$NGINX_VHOSTS_DIR" 2>/dev/null)" ]; then
        echo "No websites found."
        return
    fi
    
    # Get list of websites
    echo -e "Domain\tPHP Version\tDocument Root"
    echo -e "------\t-----------\t------------"
    
    for conf_file in "$NGINX_VHOSTS_DIR"/*.conf; do
        if [ -f "$conf_file" ]; then
            domain=$(basename "$conf_file" .conf)
            
            # Get PHP version
            if [ -f "$BASE_DIR/website_manager/sites/$domain.conf" ]; then
                source "$BASE_DIR/website_manager/sites/$domain.conf"
                php_ver=$PHP_VERSION
                doc_root=$DOCUMENT_ROOT
            else
                # Try to extract from Apache config
                php_ver=$(grep -o "php[0-9]\.[0-9]-fpm.sock" "$APACHE_VHOSTS_DIR/$domain.conf" 2>/dev/null | head -1 | sed 's/php\(.*\)-fpm.sock/\1/')
                doc_root=$(grep -o "DocumentRoot .*" "$APACHE_VHOSTS_DIR/$domain.conf" 2>/dev/null | head -1 | sed 's/DocumentRoot //')
                
                if [ -z "$php_ver" ]; then
                    php_ver="unknown"
                fi
                
                if [ -z "$doc_root" ]; then
                    doc_root="unknown"
                fi
            fi
            
            echo -e "$domain\t$php_ver\t$doc_root"
        fi
    done
}

# Function to edit website configuration
edit_website() {
    clear
    echo -e "${BLUE}=== Edit Website Configuration ===${NC}"
    echo ""
    
    # List available websites first
    echo "Available websites:"
    echo ""
    
    # Get list of websites
    count=1
    declare -a domains
    
    for conf_file in "$NGINX_VHOSTS_DIR"/*.conf; do
        if [ -f "$conf_file" ]; then
            domain=$(basename "$conf_file" .conf)
            domains[$count]=$domain
            
            # Get PHP version
            if [ -f "$BASE_DIR/website_manager/sites/$domain.conf" ]; then
                source "$BASE_DIR/website_manager/sites/$domain.conf"
                php_ver=$PHP_VERSION
            else
                php_ver=$(grep -o "php[0-9]\.[0-9]-fpm.sock" "$APACHE_VHOSTS_DIR/$domain.conf" 2>/dev/null | head -1 | sed 's/php\(.*\)-fpm.sock/\1/')
                if [ -z "$php_ver" ]; then
                    php_ver="unknown"
                fi
            fi
            
            echo "$count) $domain (PHP $php_ver)"
            count=$((count + 1))
        fi
    done
    
    if [ $count -eq 1 ]; then
        echo "No websites found."
        return
    fi
    
    # Select website to edit
    read -p "Enter website number to edit [1-$((count-1))]: " website_num
    
    if ! [[ "$website_num" =~ ^[0-9]+$ ]] || [ "$website_num" -lt 1 ] || [ "$website_num" -ge "$count" ]; then
        error "Invalid selection!"
    fi
    
    domain=${domains[$website_num]}
    
    # Load existing configuration
    if [ -f "$BASE_DIR/website_manager/sites/$domain.conf" ]; then
        source "$BASE_DIR/website_manager/sites/$domain.conf"
        current_php_version=$PHP_VERSION
        current_doc_root=$DOCUMENT_ROOT
    else
        current_php_version=$(grep -o "php[0-9]\.[0-9]-fpm.sock" "$APACHE_VHOSTS_DIR/$domain.conf" 2>/dev/null | head -1 | sed 's/php\(.*\)-fpm.sock/\1/')
        current_doc_root=$(grep -o "DocumentRoot .*" "$APACHE_VHOSTS_DIR/$domain.conf" 2>/dev/null | head -1 | sed 's/DocumentRoot //')
        
        if [ -z "$current_php_version" ]; then
            current_php_version="8.2" # Default
        fi
        
        if [ -z "$current_doc_root" ]; then
            current_doc_root="$SITES_DIR/$domain"
        fi
    fi
    
    clear
    echo -e "${BLUE}=== Editing Website: $domain ===${NC}"
    echo ""
    echo "Current configuration:"
    echo "- PHP Version: $current_php_version"
    echo "- Document Root: $current_doc_root"
    echo ""
    
    # Select what to edit
    echo "What would you like to edit?"
    echo "1) PHP Version"
    echo "2) Document Root"
    echo "3) Both"
    read -p "Enter selection [1-3]: " edit_choice
    
    # Edit PHP version
    if [[ "$edit_choice" == "1" || "$edit_choice" == "3" ]]; then
        echo -e "\nSelect new PHP version for $domain:"
        echo "1) PHP 7.4"
        echo "2) PHP 8.0"
        echo "3) PHP 8.1"
        echo "4) PHP 8.2"
        echo "5) PHP 8.3"
        read -p "Enter selection [1-5] (current: $current_php_version): " php_choice
        
        case $php_choice in
            1) new_php_version="7.4" ;;
            2) new_php_version="8.0" ;;
            3) new_php_version="8.1" ;;
            4) new_php_version="8.2" ;;
            5) new_php_version="8.3" ;;
            *) new_php_version="$current_php_version" ;; # No change
        esac
    else
        new_php_version="$current_php_version" # No change
    fi
    
    # Edit document root
    if [[ "$edit_choice" == "2" || "$edit_choice" == "3" ]]; then
        read -p "Enter new document root path (current: $current_doc_root): " new_doc_root_input
        if [[ -z "$new_doc_root_input" ]]; then
            new_doc_root="$current_doc_root" # No change
        else
            new_doc_root="$new_doc_root_input"
            
            # Create new document root if it doesn't exist
            if [ ! -d "$new_doc_root" ]; then
                mkdir -p "$new_doc_root"
                
                # Ask if content should be copied
                read -p "Copy content from old document root? (y/n): " copy_content
                if [[ "$copy_content" =~ ^[Yy]$ ]]; then
                    cp -r "$current_doc_root"/* "$new_doc_root"/ 2>/dev/null
                    log "Content copied to new document root"
                else
                    # Create basic index.php in new location
                    cat > "$new_doc_root/index.php" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $domain</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 40px;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        .info {
            background-color: #f8f9fa;
            border-left: 4px solid #5bc0de;
            padding: 15px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
        }
    </style>
</head>
<body>
    <h1>Welcome to $domain</h1>
    <div class="info">
        <p>This site is running on PHP $new_php_version</p>
        <p><?php echo 'Current PHP version: ' . phpversion(); ?></p>
        <p>Server time: <?php echo date('Y-m-d H:i:s'); ?></p>
    </div>
    <p>Replace this file with your website content.</p>
</body>
</html>
EOF

                    # Create phpinfo.php file for testing
                    cat > "$new_doc_root/phpinfo.php" << EOF
<?php
phpinfo();
EOF
                fi
            fi
            
            # Set permissions for new document root
            chown -R www-data:www-data "$new_doc_root"
            chmod -R 755 "$new_doc_root"
        fi
    else
        new_doc_root="$current_doc_root" # No change
    fi
    
    # Update Nginx configuration if document root changed
    if [ "$new_doc_root" != "$current_doc_root" ]; then
        sed -i "s|root .*;|root $new_doc_root;|g" "$NGINX_VHOSTS_DIR/$domain.conf"
    fi
    
    # Update Apache configuration
    if [ "$new_php_version" != "$current_php_version" ] || [ "$new_doc_root" != "$current_doc_root" ]; then
        # Update document root if needed
        if [ "$new_doc_root" != "$current_doc_root" ]; then
            sed -i "s|DocumentRoot .*|DocumentRoot $new_doc_root|g" "$APACHE_VHOSTS_DIR/$domain.conf"
            sed -i "s|<Directory .*>|<Directory $new_doc_root>|g" "$APACHE_VHOSTS_DIR/$domain.conf"
        fi
        
        # Update PHP version if needed
        if [ "$new_php_version" != "$current_php_version" ]; then
            sed -i "s|proxy:unix:/run/php/php.*-fpm.sock|proxy:unix:/run/php/php$new_php_version-fpm.sock|g" "$APACHE_VHOSTS_DIR/$domain.conf"
        fi
    fi
    
    # Update stored configuration
    mkdir -p "$BASE_DIR/website_manager/sites"
    cat > "$BASE_DIR/website_manager/sites/$domain.conf" << EOF
DOMAIN=$domain
DOCUMENT_ROOT=$new_doc_root
PHP_VERSION=$new_php_version
CREATED_DATE=$(date +%Y-%m-%d)
LAST_MODIFIED=$(date +%Y-%m-%d)
EOF
    
    # Restart web servers
    systemctl reload nginx
    systemctl reload apache2
    
    log "Website '$domain' configuration updated successfully!"
    
    if [ "$new_php_version" != "$current_php_version" ]; then
        log "PHP Version changed from $current_php_version to $new_php_version"
    fi
    
    if [ "$new_doc_root" != "$current_doc_root" ]; then
        log "Document Root changed from $current_doc_root to $new_doc_root"
    fi
}

# Function to remove a website
remove_website() {
    clear
    echo -e "${BLUE}=== Remove Website ===${NC}"
    echo ""
    
    # List available websites first
    echo "Available websites:"
    echo ""
    
    # Get list of websites
    count=1
    declare -a domains
    
    for conf_file in "$NGINX_VHOSTS_DIR"/*.conf; do
        if [ -f "$conf_file" ]; then
            domain=$(basename "$conf_file" .conf)
            domains[$count]=$domain
            echo "$count) $domain"
            count=$((count + 1))
        fi
    done
    
    if [ $count -eq 1 ]; then
        echo "No websites found."
        return
    fi
    
    # Select website to remove
    read -p "Enter website number to remove [1-$((count-1))]: " website_num
    
    if ! [[ "$website_num" =~ ^[0-9]+$ ]] || [ "$website_num" -lt 1 ] || [ "$website_num" -ge "$count" ]; then
        error "Invalid selection!"
    fi
    
    domain=${domains[$website_num]}
    
    # Load site configuration
    if [ -f "$BASE_DIR/website_manager/sites/$domain.conf" ]; then
        source "$BASE_DIR/website_manager/sites/$domain.conf"
        doc_root=$DOCUMENT_ROOT
    else
        doc_root=$(grep -o "DocumentRoot .*" "$APACHE_VHOSTS_DIR/$domain.conf" 2>/dev/null | head -1 | sed 's/DocumentRoot //')
        
        if [ -z "$doc_root" ]; then
            doc_root="$SITES_DIR/$domain"
        fi
    fi
    
    # Confirm removal
    echo ""
    echo "You are about to remove the website: $domain"
    echo "Document Root: $doc_root"
    echo ""
    read -p "Are you sure you want to continue? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Operation cancelled."
        return
    fi
    
    # Ask about removing files
    echo ""
    read -p "Do you want to remove all website files from $doc_root? (y/n): " remove_files
    
    # Remove configuration files
    rm -f "$NGINX_VHOSTS_DIR/$domain.conf"
    rm -f "$APACHE_VHOSTS_DIR/$domain.conf"
    rm -f "$BASE_DIR/website_manager/sites/$domain.conf"
    
    # Remove website files if requested
    if [[ "$remove_files" =~ ^[Yy]$ ]]; then
        if [ -d "$doc_root" ]; then
            rm -rf "$doc_root"
            log "Website files removed from $doc_root"
        fi
    else
        log "Website files preserved. You can manually remove them later if needed."
    fi
    
    # Restart web servers
    systemctl reload nginx
    systemctl reload apache2
    
    log "Website '$domain' has been removed successfully!"
}

# Main menu function
main_menu() {
    clear
    echo -e "${BLUE}=== Website Manager ===${NC}"
    echo ""
    echo "1) Create new website"
    echo "2) List all websites"
    echo "3) Edit website configuration"
    echo "4) Remove website"
    echo "5) Exit"
    echo ""
    read -p "Enter your choice [1-5]: " choice
    
    case $choice in
        1) create_website ;;
        2) list_websites ;;
        3) edit_website ;;
        4) remove_website ;;
        5) exit 0 ;;
        *) warning "Invalid option. Please try again." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    main_menu
}

# Create necessary directories
mkdir -p "$BASE_DIR/website_manager/sites"

# Start the main menu
main_menu
