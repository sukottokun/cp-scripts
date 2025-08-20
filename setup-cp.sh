#!/bin/bash

# Pantheon Site Creation and Setup Script
# This script creates either a WordPress or Drupal site on Pantheon and installs modules/plugins
#
# DEBUG MODE: Set DEBUG_MODE=true below to step through major operations
# In debug mode, you can:
# - Press Enter to continue to the next step
# - Press 's' to skip the current step
# - Press 'q' to quit the script

set -e  # Exit on any error

# Configuration
MACHINE_TOKEN="1FhOx08DCFsXcpJJ6aYEygwu3Yl-K2g59jZMvDX_ltbZf"
ORG="pantheon-employees"
REGION="us"
ADMIN_EMAIL="scottmassey@pantheon.io"
ADMIN_PASSWORD="demo"
WP_ADMIN_PASSWORD="StrongPassword123!"

# Debug mode - set to true to step through major operations
DEBUG_MODE=false

# Function to print output
print_status() {
    echo "[INFO] $1"
}

# Function to configure Solr for Drupal
configure_solr() {
    debug_step "Configure Solr" "Enable Solr, clone repo, edit pantheon.yml, push changes"
    
    print_status "Configuring Solr for Drupal..."
    
    # Enable Solr via terminus
    debug_step "Enable Solr service" "terminus solr:enable $SITE_NAME"
    print_status "Enabling Solr service..."
    if terminus solr:enable "$SITE_NAME"; then
        print_success "Solr enabled successfully"
    else
        print_warning "Solr may already be enabled or failed to enable"
    fi
    
    # Switch to git mode for making code changes
    debug_step "Switch to Git mode" "terminus connection:set $SITE_NAME.dev git"
    print_status "Switching to Git mode..."
    terminus connection:set "$SITE_NAME.dev" git
    
    # Create temporary directory and clone the repo
    debug_step "Clone repository" "terminus local:clone $SITE_NAME.dev"
    print_status "Cloning repository to configure pantheon.yml..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Clone repository using terminus local:clone
    if terminus local:clone "$SITE_NAME.dev" "$SITE_NAME-repo"; then
        cd "$SITE_NAME-repo"
        print_success "Repository cloned successfully"
    else
        print_error "Failed to clone repository"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Check if pantheon.yml exists, create if not
    debug_step "Edit pantheon.yml" "Add Solr configuration to pantheon.yml"
    print_status "Configuring pantheon.yml for Solr..."
    
    if [[ ! -f pantheon.yml ]]; then
        print_status "Creating pantheon.yml..."
        cat > pantheon.yml << 'EOF'
api_version: 1

search:
  solr:
    version: 8
EOF
    else
        print_status "Updating existing pantheon.yml..."
        # Check if search section already exists
        if grep -q "^search:" pantheon.yml; then
            print_warning "Search configuration already exists in pantheon.yml"
        else
            # Add search configuration
            cat >> pantheon.yml << 'EOF'

search:
  solr:
    version: 8
EOF
        fi
    fi
    
    # Commit and push changes
    debug_step "Commit and push changes" "git add, commit, and push pantheon.yml"
    print_status "Committing and pushing pantheon.yml changes..."
    
    git add pantheon.yml
    
    if git diff --staged --quiet; then
        print_warning "No changes to commit"
    else
        git commit -m "Add Solr configuration to pantheon.yml"
        
        if git push origin master; then
            print_success "pantheon.yml changes pushed successfully"
        else
            print_error "Failed to push changes"
            cd - > /dev/null
            rm -rf "$TEMP_DIR"
            return 1
        fi
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    print_success "Solr configuration completed"
    print_status "Note: It may take a few minutes for Solr changes to take effect"
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

# Debug function - pauses execution and shows what's about to happen
debug_step() {
    if [[ "$DEBUG_MODE" == true ]]; then
        echo ""
        echo "=== DEBUG STEP ==="
        echo "About to: $1"
        if [[ -n "$2" ]]; then
            echo "Command: $2"
        fi
        echo "=================="
        read -p "Press Enter to continue, 's' to skip this step, or 'q' to quit: " DEBUG_ACTION
        case $DEBUG_ACTION in
            s|S)
                echo "Skipping step..."
                return 1
                ;;
            q|Q)
                echo "Quitting debug session..."
                exit 0
                ;;
            *)
                echo "Continuing..."
                return 0
                ;;
        esac
    fi
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
    debug_step "Log into Terminus" "terminus auth:login --machine-token=..."
    
    print_status "Logging into Terminus..."
    
    if terminus auth:login --machine-token="$MACHINE_TOKEN"; then
        print_success "Successfully logged into Terminus"
    else
        print_error "Failed to login to Terminus"
        exit 1
    fi
}

