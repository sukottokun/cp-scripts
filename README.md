# Pantheon Content Publisher Setup Script

This script automates the creation and setup of WordPress or Drupal sites on Pantheon with Content Publisher functionality.

## 📋 **What This Script Does**

This script handles the entire process of creating and configuring Pantheon sites for Content Publisher:

### **Site Creation & Setup**
- Creates either a WordPress or Drupal site on Pantheon
- Generates a random site name using dictionary words
- Sets up CMS admin accounts with specified credentials
- Handles both Drupal 11 Composer-managed and WordPress upstreams

### **Module/Plugin Installation**
- **Drupal**: Installs and enables `search_api_pantheon` (dev version currently), `pantheon_content_publisher`, `pathauto`, and `token` modules
- **WordPress**: Installs Pantheon Content Publisher plugin
- Automatically commits all changes to the repository

### **Solr Configuration (Drupal)**
- Enables Solr service via Terminus
- Clones the repository locally using Terminus [local:clone](https://docs.pantheon.io/terminus/commands/local-clone) command 
- Creates/updates `pantheon.yml` with proper Solr configuration
- Commits and pushes all changes to the remote repository

### **Pantheon Content Cloud (PCC) Setup**
- Creates PCC site ID
- Configures webhook URL for content synchronization

### **Misc**
- **Debug Mode**: Step-through execution with skip/quit options
- **Error Handling**: Comprehensive error checking and user feedback
- **Repository Management**: Automatic Git operations and commits
- **Environment Validation**: Ensures all required tools and credentials are available

### **Prerequisites**
- Pantheon Terminus CLI installed and configured
- Pantheon Content Cloud CLI (`pcc`) installed
- Valid Pantheon machine token with appropriate permissions
- Access to the specified organization

## 🔧 **Installation**

### **Required Tools**

#### **Terminus CLI**
[Terminus](https://docs.pantheon.io/terminus) is Pantheon's command line interface that provides advanced interaction with the platform.

#### **PCC CLI (Pantheon Content Cloud)**
[PCC CLI](https://www.npmjs.com/package/@pantheon-systems/pcc-cli) is the command line tool for Pantheon Content Cloud operations.

## Setup

1. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Edit the `.env` file** with your actual values:
   - `TERMINUS_MACHINE_TOKEN`: Your Pantheon Terminus machine token
   - `ORG`: Your Pantheon organization name
   - `REGION`: Your preferred region (default: us)
   - `ADMIN_EMAIL`: Admin email for the site
   - `ADMIN_PASSWORD`: Admin password for Drupal sites
   - `WP_ADMIN_PASSWORD`: Admin password for WordPress sites
   - `DEBUG_MODE`: Set to `true` for step-by-step execution

3. **Make the script executable:**
   ```bash
   chmod +x setup-cp.sh
   ```

## Usage

Run the script:
```bash
./setup-cp.sh
```

The script will:
- Prompt you to choose between Drupal or WordPress
- Generate a random site name
- Create the site on Pantheon
- Install and configure necessary modules/plugins
- Set up Solr (for Drupal)
- Configure Pantheon Content Cloud
- Provide you with site information and next steps

## Security Notes

- The `.env` file contains sensitive information and is excluded from version control
- Never commit your actual `.env` file to the repository
- The `.env.example` file shows the required format without real values

## Requirements

- Pantheon Terminus CLI installed
- Pantheon Content Cloud CLI (`pcc`) installed
- Valid Pantheon machine token
- Access to the specified organization
