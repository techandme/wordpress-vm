#!/bin/bash

# Tech and Me © - 2017, https://www.techandme.se/

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
    regressionpw=$(cat /var/mysql_password.txt)
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

# System Upgrade
apt update -q2
apt dist-upgrade -y
# Update Redis PHP extention
if type pecl > /dev/null 2>&1
then
    if [ "$(dpkg-query -W -f='${Status}' php7.0-dev 2>/dev/null | grep -c "ok installed")" == "0" ]
    then
        echo "Preparing to upgrade Redis Pecl extenstion..."
        apt install php7.0-dev -y
    fi
    echo "Trying to upgrade the Redis Pecl extenstion..."
    pecl upgrade redis
    service apache2 restart
fi
wp cli update --allow-root
cd $WPATH
wp db export mysql_backup.sql --allow-root
mv $WPATH/mysql_backup.sql /var/www/html/mysql_backup.sql
chown root:root /var/www/html/mysql_backup.sql
wp core update --force --allow-root
wp plugin update --all --allow-root
wp core update-db --allow-root
wp db optimize --allow-root
echo
echo "This is the current version installed:"
echo
wp core version --extra --allow-root

# Set secure permissions
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