# Function to create Drupal site
create_drupal_site() {
    debug_step "Create Drupal site" "terminus site:create --org=$ORG --region=$REGION -- $SITE_NAME $SITE_NAME drupal-10-composer-managed"
    
    print_status "Creating Drupal site: $SITE_NAME"
    
    # Create the site
    print_status "Creating site (this may take 10 minutes)..."
    if terminus site:create --org="$ORG" --region="$REGION" -- "$SITE_NAME" "$SITE_NAME" drupal-10-composer-managed; then
        print_success "Site created successfully"
    else
        print_error "Failed to create site"
        exit 1
    fi
    
    # Wait for site to be ready
    debug_step "Wait for site to be ready" "sleep 30"
    print_status "Waiting for site to be ready..."
    sleep 30
    
    # Install Drupal
    debug_step "Install Drupal" "terminus drush $SITE_NAME.dev -- site:install -y ..."
    print_status "Installing Drupal..."
    if terminus drush "$SITE_NAME.dev" -- site:install -y --account-pass="$ADMIN_PASSWORD" --account-name=admin --account-mail="$ADMIN_EMAIL"; then
        print_success "Drupal installed successfully"
    else
        print_error "Failed to install Drupal"
        exit 1
    fi
    
    # Install modules
    install_drupal_modules
}

