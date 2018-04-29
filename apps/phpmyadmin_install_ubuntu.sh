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
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/phpmyadmin_install.sh\n" "$SCRIPTS"
    sleep 3
    exit 1
fi

# Check that the script can see the external IP (apache fails otherwise)
if [ -z "$WANIP4" ]
then
    echo "WANIP4 is an emtpy value, Apache will fail on reboot due to this. Please check your network and try again"
    sleep 3
    exit 1
fi

# Check Ubuntu version
if [ "$OS" != 1 ]
then
    echo "Ubuntu Server is required to run this script."
    echo "Please install that distro and try again."
    sleep 3
    exit 1
fi


if ! version 16.04 "$DISTRO" 16.04.4; then
    echo "Ubuntu version seems to be $DISTRO"
    echo "It must be between 16.04 - 16.04.4"
    echo "Please install that version and try again."
    exit 1
fi

echo
echo "Installing and securing phpMyadmin..."
echo "This may take a while, please don't abort."
echo

# Install phpmyadmin
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $MARIADBMYCNFPASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MARIADBMYCNFPASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $MARIADBMYCNFPASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt update -q4 & spinner_loading
apt install -y -q \
    php-gettext \
    phpmyadmin

# Secure phpMyadmin
if [ -f $PHPMYADMIN_CONF ]
then
    rm $PHPMYADMIN_CONF
fi
touch "$PHPMYADMIN_CONF"
cat << CONF_CREATE > "$PHPMYADMIN_CONF"
server {
    listen 81;
        location /phpmyadmin {
               root /usr/share/;
               index index.php index.html index.htm;
               location ~ ^/phpmyadmin/(.+\\.php)$ {
                       try_files \$uri \$uri/ /index.php?\$args;
                       root /usr/share/;
                       fastcgi_pass php;
                       fastcgi_index index.php;
                       fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                       include /etc/nginx/fastcgi_params;
               }
               location ~* ^/phpmyadmin/(.+\\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
                       root /usr/share/;
               }
        }
        location /phpMyAdmin {
               rewrite ^/* /phpmyadmin last;
        }
}
CONF_CREATE

# Secure phpMyadmin even more
CONFIG=/var/lib/phpmyadmin/config.inc.php
touch $CONFIG
cat << CONFIG_CREATE >> "$CONFIG"
<?php
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['extension'] = 'mysql';
\$cfg['Servers'][\$i]['connect_type'] = 'socket';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['UploadDir'] = '$SAVEPATH';
\$cfg['SaveDir'] = '$UPLOADPATH';
\$cfg['BZipDump'] = false;
\$cfg['Lang'] = 'en';
\$cfg['ServerDefault'] = 1;
\$cfg['ShowPhpInfo'] = true;
\$cfg['Export']['lock_tables'] = true;
?>
CONFIG_CREATE

if ! service nginx restart
then
msg_box "Ngnx could not restart, something is wrong with the configuration. 
Please report this to $ISSUES."
    exit 1
else
msg_box "$PHPMYADMIN_CONF was successfully secured.
You can reach it at: http://$ADDRESS:81"
fi
