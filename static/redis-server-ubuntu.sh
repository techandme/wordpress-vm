#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Check Ubuntu version
print_text_in_color "$ICyan" "Checking server OS and version..."
if [ "$OS" != 1 ]
then
    print_text_in_color "$IRed" "Ubuntu Server is required to run this script."
    print_text_in_color "$IRed" "Please install that distro and try again."
    exit 1
fi


if ! version 18.04 "$DISTRO" 18.04.4; then
    print_text_in_color "$IRed" "Ubuntu version $DISTRO must be between 18.04 - 18.04.4"
    exit
fi

# Check if dir exists
if [ ! -d $SCRIPTS ]
then
    mkdir -p $SCRIPTS
fi
    
# Install Redis
install_if_not php"$PHPVER"-dev
pecl channel-update pecl.php.net
if ! yes no | pecl install -Z redis
then
    msg_box "PHP module installation failed"
exit 1
else
    print_text_in_color "$IGreen" "PHP module installation OK!"
fi
install_if_not redis-server

# Set globally doesn't work for some reason
# touch /etc/php/7.0/mods-available/redis.ini
# print_text_in_color "$ICyan" 'extension=redis.so' > /etc/php/7.0/mods-available/redis.ini
# phpenmod redis
# Setting direct to apache2 works if 'libapache2-mod-php7.0' is installed
echo 'extension=redis.so' >> /etc/php/"$PHPVER"/fpm/php.ini
service nginx restart

# Install Redis
if ! apt -y install redis-server
then
    print_text_in_color "$IRed" "Installation failed."
    sleep 3
    exit 1
else
    print_text_in_color "$IGreen" "Redis installation OK!"
fi

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

sed -i "s|# unixsocket .*|unixsocket $REDIS_SOCK|g" $REDIS_CONF
sed -i "s|# unixsocketperm .*|unixsocketperm 777|g" $REDIS_CONF
sed -i "s|^port.*|port 0|" $REDIS_CONF
sed -i "s|# requirepass .*|requirepass $(cat $REDISPTXT)|g" $REDIS_CONF
sed -i 's|# rename-command CONFIG ""|rename-command CONFIG ""|' $REDIS_CONF
redis-cli SHUTDOWN
rm -f $REDISPTXT

# Secure Redis
chown redis:root /etc/redis/redis.conf
chmod 600 /etc/redis/redis.conf

apt update -q4 & spinner_loading
apt autoremove -y
apt autoclean

exit