# Function to install Drupal modules
install_drupal_modules() {
    debug_step "Install Drupal modules" "Switch to SFTP, install via composer, enable modules"
    
    print_status "Installing Drupal modules..."
    
    # Switch to SFTP mode for file changes
    debug_step "Switch to SFTP mode" "terminus connection:set $SITE_NAME.dev sftp"
    print_status "Switching to SFTP mode..."
    terminus connection:set "$SITE_NAME.dev" sftp
    
    # Install modules via Composer
    debug_step "Install search_api_pantheon" "terminus composer $SITE_NAME.dev -- require drupal/search_api_pantheon:^8"
    print_status "Installing search_api_pantheon module..."
    terminus composer "$SITE_NAME.dev" -- require drupal/search_api_pantheon:^8
    
    debug_step "Install pantheon_content_publisher" "terminus composer $SITE_NAME.dev -- require 'drupal/pantheon_content_publisher:^1.0'"
    print_status "Installing pantheon_content_publisher module..."
    terminus composer "$SITE_NAME.dev" -- require 'drupal/pantheon_content_publisher:^1.0'
    
    # Enable modules
    debug_step "Enable modules" "terminus drush $SITE_NAME.dev -- en search_api_pantheon pantheon_content_publisher -y"
    print_status "Enabling modules..."
    terminus drush "$SITE_NAME.dev" -- en search_api_pantheon pantheon_content_publisher -y
    
    # Clear cache
    debug_step "Clear Drupal cache" "terminus drush $SITE_NAME.dev -- cr"
    print_status "Clearing Drupal cache..."
    terminus drush "$SITE_NAME.dev" -- cr
    
    # Configure Solr
    configure_solr
    
# Function to configure Solr for Drupal
configure_solr() {
    debug_step "Configure Solr" "Enable Solr, clone repo, edit pantheon.yml, push changes"
    
    print_status "Configuring Solr for Drupal..."
    
    # Enable Solr via terminus
    debug_step "Enable Solr service" "terminus solr:enable $SITE_NAME"
    print_status "Enabling Solr service..."
    if terminus solr:enable "$SITE_NAME"; then
        print_success "Solr enabled successfully"
    else
        print_warning "Solr may already be enabled or failed to enable"
    fi
    
    # Switch to git mode for making code changes
    debug_step "Switch to Git mode" "terminus connection:set $SITE_NAME.dev git"
    print_status "Switching to Git mode..."
    terminus connection:set "$SITE_NAME.dev" git
    
    # Create temporary directory and clone the repo
    debug_step "Clone repository" "git clone ssh://codeserver.dev.xxx@codeserver.dev.xxx.drush.in:2222/~/repository.git"
    print_status "Cloning repository to configure pantheon.yml..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Get git clone command from Pantheon
    GIT_URL=$(terminus connection:info "$SITE_NAME.dev" --field=git_command | sed 's/git clone //')
    
    if git clone "$GIT_URL" "$SITE_NAME-repo"; then
        cd "$SITE_NAME-repo"
        print_success "Repository cloned successfully"
    else
        print_error "Failed to clone repository"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Check if pantheon.yml exists, create if not
    debug_step "Edit pantheon.yml" "Add Solr configuration to pantheon.yml"
    print_status "Configuring pantheon.yml for Solr..."
    
    if [[ ! -f pantheon.yml ]]; then
        print_status "Creating pantheon.yml..."
        cat > pantheon.yml << 'EOF'
api_version: 1

search:
  solr:
    version: 8
EOF
    else
        print_status "Updating existing pantheon.yml..."
        # Check if search section already exists
        if grep -q "^search:" pantheon.yml; then
            print_warning "Search configuration already exists in pantheon.yml"
        else
            # Add search configuration
            cat >> pantheon.yml << 'EOF'

search:
  solr:
    version: 8
EOF
        fi
    fi
    
    # Commit and push changes
    debug_step "Commit and push changes" "git add, commit, and push pantheon.yml"
    print_status "Committing and pushing pantheon.yml changes..."
    
    git add pantheon.yml
    
    if git diff --staged --quiet; then
        print_warning "No changes to commit"
    else
        git commit -m "Add Solr configuration to pantheon.yml"
        
        if git push origin master; then
            print_success "pantheon.yml changes pushed successfully"
        else
            print_error "Failed to push changes"
            cd - > /dev/null
            rm -rf "$TEMP_DIR"
            return 1
        fi
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    print_success "Solr configuration completed"
    print_status "Note: It may take a few minutes for Solr changes to take effect"
}

# Function to create WordPress site
create_wordpress_site() {
    debug_step "Create WordPress site" "terminus site:create --org=$ORG --region=$REGION -- $SITE_NAME $SITE_NAME wordpress"
    
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
    debug_step "Wait for site to be ready" "sleep 30"
    print_status "Waiting for site to be ready..."
    sleep 30
    
    # Complete WordPress installation
    debug_step "Complete WordPress installation" "terminus wp $SITE_NAME.dev -- core install ..."
    print_status "Completing WordPress installation..."
    
    # Get site URL
    SITE_URL=$(terminus env:view "$SITE_NAME.dev" --print)
    
    # Complete the WordPress installation through WP-CLI
    terminus wp "$SITE_NAME.dev" -- core install --url="$SITE_URL" --title="$SITE_NAME" --admin_user=admin --admin_password="$WP_ADMIN_PASSWORD" --admin_email="$ADMIN_EMAIL"
    
    # Create additional admin user
    debug_step "Create additional admin user" "terminus wp $SITE_NAME.dev -- user create admin_user ..."
    print_status "Creating admin user..."
    terminus wp "$SITE_NAME.dev" -- user create admin_user "$ADMIN_EMAIL" --role=administrator --user_pass="$WP_ADMIN_PASSWORD"
    
    # Install WordPress plugins
    install_wordpress_plugins
}

# Function to install WordPress plugins
install_wordpress_plugins() {
    debug_step "Install WordPress plugins" "Switch to SFTP, install plugins"
    
    print_status "Installing WordPress plugins..."
    
    # Switch to SFTP mode for plugin installations
    debug_step "Switch to SFTP mode" "terminus connection:set $SITE_NAME.dev sftp"
    print_status "Switching to SFTP mode..."
    terminus connection:set "$SITE_NAME.dev" sftp
    
    # Install Pantheon Content Publisher plugin from GitHub (latest version)
    debug_step "Install Pantheon Content Publisher plugin" "terminus wp $SITE_NAME.dev -- plugin install https://github.com/pantheon-systems/pantheon-content-publisher-wordpress/releases/latest/download/pantheon-content-publisher-for-wordpress.zip --activate"
    print_status "Installing Pantheon Content Publisher plugin..."
    terminus wp "$SITE_NAME.dev" -- plugin install https://github.com/pantheon-systems/pantheon-content-publisher-wordpress/releases/latest/download/pantheon-content-publisher-for-wordpress.zip --activate
    
    # Install other common plugins
    debug_step "Install additional plugins" "terminus wp $SITE_NAME.dev -- plugin install akismet jetpack --activate"
    print_status "Installing additional plugins..."
    terminus wp "$SITE_NAME.dev" -- plugin install akismet --activate
    terminus wp "$SITE_NAME.dev" -- plugin install jetpack --activate
    
    print_success "WordPress plugins installation completed"
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
        echo "Additional User: admin_user"
    fi
    echo ""
}

# Main script execution
main() {
    echo "==================================="
    echo "Pantheon Site Deployment Script"
    echo "==================================="
    echo ""
    
    if [[ "$DEBUG_MODE" == true ]]; then
        echo "[DEBUG MODE ENABLED]"
        echo "You can press 's' to skip steps or 'q' to quit at any debug prompt"
        echo ""
    fi
    
    # Get site type from user
    while true; do
        read -p "Choose site type (drupal/wordpress): " SITE_TYPE
        case $SITE_TYPE in
            drupal|wordpress)
                break
                ;;
            *)
                print_error "Please enter 'drupal' or 'wordpress'"
                ;;
        esac
    done
    
    # Generate site name
    debug_step "Generate site name" "Create random site name from dictionary words"
    generate_site_name
    
    # Confirm with user
    read -p "Proceed with creating $SITE_TYPE site '$SITE_NAME'? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
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
    
    debug_step "Display site information" "Show final site details and URLs"
    display_site_info
}

# Check if terminus is installed
if ! command -v terminus &> /dev/null; then
    print_error "Terminus CLI is not installed. Please install it first."
    exit 1
fi

# Run main function
main
