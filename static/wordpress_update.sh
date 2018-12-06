#!/bin/bash

# T&M Hansson IT AB © - 2018, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
MYCNFPW=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
unset MYCNFPW

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

# Make sure old instaces can upgrade as well
if [ ! -f "$MYCNF" ] && [ -f /var/mysql_password.txt ]
then
    regressionpw=$(grep "New MySQL ROOT password:" /var/mysql_password.txt | awk '{print $5}')
cat << LOGIN > "$MYCNF"
[client]
password='$regressionpw'
LOGIN
    chmod 0600 $MYCNF
    chown root:root $MYCNF
    echo "Please restart the upgrade process, we fixed the password file $MYCNF."
    exit 1
elif [ -z "$MARIADBMYCNFPASS" ] && [ -f /var/mysql_password.txt ]
then
    regressionpw=$(cat /var/mysql_password.txt)
    {
    echo "[client]"
    echo "password='$regressionpw'"
    } >> "$MYCNF"
    echo "Please restart the upgrade process, we fixed the password file $MYCNF."
    exit 1
fi

if [ -z "$MARIADBMYCNFPASS" ]
then
    echo "Something went wrong with copying your mysql password to $MYCNF."
    echo "Please report this issue to $ISSUES, thanks!"
    exit 1
else
    rm -f /var/mysql_password.txt
fi

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# System Upgrade
apt update -q2
apt dist-upgrade -y
# Update Redis PHP extention
if type pecl > /dev/null 2>&1
then
    install_if_not php-dev
    echo "Trying to upgrade the Redis Pecl extenstion..."
    yes no | pecl upgrade redis
    service nginx restart
fi

# Update adminer
if [ -d $ADMINERDIR ]
then
    echo "Updating Adminer..."
    rm -f "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php
    wget -q "http://www.adminer.org/latest.php" -O "$ADMINERDIR"/latest.php
    ln -s "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php
fi

wp_cli_cmd cli update
cd $WPATH
wp_cli_cmd db export mysql_backup.sql
mv $WPATH/mysql_backup.sql /var/www/mysql_backup.sql
chown root:root /var/www/mysql_backup.sql
wp_cli_cmd core update --force
wp_cli_cmd plugin update --all
wp_cli_cmd core update-db
wp_cli_cmd db optimize
echo
echo "This is the current version installed:"
echo
wp_cli_cmd core version --extra

# Set secure permissions
if [ ! -f "$SECURE" ]
then
    mkdir -p "$SCRIPTS"
    download_static_script wp-permissions
    chmod +x "$SECURE"
fi

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
