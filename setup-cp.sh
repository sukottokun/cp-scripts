#!/bin/bash

# Pantheon Content Publisher Site Creation and Setup Script
# This script creates either a WordPress or Drupal site on Pantheon and sets up the site for Content Publisher.
# It adds the modules or plugins and commits them to the repo, then enables them.
# It configures solr, clones the repo, and creates the pantheon.yml file.
# It then commits and pushes the pantheon.yml changes to the remote repo.
# It then creates the PCC site ID and configures the webhook. 
# You have to have PCC and Terminus installed.
#
# DEBUG MODE: Set DEBUG_MODE=true below to step through major operations
# - Press Enter to continue to the next step
# - Press 's' to skip the current step
# - Press 'q' to quit the script

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
    
    if terminus auth:login --machine-token="$TERMINUS_MACHINE_TOKEN"; then
        print_success "Successfully logged into Terminus"
    else
        print_error "Failed to login to Terminus"
        exit 1
    fi
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
    debug_step "Switch to Git mode" "terminus connection:set $SITE_NAME.dev git --yes"
    print_status "Switching to Git mode..."
    terminus connection:set "$SITE_NAME.dev" git --yes
    
    # Clone repository using terminus local:clone
    debug_step "Clone repository" "terminus local:clone $SITE_NAME"
    print_status "Cloning repository to configure pantheon.yml..."
    
    # Set SSH options to auto-accept host keys and avoid prompts
    export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
    
    # Store current directory to return to later
    ORIGINAL_DIR=$(pwd)
    
    # Clone repository using terminus local:clone (clones to $HOME/pantheon-local-copies)
    if terminus local:clone "$SITE_NAME"; then
        # Navigate to the cloned repository
        cd "$HOME/pantheon-local-copies/$SITE_NAME"
        print_success "Repository cloned successfully"
    else
        print_error "Failed to clone repository"
        unset GIT_SSH_COMMAND
        cd "$ORIGINAL_DIR"
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
  version: 8
EOF
    else
        print_status "Updating existing pantheon.yml..."
        
        # Check if api_version is present
        if ! grep -q "^api_version:" pantheon.yml; then
            print_status "Adding missing api_version to pantheon.yml..."
            # Create a new file with api_version at the top
            {
                echo "api_version: 1"
                echo ""
                cat pantheon.yml
            } > pantheon.yml.tmp && mv pantheon.yml.tmp pantheon.yml
        fi
        
        # Check if search section already exists
        if grep -q "^search:" pantheon.yml; then
            print_warning "Search configuration already exists in pantheon.yml"
        else
            # Add search configuration
            cat >> pantheon.yml << 'EOF'

search:
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
            unset GIT_SSH_COMMAND
            cd "$ORIGINAL_DIR"
            return 1
        fi
    fi
    
    # Clean up - return to original directory
    cd "$ORIGINAL_DIR"
    
    # Reset SSH settings
    unset GIT_SSH_COMMAND
    
    print_success "Solr configuration completed"
    print_status "Note: It may take a few minutes for Solr changes to take effect"
    print_status "Repository remains at: $HOME/pantheon-local-copies/$SITE_NAME"
}

