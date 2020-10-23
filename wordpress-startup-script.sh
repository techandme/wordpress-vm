#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

#########

IRed='\e[0;91m'         # Red
IGreen='\e[0;92m'       # Green
ICyan='\e[0;96m'        # Cyan
Color_Off='\e[0m'       # Text Reset
print_text_in_color() {
	printf "%b%s%b\n" "$1" "$2" "$Color_Off"
}

print_text_in_color "$ICyan" "Fetching all the variables from lib.sh..."

is_process_running() {
PROCESS="$1"

while :
do
    RESULT=$(pgrep "${PROCESS}")

    if [ "${RESULT:-null}" = null ]; then
            break
    else
            print_text_in_color "$ICyan" "${PROCESS} is running, waiting for it to stop..."
            sleep 10
    fi
done
}

#########

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# shellcheck disable=2034,2059,1091
true
SCRIPT_NAME="Nextcloud Startup Script"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# Check if root
root_check

# Check network
if network_ok
then
    print_text_in_color "$IGreen" "Online!"
else
    print_text_in_color "$ICyan" "Setting correct interface..."
    [ -z "$IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
    # Set correct interface
    cat <<-SETDHCP > "/etc/netplan/01-netcfg.yaml"
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: true
      dhcp6: true
SETDHCP
    check_command netplan apply
    print_text_in_color "$ICyan" "Checking connection..."
    sleep 1
    set_systemd_resolved_dns "$IFACE"
    if ! nslookup github.com
    then
        msg_box "The script failed to get an address from DHCP.
You must have a working network connection to run this script.

You will now be provided with the option to set a static IP manually instead."

        # Run static_ip script
	bash /var/scripts/static_ip.sh
    fi
fi

# Check network again
if network_ok
then
    print_text_in_color "$IGreen" "Online!"
else
    msg_box "Network NOT OK. You must have a working network connection to run this script.

Please contact us for support:
https://shop.hanssonit.se/product/premium-support-per-30-minutes/

Please also post this issue on: https://github.com/techandme/wordpress-vm/issues"
    exit 1
fi

# shellcheck disable=2034,2059,1091
true
SCRIPT_NAME="Wordpress startup script"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh 

# Get all needed variables from the library
mycnfpw
wpdb

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Run the startup menu
run_script MENU startup_configuration

######## The first setup is OK to run to this point several times, but not any further ########
if [ -f "$SCRIPTS/you-can-not-run-the-startup-script-several-times" ]
then
    msg_box "The $SCRIPT_NAME that handles the first setup \
(this one) is desinged to be run once, not several times in a row.

If you feel uncertain about adding some extra features during this setup, \
then it's best to wait until after the first setup is done. You can always add all the extra features later.

[For the Wordpress VM:]
Please delete this VM from your host and reimport it once again, then run this setup like you did the first time.

Full documentation can be found here: https://docs.hanssonit.se
Please report any bugs you find here: $ISSUES"
    exit 1
fi

touch "$SCRIPTS/you-can-not-run-the-startup-script-several-times"

print_text_in_color "$ICyan" "Getting scripts from GitHub to be able to run the first setup..."
# Scripts in static (.sh, .php, .py)
download_script LETS_ENC activate-tls
download_script STATIC update
download_script STATIC wp-permissions
download_script STATIC change_db_pass
download_script STATIC wordpress
download_script MENU menu
download_script MENU server_configuration
download_script MENU nextcloud_configuration
download_script MENU additional_apps

# Make $SCRIPTS excutable
chmod +x -R $SCRIPTS
chown root:root -R $SCRIPTS

# Allow wordpress to run figlet script
chown "$SUDO_USER":"$SUDO_USER" $SCRIPTS/wordpress.sh

clear
msg_box"This script will do the final setup for you

- Genereate new server SSH keys
- Set static IP
- Create a new WP user
- Upgrade the system
- Activate SSL (Let's Encrypt)
- Install Adminer
- Change keyboard setup (current is Swedish)
- Change system timezone
- Set new password to the Linux system (user: wordpress)

############### T&M Hansson IT AB -  $(date +"%Y") ###############"
clear

msg_box "PLEASE NOTE:
[#] Please finish the whole setup. The server will reboot once done.
[#] Please read the on-screen instructions carefully, they will guide you through the setup.
[#] When complete it will delete all the *.sh, *.html, *.tar, *.zip inside:
    /root
    /home/$SUDO_USER
[#] Please consider donating if you like the product:
    https://shop.hanssonit.se/product-category/donate/
[#] You can also ask for help here:
    https://shop.hanssonit.se/product/premium-support-per-30-minutes/"

msg_box "PLEASE NOTE:
The first setup is meant to be run once, and not aborted.
If you feel uncertain about the options during the setup, just choose the defaults by hitting [ENTER] at each question.
When the setup is done, the server will automatically reboot.
Please report any issues to: $ISSUES"

# Change timezone in PHP
sed -i "s|;date.timezone.*|date.timezone = $(cat /etc/timezone)|g" "$PHP_INI"

# Generate new SSH Keys
printf "\nGenerating new SSH keys for the server...\n"
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Generate new MariaDB password
print_text_in_color "$ICyan" "Generating new PostgreSQL password..."
check_command bash "$SCRIPTS/change_db_pass.sh"
sleep 3

# Server configurations
bash $SCRIPTS/server_configuration.sh

# Nextcloud configuration
bash $SCRIPTS/wordpress_configuration.sh

# Install apps
bash $SCRIPTS/additional_apps.sh


### Change passwords
# CLI USER
msg_box "For better security, we will now change the password for the CLI user in Ubuntu."
UNIXUSER="$(getent group sudo | cut -d: -f4 | cut -d, -f1)"
while :
do
    UNIX_PASSWORD=$(input_box_flow "Please type in the new password for the current CLI user in Ubuntu: $UNIXUSER.")
    if [[ "$UNIX_PASSWORD" == *" "* ]]
    then
        msg_box "Please don't use spaces."
    else
        break
    fi
done
if check_command echo "$UNIXUSER:$UNIX_PASSWORD" | sudo chpasswd
then
    msg_box "The new password for the current CLI user in Ubuntu ($UNIXUSER) is now set to: $UNIX_PASSWORD
    
This is used when you login to the Ubuntu CLI."
fi
unset UNIX_PASSWORD

# WORDPRESS USER
while :
do
msg_box "Please define the FQDN and create a new user for Wordpress.

Make sure your FQDN starts with either http:// or https://,
otherwise your installation will not work correctly!"

FQDN=$(input_box_flow "Please enter your domain name or IP address, e.g: https://www.example.com or http://192.168.1.100.")
USER=$(input_box_flow "Please enter your Wordpress username.")
NEWWPADMINPASS=$(input_box_flow "Please enter your Wordpress password.")
EMAIL=$(input_box_flow "Please enter your Wordpress admin email address.")

if yesno_box_yes "Is this correct?

Domain or IP address: $FQDN
Wordpress user: $USER
Wordpress password: $NEWWPADMINPASS
Wordpress admin email: $EMAIL"
then
    break
fi
done

echo "$FQDN" > fqdn.txt
wp_cli_cmd option update siteurl < fqdn.txt --path="$WPATH"
rm fqdn.txt

OLDHOME=$(wp_cli_cmd option get home --path="$WPATH")
wp_cli_cmd search-replace "$OLDHOME" "$FQDN" --precise --all-tables --path="$WPATH"

wp_cli_cmd user create "$USER" "$EMAIL" --role=administrator --user_pass="$NEWWPADMINPASS" --path="$WPATH"
wp_cli_cmd user delete 1 --reassign="$USER" --path="$WPATH"
{
echo "WP USER: $USER"
echo "WP PASS: $NEWWPADMINPASS"
} > /var/adminpass.txt

# Change servername in Nginx
server_name=$(echo "$FQDN" | cut -d "/" -f3)
sed -i "s|# server_name .*|server_name $server_name;|g" "$HTTP_CONF"
sed -i "s|# server_name .*|server_name $server_name;|g" "$TLS_CONF"
restart_webserver

# Show current administrators
echo
print_text_in_color "$ICyan" "This is the current administrator(s):"
wp_cli_cmd user list --role=administrator --path="$WPATH"
any_key "Press any key to continue..."
clear

# Cleanup 1
rm -f "$SCRIPTS/change_db_pass.sh"
rm -f "$SCRIPTS/instruction.sh"
rm -f "$SCRIPTS/static_ip.sh"
rm -f "$SCRIPTS/lib.sh"
rm -f "$SCRIPTS/server_configuration.sh"
rm -f "$SCRIPTS/wordpress_configuration.sh"
rm -f "$SCRIPTS/additional_apps.sh"
rm -f "$SCRIPTS/adduser.sh"
find /root "/home/$SUDO_USER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name 'results' -o -name '*.zip*' \) -delete
find "WPATH" -type f \( -name 'results' -o -name '*.sh*' \) -delete
sed -i "s|instruction.sh|wordpress.sh|g" "/home/$SUDO_USER/.bash_profile"

truncate -s 0 \
    /root/.bash_history \
    "/home/$UNIXUSER/.bash_history" \
    /var/spool/mail/root \
    "/var/spool/mail/$UNIXUSER" \
    /var/log/nginx/access.log \
    /var/log/nginx/error.log \
    /var/log/cronjobs_success.log

sed -i "s|sudo -i||g" "$UNIXUSER_PROFILE"

cat << ROOTNEWPROFILE > "$ROOT_PROFILE"
# ~/.profile: executed by Bourne-compatible login shells.
if [ "/bin/bash" ]
then
    if [ -f ~/.bashrc ]
    then
        . ~/.bashrc
    fi
fi
if [ -x /var/scripts/wordpress-startup-script.sh ]
then
    /var/scripts/wordpress-startup-script.sh
fi
if [ -x /var/scripts/history.sh ]
then
    /var/scripts/history.sh
fi
mesg n
ROOTNEWPROFILE

# Upgrade system
print_text_in_color "$ICyan" "System will now upgrade..."
bash $SCRIPTS/update.sh

# Cleanup 2
apt autoremove -y
apt autoclean

# Remove preference for IPv4
rm -f /etc/apt/apt.conf.d/99force-ipv4 
apt update

# Success!
msg_box "The installation process is *almost* done.
Please hit OK in all the following prompts and let the server reboot to complete the installation process."

msg_box "TIPS & TRICKS:
1. Publish your server online: https://goo.gl/iUGE2U
3. To update this server just type: sudo bash /var/scripts/update.sh
4. Install apps, configure Wordpress, and server: sudo bash $SCRIPTS/menu.sh"
5. To allow access to wp-login.php, please edit your nginx virtual hosts file.
   You can find it here: $HTTP_CONF"

BUGS & SUPPORT:
- SUPPORT: https://shop.hanssonit.se/product/premium-support-per-30-minutes/
- BUGS: Please report any bugs here: $ISSUES"

msg_box "Congratulations! You have successfully installed Wordpress!
LOGIN:
Login to Wordpress in your browser:
- IP: $ADDRESS
- Hostname: $(hostname -f)
### PLEASE HIT OK TO REBOOT ###"

# Reboot
print_text_in_color "$IGreen" "Installation done, system will now reboot..."
check_command rm -f "$SCRIPTS/you-can-not-run-the-startup-script-several-times"
check_command rm -f "$SCRIPTS/wordpress-startup-script.sh"
reboot
