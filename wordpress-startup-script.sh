#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
WPDB=1 && MYCNFPW=1 && FIRST_IFACE=1 && CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
unset FIRST_IFACE
unset CHECK_CURRENT_REPO
unset MYCNFPW
unset WPDB

# Tech and Me © - 2017, https://www.techandme.se/

## If you want debug mode, please activate it further down in the code at line ~60

is_root() {
    if [[ "$EUID" -ne 0 ]]
    then
        return 1
    else
        return 0
    fi
}

network_ok() {
    echo "Testing if network is OK..."
    service networking restart
    if wget -q -T 20 -t 2 http://github.com -O /dev/null
    then
        return 0
    else
        return 1
    fi
}

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash $SCRIPTS/wordpress-startup-script.sh\n"
    exit 1
fi

# Check network
if network_ok
then
    printf "${Green}Online!${Color_Off}\n"
else
    echo "Setting correct interface..."
    [ -z "$IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
    # Set correct interface
    {
        sed '/# The primary network interface/q' /etc/network/interfaces
        printf 'auto %s\niface %s inet dhcp\n# This is an autoconfigured IPv6 interface\niface %s inet6 auto\n' "$IFACE" "$IFACE" "$IFACE"
    } > /etc/network/interfaces.new
    mv /etc/network/interfaces.new /etc/network/interfaces
    service networking restart
    # shellcheck source=lib.sh
    CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
    unset CHECK_CURRENT_REPO
fi

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check network
if network_ok
then
    printf "${Green}Online!${Color_Off}\n"
else
    printf "\nNetwork NOT OK. You must have a working Network connection to run this script.\n"
    echo "Please report this issue here: $ISSUES"
    exit 1
fi

# Check where the best mirrors are and update
printf "\nTo make downloads as fast as possible when updating you should have mirrors that are as close to you as possible.\n"
echo "This VM comes with mirrors based on servers in that where used when the VM was released and packaged."
echo "We recomend you to change the mirrors based on where this is currently installed."
echo "Checking current mirror..."
printf "Your current server repository is:  ${Cyan}$REPO${Color_Off}\n"

if [[ "no" == $(ask_yes_or_no "Do you want to try to find a better mirror?") ]]
then
    echo "Keeping $REPO as mirror..."
    sleep 1
else
    echo "Locating the best mirrors..."
    apt update -q4 & spinner_loading
    apt install python-pip -y
    pip install \
        --upgrade pip \
        apt-select
    apt-select -m up-to-date -t 5 -c
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup && \
    if [ -f sources.list ]
    then
        sudo mv sources.list /etc/apt/
    fi
fi

echo
echo "Getting scripts from GitHub to be able to run the first setup..."
# All the shell scripts in static (.sh)
download_static_script security
download_static_script update
download_static_script ip
download_static_script test_connection
download_static_script wp-permissions
download_static_script change_mysql_pass
download_static_script techandme
download_static_script index
download_le_script activate-ssl

# Make $SCRIPTS excutable
chmod +x -R $SCRIPTS
chown root:root -R $SCRIPTS

# Allow wordpress to run figlet script
chown wordpress:wordpress $SCRIPTS/techandme.sh

clear
cat << EOMSTART
+---------------------------------------------------------------+
|   This script will do the final setup for you                 |
|                                                               |
|   - Genereate new server SSH keys				|
|   - Set static IP                                             |
|   - Create a new WP user                                      |
|   - Upgrade the system                                        |
|   - Activate SSL (Let's Encrypt)                              |
|   - Install phpMyadmin					|
|   - Change keyboard setup (current is Swedish)                |
|   - Change system timezone                                    |
|   - Set new password to the Linux system (user: wordpress)	|
|								|
|    ################# Tech and Me - 2017 #################	|
+---------------------------------------------------------------+
EOMSTART
any_key "Press any key to start the script..."
clear

# VPS?
if [[ "no" == $(ask_yes_or_no "Do you run this script on a *remote* VPS like DigitalOcean, HostGator or similar?") ]]
then
    # Change IP
    printf "\n${Color_Off}OK, we assume you run this locally and we will now configure your IP to be static.${Color_Off}\n"
    echo "Your internal IP is: $ADDRESS"
    printf "\n${Color_Off}Write this down, you will need it to set static IP\n"
    echo "in your router later. It's included in this guide:"
    echo "https://www.techandme.se/open-port-80-443/ (step 1 - 5)"
    any_key "Press any key to set static IP..."
    ifdown "$IFACE"
    wait
    ifup "$IFACE"
    wait
    bash "$SCRIPTS/ip.sh"
    if [ -z "$IFACE" ]
    then
        echo "IFACE is an emtpy value. Trying to set IFACE with another method..."
        download_static_script ip2
        bash "$SCRIPTS/ip2.sh"
        rm -f "$SCRIPTS/ip2.sh"
    fi
    ifdown "$IFACE"
    wait
    ifup "$IFACE"
    wait
    echo
    echo "Testing if network is OK..."
    echo
    CONTEST=$(bash $SCRIPTS/test_connection.sh)
    if [ "$CONTEST" == "Connected!" ]
    then
        # Connected!
        printf "${Green}Connected!${Color_Off}\n"
        printf "We will use the DHCP IP: ${Green}$ADDRESS${Color_Off}. If you want to change it later then just edit the interfaces file:\n"
        printf "sudo nano /etc/network/interfaces\n"
        echo "If you experience any bugs, please report it here:"
        echo "$ISSUES"
        any_key "Press any key to continue..."
    else
        # Not connected!
        printf "${Red}Not Connected${Color_Off}\nYou should change your settings manually in the next step.\n"
        any_key "Press any key to open /etc/network/interfaces..."
        nano /etc/network/interfaces
        service networking restart
        clear
        echo "Testing if network is OK..."
        ifdown "$IFACE"
        wait
        ifup "$IFACE"
        wait
        bash "$SCRIPTS/test_connection.sh"
        wait
    fi
else
    echo "OK, then we will not set a static IP as your VPS provider already have setup the network for you..."
    sleep 5 & spinner_loading
fi
clear

# Set keyboard layout
echo "Current keyboard layout is $(localectl status | grep "Layout" | awk '{print $3}')"
if [[ "no" == $(ask_yes_or_no "Do you want to change keyboard layout?") ]]
then
    echo "Not changing keyboard layout..."
    sleep 1
    clear
else
    dpkg-reconfigure keyboard-configuration
clear
fi

# Generate new SSH Keys
printf "\nGenerating new SSH keys for the server...\n"
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Generate new MARIADB password
echo "Generating new MARIADB password..."
if bash "$SCRIPTS/change_mysql_pass.sh" && wait
then
   rm "$SCRIPTS/change_mysql_pass.sh"
fi

whiptail --title "Which apps do you want to install?" --checklist --separate-output "Automatically configure and install selected apps\nSelect by pressing the spacebar" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Fail2ban" "(Extra Bruteforce protection)   " OFF \
"Webmin" "(Server GUI)       " OFF \
"phpMyadmin" "(*SQL GUI)       " OFF 2>results
while read -r -u 9 choice
do
    case $choice in
        Fail2ban)
            run_app_script fail2ban

        ;;

        Webmin)
            run_app_script webmin

        ;;

        phpMyadmin)
            run_app_script phpmyadmin_install_ubuntu16
        ;;

        *)
        ;;
    esac
