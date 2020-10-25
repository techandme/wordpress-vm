#!/bin/bash
# shellcheck disable=2034,2059
true
SCRIPT_NAME="Redis Server Ubuntu"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Check Ubuntu version
if ! version 16.04 "$DISTRO" 20.04.6
then
    msg_box "Your current Ubuntu version is $DISTRO but must be between 16.04 - 20.04.6 to run this script."
    msg_box "Please contact us to get support for upgrading your server:
https://www.hanssonit.se/#contact
https://shop.hanssonit.se/"
    exit 1
fi

# Check if dir exists
if [ ! -d $SCRIPTS ]
then
    mkdir -p $SCRIPTS
fi

# Check the current PHPVER
check_php

# Install Redis
install_if_not php"$PHPVER"-dev
pecl channel-update pecl.php.net
if ! yes no | pecl install -Z redis
then
    msg_box "PHP module installation failed"
exit 1
else
    printf "${IGreen}\nPHP module installation OK!${Color_Off}\n"
fi
install_if_not redis-server

# Setting direct to PHP-FPM as it's installed with PECL (globally doesn't work)
print_text_in_color "$ICyan" "Adding extension=redis.so to $PHP_INI..."
# FPM is needed for frontend
echo 'extension=redis.so' >> /etc/php/"$PHPVER"/fpm/php.ini
# CLI is needed for backend
echo 'extension=redis.so' >> /etc/php/"$PHPVER"/cli/php.ini
restart_webserver

## Redis performance tweaks ##
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi

# Disable THP
if ! grep -Fxq "never" /sys/kernel/mm/transparent_hugepage/enabled
then
    echo "never" > /sys/kernel/mm/transparent_hugepage/enabled
fi

# Raise TCP backlog
#if ! grep -Fxq "net.core.somaxconn" /proc/sys/net/core/somaxconn
#then
#    sed -i "s|net.core.somaxconn.*||g" /etc/sysctl.conf
#    sysctl -w net.core.somaxconn=512
#    echo "net.core.somaxconn = 512" >> /etc/sysctl.conf
#fi
sed -i "s|# unixsocket .*|unixsocket $REDIS_SOCK|g" $REDIS_CONF
sed -i "s|# unixsocketperm .*|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|^port.*|port 0|" $REDIS_CONF
sed -i "s|# requirepass .*|requirepass $(cat $REDISPTXT)|g" $REDIS_CONF
sed -i 's|# rename-command CONFIG ""|rename-command CONFIG ""|' $REDIS_CONF
redis-cli SHUTDOWN

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

apt update -q4 & spinner_loading
apt autoremove -y
apt autoclean
rm -f "$REDISPTXT"

exit
