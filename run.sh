#!/bin/bash

# Check if the correct number of parameters are passed
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 old_domain new_domain"
    exit 1
fi

# Assign parameters to variables
old_domain=$1
new_domain=$2
# Define the new domain path
domain_new_path="/home/$new_domain/public_html"
# Define the old domain path
domain_old_path="/home/$old_domain/public_html"

script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
extension_zip="$script_dir/all-in-one-wp-migration-unlimited-extension.zip"
echo "$extension_zip"

# Define the backup_domain function
backup_domain() {
    local domain_path="$1"
    local domain=$(basename "$(dirname "$domain_path")") # Extract domain name
    local owner_group=$(stat -c "%U:%G" "$domain_path")
    
    cd "$domain_path" || {
        echo "Directory not found: $domain_path"
        return
    }
    echo "$domain_path"
    echo "$domain"
    echo "$owner_group"

    echo "Start for $domain"

    if ! wp --allow-root plugin is-active all-in-one-wp-migration; then
        # Check if the plugin is installed
        if ! wp --allow-root plugin is-installed all-in-one-wp-migration; then
            # Install and activate the plugin
            echo "Install and activate all-in-one-wp-migration"
            wp --allow-root plugin install all-in-one-wp-migration --activate
        else
            # Activate the plugin if it's installed but not active
            echo "Activate all-in-one-wp-migration"
            wp --allow-root plugin update all-in-one-wp-migration
            wp --allow-root plugin activate all-in-one-wp-migration
        fi
        sudo chown -R "$owner_group" /home/"$domain"/public_html/wp-content/plugins/all-in-one-wp-migration/
        sudo chmod -R 755 /home/"$domain"/public_html/wp-content/plugins/all-in-one-wp-migration/
    else
        wp --allow-root plugin update all-in-one-wp-migration
        echo "all-in-one-wp-migration is already active"
    fi

    local ext_dir="/home/$domain/public_html/wp-content/plugins/all-in-one-wp-migration-unlimited-extension/"
    if wp --allow-root plugin is-active all-in-one-wp-migration-unlimited-extension; then
        # Check if the unlimited extension is installed
        echo "all-in-one-wp-migration-unlimited-extension is already active"
        wp --allow-root plugin deactivate all-in-one-wp-migration-unlimited-extension
    fi
    wp --allow-root plugin delete all-in-one-wp-migration-unlimited-extension
    wp --allow-root plugin install "$extension_zip" --activate
    sudo chown -R "$owner_group" "$ext_dir"
    sudo chmod -R 755 "$ext_dir"

    echo "Start backup for $domain"
    backup_dir="/home/$domain/public_html/wp-content/ai1wm-backups"
    # remove older backup
    sudo rm -rf "$backup_dir"/*.wpress

    wp ai1wm backup --sites --allow-root --exclude-cache
    echo "Backup Size: $(du -sh "$backup_dir"/*.wpress)"
    
    # Get the latest backup filename
    cd "$backup_dir" || exit
    latest_backup="$(ls -1t | head -n1)"

    if [ $? -ne 0 ]; then
        echo "Failed to create backup for $domain"
    fi

    # Uninstall the All-in-One WP Migration plugins
    wp --allow-root plugin deactivate all-in-one-wp-migration-unlimited-extension
    wp --allow-root plugin delete all-in-one-wp-migration-unlimited-extension

    wp --allow-root plugin deactivate all-in-one-wp-migration
    wp --allow-root plugin delete all-in-one-wp-migration
}

# Define the restore_domain function
restore_domain() {
    local domain_path="$1"
    local domain=$(basename "$(dirname "$domain_path")") # Extract domain name
    local owner_group=$(stat -c "%U:%G" "$domain_path")
    echo "Restoring $domain"

    cd "$domain_path" || {
        echo "Directory not found: $domain_path"
        return
    }

    echo "$domain_path"
    echo "$domain"
    echo "$owner_group"

    # Install and activate the required plugins
    wp --allow-root plugin install all-in-one-wp-migration --activate
    wp --allow-root plugin install "$extension_zip" --activate

    sudo chown -R "$owner_group" /home/"$domain"/public_html/wp-content/plugins/all-in-one-wp-migration/
    sudo chmod -R 755 /home/"$domain"/public_html/wp-content/plugins/all-in-one-wp-migration/

    sudo chown -R "$owner_group" /home/"$domain"/public_html/wp-content/plugins/all-in-one-wp-migration-unlimited-extension/
    sudo chmod -R 755 /home/"$domain"/public_html/wp-content/plugins/all-in-one-wp-migration-unlimited-extension/

    # Perform the restore
    backup_dir="/home/$domain/public_html/wp-content/ai1wm-backups"
    latest_backup="$(ls -1t "$backup_dir"/*.wpress | head -n1)"

    if [ -z "$latest_backup" ]; then
        echo "No backup file found to restore for $domain"
        return
    fi

    wp ai1wm restore "$latest_backup" --allow-root
    echo "Restore completed for $domain"

	mv "$domain_old_path/wp-content/ai1wm-backups/"*.wpress "$domain_new_path/wp-content/ai1wm-backups/"

    # Uninstall the All-in-One WP Migration plugins after restore
    wp --allow-root plugin deactivate all-in-one-wp-migration-unlimited-extension
    wp --allow-root plugin delete all-in-one-wp-migration-unlimited-extension

    wp --allow-root plugin deactivate all-in-one-wp-migration
    wp --allow-root plugin delete all-in-one-wp-migration
}



# Check if the old domain path exists
if [ -d "$domain_old_path" ]; then
    echo "Step 1: Found the directory for the old domain at $domain_old_path"
    # Call the backup_domain function
    backup_domain "$domain_old_path"
else
    echo "Error: Directory $domain_old_path does not exist!"
    exit 1
fi

# Create the new domain directory if it doesn't exist
if [ -d "$domain_new_path" ]; then
    restore_domain "$domain_new_path"
else
    echo "Error: Directory $domain_new_path does not exist!"
    exit 1
fi
