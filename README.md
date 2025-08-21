# Pantheon Content Publisher Setup Script

This script automates the creation and setup of WordPress or Drupal sites on Pantheon with Content Publisher functionality.
* WordPress isn't working yet! Run it and it'll fuck your shit up. *

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
