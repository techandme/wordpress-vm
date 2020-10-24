#!/bin/bash
# shellcheck disable=2034,2059
true
SCRIPT_NAME="Test New Configuration"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/20.04_testing/lib.sh)

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Activate the new config
msg_box "We will now test that everything is OK"
ln -s "$SITES_AVAILABLE"/"$1" "$SITES_ENABLED"/"$1"
rm -f "$SITES_AVAILABLE"/"$HTTP_CONF"
rm -f "$SITES_AVAILABLE"/"$TLS_CONF"
rm -f "$NGINX_DEF"
rm -f "$SITES_ENABLED"/default
if restart_webserver
then
    msg_box "New settings works! TLS is now activated and OK!

This cert will expire in 90 days if you don't renew it.
There are several ways of renewing this cert and here are some tips and tricks:
https://goo.gl/c1JHR0

To do your job a little bit easier we have added a autorenew script as a cronjob.
If you need to edit the crontab please type: crontab -u root -e
If you need to edit the script itself, please check: $SCRIPTS/letsencryptrenew.sh

Feel free to contribute to this project: https://goo.gl/3fQD65"
    crontab -u root -l | { cat; echo "3 */12 * * * $SCRIPTS/letsencryptrenew.sh"; } | crontab -u root -

FQDOMAIN=$(grep -m 1 "server_name" "$SITES_ENABLED"/"$1" | awk '{print $2}')
if [ "$(hostname)" != "$FQDOMAIN" ]
then
    print_text_in_color "$ICyan" "Setting hostname to $FQDOMAIN..."
    sudo hostnamectl set-hostname "$FQDOMAIN"
    # Change /etc/hosts as well
    sed -i "s|127.0.1.1.*|127.0.1.1       $FQDOMAIN $(hostname -s)|g" /etc/hosts
    # And in the php-fpm pool conf
    sed -i "s|env\[HOSTNAME\] = .*|env[HOSTNAME] = $(hostname -f)|g" "$PHP_POOL_DIR"/wordpress.conf
fi

add_crontab_le() {
# shellcheck disable=SC2016
DATE='$(date +%Y-%m-%d_%H:%M)'
cat << CRONTAB > "$SCRIPTS/letsencryptrenew.sh"
#!/bin/sh
if ! certbot renew --quiet --no-self-upgrade > /var/log/letsencrypt/renew.log 2>&1 ; then
        echo "Let's Encrypt FAILED!"--$DATE >> /var/log/letsencrypt/cronjob.log
else
        echo "Let's Encrypt SUCCESS!"--$DATE >> /var/log/letsencrypt/cronjob.log
fi

# Check if service is running
if ! pgrep nginx > /dev/null
then
    start_if_stopped nginx.service
fi
CRONTAB
}
add_crontab_le

# Makeletsencryptrenew.sh executable
chmod +x $SCRIPTS/letsencryptrenew.sh

# Cleanup
rm -f $SCRIPTS/test-new-config.sh
rm -f $SCRIPTS/activate-tls.sh

else



# If it fails, revert changes back to normal
    rm -f "$SITES_ENABLED"/"$1"
    ln -s "$$SITES_AVAILABLE/$HTTP_CONF" "$SITES_ENABLED"
    restart_webserver
    msg_box "Couldn't load new config, reverted to old settings. Self-signed TLS is OK!"
    exit 1
fi
