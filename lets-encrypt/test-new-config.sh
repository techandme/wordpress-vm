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

# Activate the new config
printf "${Color_Off}We will now test that everything is OK\n"
any_key "Press any key to continue... "
ln -s /etc/nginx/sites-available/"$1" /etc/nginx/sites-enabled/"$1"
rm -f /etc/nginx/sites-enabled/wordpress_port_80.conf
rm -f /etc/nginx/sites-enabled/wordpress_port_443.conf
rm -f /etc/nginx/sites-enabled/default.conf
rm -f /etc/nginx/sites-enabled/default
if service nginx restart
then
    printf "${On_Green}New settings works! SSL is now activated and OK!${Color_Off}\n\n"
    print_text_in_color "$ICyan" "This cert will expire in 90 days, so you have to renew it."
    print_text_in_color "$ICyan" "There are several ways of doing so, here are some tips and tricks: https://goo.gl/c1JHR0"
    print_text_in_color "$ICyan" "This script will add a renew cronjob to get you started, edit it by typing:"
    print_text_in_color "$ICyan" "'crontab -u root -e'"
    print_text_in_color "$ICyan" "Feel free to contribute to this project: https://goo.gl/3fQD65"
    any_key "Press any key to continue..."
    crontab -u root -l | { cat; echo "@daily $SCRIPTS/letsencryptrenew.sh"; } | crontab -u root -

FQDOMAIN=$(grep -m 1 "server_name" "/etc/nginx/sites-enabled/$1" | awk '{print $2}')
if [ "$(hostname)" != "$FQDOMAIN" ]
then
    print_text_in_color "$ICyan" "Setting hostname to $FQDOMAIN..."
    sudo hostnamectl set-hostname "$FQDOMAIN"
    # Change /etc/hosts as well
    sed -i "s|127.0.1.1.*|127.0.1.1       $FQDOMAIN $(hostname -s)|g" /etc/hosts
fi

add_crontab_le() {
# shellcheck disable=SC2016
DATE='$(date +%Y-%m-%d_%H:%M)'
cat << CRONTAB > "$SCRIPTS/letsencryptrenew.sh"
#!/bin/sh
if ! certbot renew --quiet --no-self-upgrade > /var/log/letsencrypt/renew.log 2>&1 ; then
        print_text_in_color "$ICyan" "Let's Encrypt FAILED!"--$DATE >> /var/log/letsencrypt/cronjob.log
else
        print_text_in_color "$ICyan" "Let's Encrypt SUCCESS!"--$DATE >> /var/log/letsencrypt/cronjob.log
fi

# Check if service is running
if ! pgrep nginx > /dev/null
then
    service nginx start
fi
CRONTAB
}
add_crontab_le

# Makeletsencryptrenew.sh executable
chmod +x $SCRIPTS/letsencryptrenew.sh

# Cleanup
rm $SCRIPTS/test-new-config.sh ## Remove ??
rm $SCRIPTS/activate-ssl.sh ## Remove ??

else
# If it fails, revert changes back to normal
    rm -f /etc/nginx/sites-enabled/"$1"
    ln -s /etc/nginx/sites-available/wordpress_port_80.conf /etc/nginx/sites-enabled/ 
    service nginx restart
    printf "${ICyan}Couldn't load new config, reverted to old settings. Self-signed SSL is OK!${Color_Off}\n"
    any_key "Press any key to continue... "
    exit 1
fi