# Function to create PCC site and configure webhook
configure_pcc() {
    debug_step "Create PCC site ID" "pcc site create --url $SITE_URL"
    
    print_status "Creating Pantheon Content Cloud site..."
    
    # Get the site URL without trailing slash
    CLEAN_SITE_URL=$(echo "$SITE_URL" | sed 's/\/$//')
    
    # Create PCC site and capture the ID
    PCC_OUTPUT=$(pcc site create --url "$CLEAN_SITE_URL" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        # Extract the site ID from the output (format: "Id: xXXXXXXXXXXX")
        PCC_SITE_ID=$(echo "$PCC_OUTPUT" | grep -o 'Id: [a-zA-Z0-9]*' | cut -d' ' -f2)
        
        if [[ -n "$PCC_SITE_ID" ]]; then
            print_success "PCC site created successfully with ID: $PCC_SITE_ID"
            
            # Configure the webhook
            debug_step "Configure PCC webhook" "pcc site configure $PCC_SITE_ID --webhook-url $CLEAN_SITE_URL/api/pantheoncloud/webhook"
            print_status "Configuring PCC webhook..."
            
            if pcc site configure "$PCC_SITE_ID" --webhook-url "$CLEAN_SITE_URL/api/pantheoncloud/webhook"; then
                print_success "PCC webhook configured successfully"
            else
                print_warning "Failed to configure PCC webhook - you may need to do this manually"
            fi
        else
            print_warning "Could not extract PCC site ID from output - you may need to create manually"
        fi
    else
        print_warning "Failed to create PCC site - you may need to do this manually"
        print_warning "Output: $PCC_OUTPUT"
    fi
}

# Function to install Drupal modules
install_drupal_modules() {
    debug_step "Install Drupal modules" "Switch to SFTP, install via composer, enable modules"
    
    print_status "Installing Drupal modules..."
    
    # Switch to SFTP mode for file changes
    debug_step "Switch to SFTP mode" "terminus connection:set $SITE_NAME.dev sftp --yes"
    print_status "Switching to SFTP mode..."
    terminus connection:set "$SITE_NAME.dev" sftp --yes
    
    # Install modules via Composer
    debug_step "Install search_api_pantheon" "terminus composer $SITE_NAME.dev -- require drupal/search_api_pantheon:^8"
    print_status "Installing search_api_pantheon module..."
    terminus composer "$SITE_NAME.dev" -- require drupal/search_api_pantheon:^8
    
    debug_step "Install pantheon_content_publisher" "terminus composer $SITE_NAME.dev -- require 'drupal/pantheon_content_publisher:^1.0'"
    print_status "Installing pantheon_content_publisher module..."
    terminus composer "$SITE_NAME.dev" -- require 'drupal/pantheon_content_publisher:^1.0'
    
    # Commit composer files before switching to git mode
    debug_step "Commit composer changes" "terminus env:commit $SITE_NAME.dev --message='Add Drupal modules via composer'"
    print_status "Committing composer file changes..."
    if terminus env:commit "$SITE_NAME.dev" --message="Add Drupal modules via composer"; then
        print_success "Composer changes committed"
    else
        print_warning "No changes to commit or commit failed - continuing anyway"
    fi
    
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
    
    # Get site URL for PCC configuration
    SITE_URL=$(terminus env:view "$SITE_NAME.dev" --print)
    
    # Configure Pantheon Content Cloud
    configure_pcc
    
    print_success "Drupal modules installed and enabled"
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
    
    # Get site URL for PCC configuration  
    SITE_URL=$(terminus env:view "$SITE_NAME.dev" --print)
    
    # Configure Pantheon Content Cloud
    configure_pcc
}

# Function to install WordPress plugins
install_wordpress_plugins() {
    debug_step "Install WordPress plugins" "Switch to SFTP, install plugins"
    
    print_status "Installing WordPress plugins..."
    
    # Switch to SFTP mode for plugin installations
    debug_step "Switch to SFTP mode" "terminus connection:set $SITE_NAME.dev sftp --yes"
    print_status "Switching to SFTP mode..."
    terminus connection:set "$SITE_NAME.dev" sftp --yes
    
    # Install Pantheon Content Publisher plugin from GitHub (latest version)
    debug_step "Install Pantheon Content Publisher plugin" "terminus wp $SITE_NAME.dev -- plugin install https://github.com/pantheon-systems/pantheon-content-publisher-wordpress/releases/latest/download/pantheon-content-publisher-for-wordpress.zip --activate"
    print_status "Installing Pantheon Content Publisher plugin..."
    terminus wp "$SITE_NAME.dev" -- plugin install https://github.com/pantheon-systems/pantheon-content-publisher-wordpress/releases/latest/download/pantheon-content-publisher-for-wordpress.zip --activate
    
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
    echo "Pantheon Content Cloud Setup:"
    echo "=============================="
    
    if [[ -n "$PCC_SITE_ID" ]]; then
        echo "PCC Site ID: $PCC_SITE_ID"
    else
        echo "PCC Site ID: (creation may have failed - check output above)"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Create an access token for the above collection ID here:"
    echo "   https://content.pantheon.io/dashboard/settings/tokens"
    echo ""
    
    if [[ "$SITE_TYPE" == "drupal" ]]; then
        CLEAN_SITE_URL=$(echo "$(terminus env:view "$SITE_NAME.dev" --print)" | sed 's/\/$//')
        echo "2. Add the site ID and token you just created to your Drupal site here:"
        echo "   $CLEAN_SITE_URL/admin/structure/pantheon-content-publisher-collection"
    else
        echo "2. Configure the site ID and token in your WordPress admin panel"
    fi
    
    echo "3. Install the Google Add-on and you should be good to publish!"
    echo ""
}

# Main script execution
main() {
    echo "======================================================="
    echo "Pantheon Content Publisher Site Deployment Script"
    echo "======================================================="
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