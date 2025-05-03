#!/bin/bash
# server-tools.sh - Quick tool to download and run server scripts from GitHub
# Usage: ./server-tools.sh [script] [arguments]

# Configuration - Change these to match your GitHub repository
GITHUB_USERNAME="script-php"
REPO_NAME="testhost"
BRANCH="main"

# Base URL for raw GitHub content
# BASE_URL="http://loccalhost/cpanel/"
# BASE_URL="https://raw.githubusercontent.com/$GITHUB_USERNAME/$REPO_NAME/$BRANCH"


# Available scripts
SCRIPTS=("server_install.sh" "site_config.sh" "php_switcher.sh")

# Function to display help
show_help() {
    echo "Server Management Tools"
    echo "----------------------"
    echo "Usage: $0 [script] [arguments]"
    echo ""
    echo "Available scripts:"
    echo "  install   - Run server_install.sh to set up the complete server environment"
    echo "  site      - Run site_config.sh to create a new website configuration"
    echo "  php       - Run php_switcher.sh to switch PHP version for a website"
    echo "  update    - Update this script to the latest version"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 site example.com 8.1"
    echo "  $0 php example.com 8.2"
}

# Function to run a script from GitHub
run_script() {
    local script=$1
    shift  # Remove the first argument (script name)
    
    echo "Executing $script from GitHub repository..."
    bash <(curl -s "$BASE_URL/$script") "$@"
    
    return $?
}

# Function to update this script
update_self() {
    echo "Updating server-tools.sh to the latest version..."
    curl -s "$BASE_URL/server-tools.sh" > "$0.new"
    
    if [ $? -eq 0 ]; then
        chmod +x "$0.new"
        mv "$0.new" "$0"
        echo "Update successful!"
    else
        echo "Update failed!"
        rm -f "$0.new"
    fi
}

# Main script execution
case "$1" in
    install)
        run_script "server_install.sh" "${@:2}"
        ;;
    site)
        run_script "site_config.sh" "${@:2}"
        ;;
    php)
        run_script "php_switcher.sh" "${@:2}"
        ;;
    update)
        update_self
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac

exit $?