done 9< results
rm -f results
clear

# Change Timezone
echo "Current timezone is $(cat /etc/timezone)"
echo "You must change it to your timezone"
any_key "Press any key to change timezone..."
dpkg-reconfigure tzdata
sleep 3
clear

# Add extra security
if [[ "yes" == $(ask_yes_or_no "Do you want to add extra security, based on this: http://goo.gl/gEJHi7 ?") ]]
then
    bash $SCRIPTS/security.sh
    rm "$SCRIPTS"/security.sh
else
    echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/security.sh"
    any_key "Press any key to continue..."
fi
clear

# Change password
printf "${Color_Off}\n"
echo "For better security, change the system user password for [$UNIXUSER]"
any_key "Press any key to change password for system user..."
while true
do
    sudo passwd "$UNIXUSER" && break
done
echo
clear

cat << LETSENC
+-----------------------------------------------+
|  The following script will install a trusted  |
|  SSL certificate through Let's Encrypt.       |
+-----------------------------------------------+
LETSENC
# Let's Encrypt
if [[ "yes" == $(ask_yes_or_no "Do you want to install SSL?") ]]
then
    bash $SCRIPTS/activate-ssl.sh
else
    echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/activate-ssl.sh"
    any_key "Press any key to continue..."
fi
clear

