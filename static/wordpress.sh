#!/bin/bash

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

WANIP6=$(curl -s -k -m 5 https://ipv6bot.whatismyipaddress.com)
WANIP4=$(curl -s -k -m 5 https://ipv4bot.whatismyipaddress.com)
ADDRESS=$(hostname -I | cut -d ' ' -f 1)
WPADMINUSER=$(grep "WP USER:" /var/adminpass.txt)

clear
figlet -f small Wordpress
echo "https://www.hanssonit.se/wordpress-vm/"
echo
echo "Network:"
echo "Hostname: $(hostname -s)"
echo "WAN IPv4: $WANIP4"
echo "WAN IPv6: $WANIP6"
echo "LAN IPv4: $ADDRESS"
echo
echo "Wordpress Login:"
echo "$WPADMINUSER"
echo "Type this in your CLI to get the password:"
echo "grep 'WP PASS:' /var/adminpass.txt"
echo
echo "MySQL/MariaDB:"
echo "Login happens with the OS root account."
echo "Simply type 'mysql -u root' from your CLI"
echo
