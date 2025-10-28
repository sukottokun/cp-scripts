#!/bin/bash

# shellcheck disable=SC1091

# Basic Pantheon Site Creation Script
# This script creates either a WordPress or Drupal site on Pantheon without any additional modules/plugins.
# You have to have Terminus installed.

set -e  # Exit on any error

# Load environment variables
if [[ -f .env ]]; then
    source .env
else
    echo "[ERROR] .env file not found. Please create one based on env.example"
    exit 1
fi

# Validate required environment variables
if [[ -z "$TERMINUS_MACHINE_TOKEN" || -z "$ORG" || -z "$ADMIN_EMAIL" ]]; then
    echo "[ERROR] Missing required environment variables. Please check your .env file"
    exit 1
fi

# Function to print output
print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_error() {
    echo "[ERROR] $1"
}

# Function to generate site name
generate_site_name() {
    print_status "Generating site name..."
    
    # Check if word dictionary exists
    if [[ ! -f /usr/share/dict/words ]]; then
        print_warning "Dictionary not found, generating simple name..."
        TIMESTAMP=$(date +%s)
        SITE_NAME="site-${TIMESTAMP}"
    else
        WORD1=$(shuf -n1 /usr/share/dict/words | tr '[:upper:]' '[:lower:]' | tr -d "'")
        WORD2=$(shuf -n1 /usr/share/dict/words | tr '[:upper:]' '[:lower:]' | tr -d "'")
        SITE_NAME="${WORD1}-${WORD2}"
    fi
    
    # Clean site name (remove special characters, limit length)
    SITE_NAME=$(echo "$SITE_NAME" | sed 's/[^a-z0-9-]//g' | cut -c1-30)
    
    print_success "Generated site name: $SITE_NAME"
}

# Function to login to Terminus
terminus_login() {
    print_status "Logging into Terminus..."
    
    if terminus auth:login --machine-token="$TERMINUS_MACHINE_TOKEN"; then
        print_success "Successfully logged into Terminus"
    else
        print_error "Failed to login to Terminus"
        exit 1
    fi
}

# Function to create Drupal site
create_drupal_site() {
    print_status "Creating Drupal site: $SITE_NAME"
    
    # Create the site
    print_status "Creating site (this may take 10 minutes)..."
    if terminus site:create --org="$ORG" --region="$REGION" -- "$SITE_NAME" "$SITE_NAME" drupal-11-composer-managed; then
        print_success "Site created successfully"
    else
        print_error "Failed to create site"
        exit 1
    fi
    
    # Wait for site to be ready
    print_status "Waiting for site to be ready..."
    sleep 30
    
    # Install Drupal
    print_status "Installing Drupal..."
    if terminus drush "$SITE_NAME.dev" -- site:install -y --account-pass="$ADMIN_PASSWORD" --account-name=admin --account-mail="$ADMIN_EMAIL"; then
        print_success "Drupal installed successfully"
    else
        print_error "Failed to install Drupal"
        exit 1
    fi
    
    print_success "Drupal site setup completed"
}

# Function to create WordPress site
create_wordpress_site() {
    print_status "Creating WordPress site: $SITE_NAME"
    
    # Create the site
    print_status "Creating WordPress site..."
    if terminus site:create --org="$ORG" --region="$REGION" -- "$SITE_NAME" "$SITE_NAME" wordpress; then
        print_success "WordPress site created successfully"
    else
        print_error "Failed to create WordPress site"
        exit 1
    fi
    
    # Wait for site to be ready
    print_status "Waiting for site to be ready..."
    sleep 30
    
    # Complete WordPress installation
    print_status "Completing WordPress installation..."
    
    # Get site URL
    SITE_URL=$(terminus env:view "$SITE_NAME.dev" --print)
    
    # Complete the WordPress installation through WP-CLI
    terminus remote:wp --progress "$SITE_NAME.dev" -- core install --url="$SITE_URL" --title="$SITE_NAME" --admin_user=admin --admin_password="$WP_ADMIN_PASSWORD" --admin_email="$ADMIN_EMAIL"
    
    print_success "WordPress site setup completed"
}

# Function to display site information
display_site_info() {
    print_success "Site deployment completed!"
    echo ""
    echo "Site Information:"
    echo "=================="
    echo "Site Name: $SITE_NAME"
    echo "Dashboard: $(terminus dashboard "$SITE_NAME.dev" --print)"
    echo "Site URL: $(terminus env:view "$SITE_NAME.dev" --print)"
    echo "Admin Email: $ADMIN_EMAIL"
    
    if [[ "$SITE_TYPE" == "drupal" ]]; then
        echo "Admin Username: admin"
        echo "Admin Password: $ADMIN_PASSWORD"
    else
        echo "Admin Username: admin"
        echo "Admin Password: $WP_ADMIN_PASSWORD"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Visit your site and log in with the credentials above"
    echo "2. Configure your site settings as needed"
    echo "3. Install additional modules/plugins as required"
    echo ""
}

# Main script execution
main() {
    echo "======================================================="
    echo "Basic Pantheon Site Creation Script"
    echo "======================================================="
    echo ""
    
    # Get site type from user
    while true; do
        read -r -p "Choose site type (D)rupal or (W)ordPress: " SITE_TYPE
        case $SITE_TYPE in
            d|D)
                SITE_TYPE="drupal"
                break
                ;;
            w|W)
                SITE_TYPE="wordpress"
                break
                ;;
            *)
                print_error "Please enter 'D' for Drupal or 'W' for WordPress"
                ;;
        esac
    done
    
    # Generate site name
    generate_site_name
    
    # Confirm with user
    read -r -p "Proceed with creating $SITE_TYPE site '$SITE_NAME'? (Y/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        print_warning "Operation cancelled"
        exit 0
    fi
    
    # Execute deployment
    terminus_login
    
    if [[ "$SITE_TYPE" == "drupal" ]]; then
        create_drupal_site
    else
        create_wordpress_site
    fi
    
    display_site_info
}

# Check if terminus is installed
if ! command -v terminus &> /dev/null; then
    print_error "Terminus CLI is not installed. Please install it first."
    exit 1
fi

# Run main function
main
