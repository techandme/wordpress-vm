#!/bin/bash

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# Check if /boot is filled more than 90% and exit the script if that's 
# the case since we don't want to end up with a broken system
if [ -d /boot ]
then
    if [[ "$(df -h | grep -m 1 /boot | awk '{print $5}' | cut -d "%" -f1)" -gt 90 ]]
    then
        msg_box "It seems like your boot drive is filled more than 90%. \
You can't proceed to upgrade since it probably will break your system
To be able to proceed with the update you need to delete some old Linux kernels. If you need support, please visit:
https://shop.hanssonit.se/product/premium-support-per-30-minutes/"
        exit
    fi
fi

# Ubuntu 16.04 is deprecated
check_distro_version

# Make sure VMLOGS are present
mkdir -p "$VMLOGS"

send_mail \
"Wordpress update started!" \
"Please don't shutdown or reboot your server during the update! $(date +%T)"
wp_cli_cmd maintenance-mode activate

# Hold PHP if Ondrejs PPA is used
print_text_in_color "$ICyan" "Fetching latest packages with apt..."
apt update -q4 & spinner_loading
if apt-cache policy | grep "ondrej" >/dev/null 2>&1
then
    print_text_in_color "$ICyan" "Ondrejs PPA is installed. \
Holding PHP to avoid upgrading to a newer version without migration..."
    apt-mark hold php*
fi

# Make sure everyone gets access to menu.sh
download_script MENU menu

# Make sure fetch_lib.sh is available
download_script STATIC fetch_lib

export DEBIAN_FRONTEND=noninteractive ; apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Update Netdata
if [ -d /etc/netdata ]
then
    print_text_in_color "$ICyan" "Updating Netdata..."
    NETDATA_UPDATER_PATH="$(find /usr -name 'netdata-updater.sh')"
    if [ -n "$NETDATA_UPDATER_PATH" ]
    then
        install_if_not cmake # Needed for Netdata in newer versions
        bash "$NETDATA_UPDATER_PATH"
    fi
fi

# Update Redis PHP extension (18.04 --> 20.04 since 16.04 already is deprecated in the top of this script)
print_text_in_color "$ICyan" "Trying to upgrade the Redis PECL extension..."

# Check current PHP version
check_php

# Do the upgrade
if pecl list | grep redis >/dev/null 2>&1
then
    if is_this_installed php"$PHPVER"-common
    then
        install_if_not php"$PHPVER"-dev
    fi
    pecl channel-update pecl.php.net
    yes no | pecl upgrade redis
    systemctl restart redis-server.service
fi

# Double check if redis.so is enabled
if ! grep -qFx extension=redis.so "$PHP_INI"
then
    echo "extension=redis.so" >> "$PHP_INI"
fi
restart_webserver

# Upgrade APCu and igbinary
if is_this_installed php"$PHPVER"-dev
then
    if [ -f "$PHP_INI" ]
    then
        print_text_in_color "$ICyan" "Trying to upgrade igbinary, and APCu..."
        if pecl list | grep igbinary >/dev/null 2>&1
        then
            yes no | pecl upgrade igbinary
            # Check if igbinary.so is enabled
            if ! grep -qFx extension=igbinary.so "$PHP_INI"
            then
                echo "extension=igbinary.so" >> "$PHP_INI"
            fi
        fi
        if pecl list | grep -q apcu
        then
            yes no | pecl upgrade apcu
            # Check if apcu.so is enabled
            if ! grep -qFx extension=apcu.so "$PHP_INI"
            then
                echo "extension=apcu.so" >> "$PHP_INI"
            fi
        fi
        if pecl list | grep -q inotify
        then 
            yes no | pecl upgrade inotify
            # Check if inotify.so is enabled
            if ! grep -qFx extension=inotify.so "$PHP_INI"
            then
                echo "extension=inotify.so" >> "$PHP_INI"
            fi
        fi
    fi
fi

# Update adminer
if [ -d $ADMINERDIR ]
then
    print_text_in_color "$ICyan" "Updating Adminer..."
    rm -f "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php
    curl_to_dir "http://www.adminer.org" "latest.php" "$ADMINERDIR"
    ln -s "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php
fi

# Cleanup un-used packages
apt autoremove -y
apt autoclean

# Update GRUB, just in case
update-grub

# Remove update lists
rm /var/lib/apt/lists/* -r

# Fix bug in wordpress.sh
CURRUSR="$(getent group sudo | cut -d: -f4 | cut -d, -f1)"
if grep -q "6.ifcfg.me" $SCRIPTS/wordpress.sh &>/dev/null
then
   rm -f "$SCRIPTS/wordpress.sh"
   download_script STATIC wordpress
   chown "$CURRUSR":"$CURRUSR" "$SCRIPTS/wordpress.sh"
   chmod +x "$SCRIPTS/wordpress.sh"
elif [ -f $SCRIPTS/techandme.sh ]
then
   rm -f "$SCRIPTS/techandme.sh"
   download_script STATIC wordpress
   chown "$CURRUSR":"$CURRUSR" "$SCRIPTS/wordpress.sh"
   chmod +x "$SCRIPTS/wordpress.sh"
   if [ -f /home/"$CURRUSR"/.bash_profile ]
   then
       sed -i "s|techandme|wordpress|g" /home/"$CURRUSR"/.bash_profile
   elif [ -f /home/"$CURRUSR"/.profile ]
   then
       sed -i "s|techandme|wordpress|g" /home/"$CURRUSR"/.profile
   fi
fi

# Set secure permissions
if [ ! -f "$SECURE" ]
then
    mkdir -p "$SCRIPTS"
    download_script STATIC wp-permissions
    chmod +x "$SECURE"
else
    rm "$SECURE"
    download_script STATIC wp-permissions
    chmod +x "$SECURE"
fi

# Create WP-CLI CACHE DIR
mkdir -p /var/www/.wp-cli/cache/
chown www-data:www-data -R /var/www/.wp-cli/cache/

# Upgrade WP-CLI
wp cli update

# Upgrade Wordpress and apps
wp_cli_cmd db export mysql_backup.sql
mv "$WPATH"/mysql_backup.sql /var/www/mysql_backup.sql
chown root:root /var/www/mysql_backup.sql
wp_cli_cmd core update --force
wp_cli_cmd plugin update --all
wp_cli_cmd core update-db
wp_cli_cmd db optimize
print_text_in_color "$ICyan" "This is the current version installed:"
if wp_cli_cmd core version --extra
then
    # Write to log
    touch "$VMLOGS"/cronjobs_success.log
    echo "WORDPRESS UPDATE success-$(date +%Y-%m-%d_%H:%M)" >> "$VMLOGS"/cronjobs_success.log
    # Send email
    send_mail \
"Wordpress update finished!" \
"Wordpress update is now complete. Please visit your site to check that everything looks alright. $(date +%T)"
    if wp_cli_cmd maintenance-mode status | grep -q "is active"
    then
        wp_cli_cmd maintenance-mode deactivate
    fi
fi

# Un-hash this if you want the system to reboot
# reboot

exit
