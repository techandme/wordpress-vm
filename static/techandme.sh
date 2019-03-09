#!/bin/bash
WANIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
ADDRESS=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
WPADMINUSER=$(grep "WP USER:" /var/adminpass.txt)
WPADMINPASS=$(grep "WP PASS:" /var/adminpass.txt)
clear
figlet -f small Wordpress
print_text_in_color "$ICyan" "  https://www.hanssonit.se/wordpress-vm/"
print_text_in_color "$ICyan"
print_text_in_color "$ICyan"
print_text_in_color "$ICyan" "|NETWORK|"
print_text_in_color "$ICyan" "WAN IP: $WANIP"
print_text_in_color "$ICyan" "LAN IP: $ADDRESS"
print_text_in_color "$ICyan"
print_text_in_color "$ICyan" "|WORDPRESS LOGIN|"
print_text_in_color "$ICyan" "$WPADMINUSER"
print_text_in_color "$ICyan" "$WPADMINPASS"
print_text_in_color "$ICyan"
print_text_in_color "$ICyan" "|MySQL|"
print_text_in_color "$ICyan" "PASS: cat /root/.my.cnf"
print_text_in_color "$ICyan"
exit 0
