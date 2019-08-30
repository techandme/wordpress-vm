#!/bin/bash

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

# Prefer IPv4
sed -i "s|#precedence ::ffff:0:0/96  100|precedence ::ffff:0:0/96  100|g" /etc/gai.conf

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
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/wordpress_install.sh\n" "$SCRIPTS"
    exit 1
fi


print_text_in_color "$ICyan" "Installing and securing Adminer..."

# Check Ubuntu version
if [ "$OS" != 1 ]
then
    print_text_in_color "$IRed" "Ubuntu Server is required to run this script."
    print_text_in_color "$IRed" "Please install that distro and try again."
    sleep 3
    exit 1
fi


if ! version 16.04 "$DISTRO" 18.04.4; then
    print_text_in_color "$IRed" "Ubuntu version seems to be $DISTRO"
    print_text_in_color "$IRed" "It must be between 16.04 - 18.04.4"
    print_text_in_color "$IRed" "Please install that version and try again."
    exit 1
fi

# Install Adminer
apt update -q4 & spinner_loading
install_if_not adminer
sudo wget -q "http://www.adminer.org/latest.php" -O "$ADMINERDIR"/latest.php
sudo ln -s "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php

cat << ADMINER_CREATE > "$ADMINER_CONF"
server {

    # Listen on port 81
    listen 81;

    # Server name being used (exact name, wildcards or regular expression)
    # server_name adminer.my;

    root /usr/share/adminer/adminer;

    # Logging
    error_log /var/log/adminer.access_log;
    access_log /var/log/adminer.error_log;


    location / {
           index   index.php;
           allow   $GATEWAY/24;
           deny    all;
       }

    location ~* ^/adminer/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
                root /usr/share/adminer/;
       }
       
    location ~ /\.ht {
           deny  all;
       }

    location ~ /(libraries|setup/frames|setup/libs) {
           deny all;
           return 404;
       }

    # Pass the PHP scripts to FastCGI server
    location ~* \\.php$ {
                #NOTE: You should have "cgi.fix_pathinfo = 0;" in php.ini
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                try_files \$uri =404;
                fastcgi_index index.php;
                include fastcgi.conf;
                include fastcgi_params;
                fastcgi_intercept_errors on;
                fastcgi_pass unix:$PHP_FPM_SOCK;
                fastcgi_buffers 16 16k;
                fastcgi_buffer_size 32k;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
       }
}
ADMINER_CREATE

# Enable config
ln -s /etc/nginx/sites-available/adminer.conf /etc/nginx/sites-enabled/adminer.conf

if ! service nginx restart
then
msg_box "Nginx could not restart...
The script will exit."
    exit 1
else
msg_box "Adminer was sucessfully installed and can be reached here:
http://$ADDRESS:81

You can download more plugins and get more information here: 
https://www.adminer.org

Your MariaDB connection information can be found in /root/.my.cnf

In case you try to access Adminer and get 'Forbidden' you need to change the IP in:
$ADMINER_CONF"
fi

exit
