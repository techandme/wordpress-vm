#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/
# Inspired by https://github.com/nextcloud/nextcloudpi/blob/master/etc/nextcloudpi-config.d/fail2ban.sh

# shellcheck disable=2034,2059
true
SCRIPT_NAME="Fail2ban"
SCRIPT_EXPLAINER="Fail2ban provides extra Brute Force protextion for Wordpress.
It scans the Wordpress and SSH log files and bans IPs that show malicious \
signs -- too many password failures, seeking for exploits, etc.
Generally Fail2Ban is then used to update firewall rules to \
reject the IP addresses for a specified amount of time."
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/20.04_testing/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Check if fail2ban is already installed
if ! is_this_installed fail2ban
then
    # Ask for installing
    install_popup "$SCRIPT_NAME"
else
    # Ask for removal or reinstallation
    reinstall_remove_menu "$SCRIPT_NAME"
    # Removal
    print_text_in_color "$ICyan" "Unbanning all currently blocked IPs..."
    fail2ban-client unban --all
    check_command update-rc.d fail2ban disable
    check_command apt-get purge fail2ban -y
    rm -Rf /etc/fail2ban/
    wp_cli_cmd plugin delete wp-fail2ban
    # Show successful uninstall if applicable
    removal_popup "$SCRIPT_NAME"
fi

### Local variables ###
# location of logs
AUTHLOG="/var/log/auth.log"
# time to ban an IP that exceeded attempts
BANTIME_=1209600
# cooldown time for incorrect passwords
FINDTIME_=1800
# failed attempts before banning an IP
MAXRETRY_=20

apt update -q4 & spinner_loading
install_if_not fail2ban
check_command update-rc.d fail2ban disable

# Install WP-Fail2ban and activate conf
wp_cli_cmd plugin install wp-fail2ban --activate
curl https://plugins.svn.wordpress.org/wp-fail2ban/trunk/filters.d/wordpress-hard.conf > /etc/fail2ban/filter.d/wordpress.conf

if [ ! -f "$AUTHLOG" ]
then
    print_text_in_color "$IRed" "$AUTHLOG not found"
    exit 1
fi

# Create jail.local file
cat << FCONF > /etc/fail2ban/jail.d/wordpress.conf
# The DEFAULT allows a global definition of the options. They can be overridden
# in each jail afterwards.
[DEFAULT]

# "ignoreip" can be an IP address, a CIDR mask or a DNS host. Fail2ban will not
# ban a host which matches an address in this list. Several addresses can be
# defined using space separator.
ignoreip = 127.0.0.1/8 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8

# "bantime" is the number of seconds that a host is banned.
bantime  = $BANTIME_

# A host is banned if it has generated "maxretry" during the last "findtime"
# seconds.
findtime = $FINDTIME_
maxretry = $MAXRETRY_

#
# ACTIONS
#
banaction = iptables-multiport
protocol = tcp
chain = INPUT
action_ = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mw = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mwl = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action = %(action_)s

#
# SSH
#

[sshd]

enabled  = true
maxretry = $MAXRETRY_

#
# HTTP servers
#

[wordpress]
enabled  = true
port     = http,https
filter   = wordpress
logpath  = $AUTHLOG
maxretry = $MAXRETRY_
findtime = $FINDTIME_
bantime  = $BANTIME_
FCONF

# Update settings
check_command update-rc.d fail2ban defaults
check_command update-rc.d fail2ban enable
check_command systemctl restart fail2ban.service

# The End
msg_box "Fail2ban is now sucessfully installed.

Please use 'fail2ban-client set nextcloud unbanip <Banned IP>' to unban certain IPs
You can also use 'iptables -L -n' to check which IPs that are banned"

exit
