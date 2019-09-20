#!/bin/bash

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/wordpress_update.sh\n" "$SCRIPTS"
    exit 1
fi

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# System Upgrade
apt update -q2
apt dist-upgrade -y

# Update Redis PHP extension
print_text_in_color "$ICyan" "Trying to upgrade the Redis PECL extenstion..."
if ! pecl list | grep redis >/dev/null 2>&1
then
    if is_this_installed php"$PHPVER"
    then
        install_if_not php"$PHPVER"-dev
    else
        install_if_not php7.0-dev
    fi
    apt purge php-redis -y
    apt autoremove -y
    pecl channel-update pecl.php.net
    yes no | pecl install redis
    service redis-server restart
    if nginx -v 2> /dev/null
    then
        service nginx restart
    elif apache2 -v 2> /dev/null
    then
        service apache2 restart
    fi
elif pecl list | grep redis >/dev/null 2>&1
then
    if is_this_installed php"$PHPVER"
    then
        install_if_not php"$PHPVER"-dev
    else
        install_if_not php7.0-dev
    fi
    pecl channel-update pecl.php.net
    yes no | pecl upgrade redis
    service redis-server restart
    if nginx -v 2> /dev/null
    then
        service nginx restart
    elif apache2 -v 2> /dev/null
    then
        service apache2 restart
    fi
fi

# Upgrade APCu and igbinary
if is_this_installed php"$PHPVER"
then
    if [ -f "$PHP_INI" ]
    then
        print_text_in_color "$ICyan" "Trying to upgrade igbinary and APCu..."
        if pecl list | grep igbinary >/dev/null 2>&1
        then
            yes no | pecl upgrade igbinary
            # Check if igbinary.so is enabled
            if ! grep -qFx extension=igbinary.so "$PHP_INI"
            then
                echo "extension=igbinary.so" >> "$PHP_INI"
            fi
        fi
        if pecl list | grep apcu >/dev/null 2>&1
        then
            yes no | pecl upgrade apcu
            # Check if apcu.so is enabled
            if ! grep -qFx extension=apcu.so "$PHP_INI"
            then
                echo "extension=apcu.so" >> "$PHP_INI"
            fi
        fi
    fi
fi

# Update adminer
if [ -d $ADMINERDIR ]
then
    print_text_in_color "$ICyan" "Updating Adminer..."
    rm -f "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php
    wget -q "http://www.adminer.org/latest.php" -O "$ADMINERDIR"/latest.php
    ln -s "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php
fi

# Check if Wordpress is installed in the regular path or try to find it
if [ ! -d "$WPATH" ]
then
    WPATH="/var/www/$(find /var/www/* -type d | grep wp | head -1 | cut -d "/" -f4)"
    export WPATH
    if [ ! -d "$WPATH"/wp-admin ]
    then
        WPATH="/var/www/$(find /var/www/* -type d | grep wp | tail -1 | cut -d "/" -f4)"
        export WPATH
        if [ ! -d "$WPATH"/wp-admin ]
        then
            WPATH="/var/www/html/$(find /var/www/html/* -type d | grep wp | head -1 | cut -d "/" -f5)"
            export WPATH
            if [ ! -d "$WPATH"/wp-admin ]
            then
                WPATH="/var/www/html/$(find /var/www/html/* -type d | grep wp | tail -1 | cut -d "/" -f5)"
                export WPATH
                if [ ! -d "$WPATH"/wp-admin ]
                then
msg_box "Wordpress doesn't seem to be installed in the regular path. We tried to find it, but didn't succeed.

The script will now exit."
                    exit 1
                fi
            fi
        fi
    fi
fi

# Set secure permissions
if [ ! -f "$SECURE" ]
then
    mkdir -p "$SCRIPTS"
    download_static_script wp-permissions
    chmod +x "$SECURE"
    bash "$SECURE"
elif [ -f "$SECURE" ]
then
    bash "$SECURE"
fi

# Upgrade WP-CLI
wp cli update

# Upgrade Wordpress and apps
cd "$WPATH"
wp_cli_cmd db export mysql_backup.sql
mv "$WPATH"/mysql_backup.sql /var/www/mysql_backup.sql
chown root:root /var/www/mysql_backup.sql
wp_cli_cmd core update --force
wp_cli_cmd plugin update --all
wp_cli_cmd core update-db
wp_cli_cmd db optimize
print_text_in_color "$ICyan" "This is the current version installed:"
wp_cli_cmd core version --extra

# Cleanup un-used packages
apt autoremove -y
apt autoclean

# Update GRUB, just in case
update-grub

# Write to log
touch /var/log/cronjobs_success.log
echo "WORDPRESS UPDATE success-$(date +%Y-%m-%d_%H:%M)" >> /var/log/cronjobs_success.log

# Un-hash this if you want the system to reboot
# reboot

exit