# Create new WP user
cat << ENTERNEW
+-----------------------------------------------+
|    Please create a new user for Wordpress:	|
+-----------------------------------------------+
ENTERNEW
new_wp_user() {
echo "Enter FQDN (http://yourdomain.com):"
read -r FQDN
echo
echo "Enter username:"
read -r USER
echo
echo "Enter password:"
read -r NEWWPADMINPASS
echo
echo "Enter email address:"
read -r EMAIL
}
new_wp_user

echo
if [[ "no" == $(ask_yes_or_no "Is this correct?  FQDN: $FQDN User: $USER Password: $NEWWPADMINPASS Email: $EMAIL") ]]
	then
echo
echo
cat << ENTERNEW2
+-----------------------------------------------+
|    OK, try again. (2/2) 			|
|    Please create a new user for Wordpress:	|
|    It's important that it's correct, because	|
|    the script is based on what you enter	|
+-----------------------------------------------+
ENTERNEW2
new_wp_user
fi
clear

echo "$FQDN" > fqdn.txt
wp option update siteurl < fqdn.txt --allow-root --path="$WPATH"
rm fqdn.txt

ADDRESS=$(hostname -I | cut -d ' ' -f 1)
wp search-replace "http://$ADDRESS" "$FQDN" --precise --all-tables --path="$WPATH" --allow-root

wp user create "$USER" "$EMAIL" --role=administrator --user_pass="$NEWWPADMINPASS" --path="$WPATH" --allow-root
wp user delete 1 --allow-root --reassign="$USER" --path="$WPATH"
{
echo "WP USER: $USER"
echo "WP PASS: $NEWWPADMINPASS"
} > /var/adminpass.txt


# Show current administrators
echo
echo "This is the current administrator(s):"
wp user list --role=administrator --path="$WPATH" --allow-root
any_key "Press any key to continue..."
clear

# Fixes https://github.com/techandme/wordpress-vm/issues/58
a2dismod status
service apache2 reload

# Cleanup 1
rm -f "$SCRIPTS/ip.sh"
rm -f "$SCRIPTS/test_connection.sh"
rm -f "$SCRIPTS/instruction.sh"
rm -f "$SCRIPTS/wordpress-startup-script.sh"
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete
sed -i "s|instruction.sh|techandme.sh|g" "/home/$UNIXUSER/.bash_profile"

truncate -s 0 \
    /root/.bash_history \
    "/home/$UNIXUSER/.bash_history" \
    /var/spool/mail/root \
    "/var/spool/mail/$UNIXUSER" \
    /var/log/apache2/access.log \
    /var/log/apache2/error.log \
    /var/log/cronjobs_success.log

sed -i "s|sudo -i||g" "/home/$UNIXUSER/.bash_profile"
cat << RCLOCAL > "/etc/rc.local"
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0

RCLOCAL
clear

# Upgrade system
echo "System will now upgrade..."
bash $SCRIPTS/update.sh

# Cleanup 2
apt autoremove -y
apt autoclean
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e "$(uname -r | cut -f1,2 -d"-")" | grep -e "[0-9]" | xargs sudo apt -y purge)
echo "$CLEARBOOT"

ADDRESS2=$(grep "address" /etc/network/interfaces | awk '$1 == "address" { print $2 }')
# Success!
clear
printf "%s\n""${Green}"
echo    "+--------------------------------------------------------------------+"
echo    "|      Congratulations! You have successfully installed Wordpress!   |"
echo    "|                                                                    |"
printf "|         ${Color_Off}Login to Wordpress in your browser: ${Cyan}\"$ADDRESS2\"${Green}         |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}Publish your server online! ${Cyan}https://goo.gl/iUGE2U${Green}          |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}To login to MARIADB just type: ${Cyan}'mysql -u root'${Green}             |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}To update this VM just type: ${Green}                              |\n"
printf "|         ${Cyan}'sudo bash /var/scripts/update.sh'${Green}                         |\n"
echo    "|                                                                    |"
printf "|    ${IRed}#################### Tech and Me - 2017 ####################${Green}    |\n"
echo    "+--------------------------------------------------------------------+"
printf "${Color_Off}\n"

# Prefer IPv6
sed -i "s|precedence ::ffff:0:0/96  100|#precedence ::ffff:0:0/96  100|g" /etc/gai.conf

## Reboot
echo "Installations finished. System will now reboot..."
reboot
