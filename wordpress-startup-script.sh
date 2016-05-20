#!/bin/bash

# Tech and Me - ©2016, https://www.techandme.se/

WWW_ROOT=/var/www/html
WPATH=$WWW_ROOT/wordpress
SCRIPTS=/var/scripts
PW_FILE=/var/mysql_password.txt # Keep in sync with wordpress_install.sh
IP="/sbin/ip"
IFACE=$($IP -o link show | awk '{print $2,$9}' | grep "UP" | cut -d ":" -f 1)
ADDRESS=$(hostname -I | cut -d ' ' -f 1)
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e `uname -r | cut -f1,2 -d"-"` | grep -e [0-9] | xargs sudo apt-get -y purge)
WANIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
PHPMYADMIN_CONF="/etc/apache2/conf-available/phpmyadmin.conf"
STATIC="https://raw.githubusercontent.com/enoch85/wordpress-vm/master/static"
LETS_ENC="https://raw.githubusercontent.com/enoch85/ownCloud-VM/master/lets-encrypt"
IFCONFIG="/sbin/ifconfig"
INTERFACES="/etc/network/interfaces"
ADDRESS=$(hostname -I | cut -d ' ' -f 1)
NETMASK=$($IFCONFIG | grep -w inet |grep -v 127.0.0.1| awk '{print $4}' | cut -d ":" -f 2)
GATEWAY=$(route -n|grep "UG"|grep -v "UGH"|cut -f 10 -d " ")

# Check if root
	if [ "$(whoami)" != "root" ]; then
        	echo
        	echo -e "\e[31mSorry, you are not root.\n\e[0mYou must type: \e[36msudo \e[0mbash $SCRIPTS/wordpress-startup-script.sh"
        	echo
        	exit 1
	fi

# Check network
echo "Testing if network is OK..."
sleep 2
sudo ifdown $IFACE && sudo ifup $IFACE
wget -q --spider http://github.com
	if [ $? -eq 0 ]; then
    		echo -e "\e[32mOnline!\e[0m"
	else
		echo
		echo "Network NOT OK. You must have a working Network connection to run this script."
		echo "You could try to change network settings of this VM to 'Bridged Mode'".
		echo "If that doesn't help, please try to un-check 'Replicate physical host' in"
		echo "the network settings of the VM."
		echo 
		echo "Trying one more time..."
		echo
					# Check if whiptail is installed, else install it
					if [ $(dpkg-query -W -f='${Status}' whiptail 2>/dev/null | grep -c "ok installed") -eq 1 ];
					then
        				echo "whiptail is already installed!"
					else
					apt-get update
					apt-get install whiptail -y
					fi
					# Make sure its not a dns error
					cat /dev/null > /etc/resolvconf/resolv.conf.d/base
					echo "nameserver 8.26.56.26" >> /etc/resolvconf/resolv.conf.d/base
					echo "nameserver 8.20.247.20" >> /etc/resolvconf/resolv.conf.d/base
					resolvconf -u
					# Variable's for users input when unable to get a network connection
					IFCONFIGA=$(ifconfig -a)
					INPUTUSR=$(whiptail --title "Navigate with TAB to hit ok to enter input" --inputbox "What was the interface name?" 10 60)
					whiptail --title "Navigate with TAB to hit ok" --msgbox "Next we will show you the interface you need to connect to, something like eth0, enp2s0... please write it down or copy it. Hit ok to continue..." 10 60)
					INPUTUSR=$(whiptail --title "Navigate with TAB to hit ok to continue" --msgbox "$IFCONFIGA" 10 60)
					# Send user input to interfaces file
					cat <<-IPCONFIG > "$INTERFACES"
        				auto lo $INPUTUSR
        				iface lo inet loopback
        				iface $INPUTUSR inet dhcp
					pre-up /sbin/ethtool -K $IFACE tso off
					pre-up /sbin/ethtool -K $IFACE gso off
					IPCONFIG
					ifdown -a
					echo
					ifup -a
					echo
					# Test connection for the last time
					wget -q --spider http://github.com
					if [ $? -eq 0 ]; then
    					echo
    					echo "Success, moving on!"
					else
					echo
					echo "No luck this time either, please try a reboot: sudo reboot"
					exit 1
					fi
	fi

echo "Getting scripts from GitHub to be able to run the first setup..."

# Change MySQL password
        if [ -f $SCRIPTS/change_mysql_pass.sh ];
                then
                rm $SCRIPTS/change_mysql_pass.sh
                wget -q $STATIC/change_mysql_pass.sh
                else
        	wget -q $STATIC/change_mysql_pass.sh -P $SCRIPTS
	fi

# phpMyadmin
        if [ -f $SCRIPTS/phpmyadmin_install_ubuntu16.sh ];
                then
                rm $SCRIPTS/phpmyadmin_install_ubuntu16.sh
                wget -q $STATIC/phpmyadmin_install_ubuntu16.sh -P $SCRIPTS
                else
        	wget -q $STATIC/phpmyadmin_install_ubuntu16.sh -P $SCRIPTS
	fi
# Activate SSL
        if [ -f $SCRIPTS/activate-ssl.sh ];
                then
                rm $SCRIPTS/activate-ssl.sh
                wget -q $LETS_ENC/activate-ssl.sh -P $SCRIPTS
                else
        	wget -q $LETS_ENC/activate-ssl.sh -P $SCRIPTS
	fi
# The update script
        if [ -f $SCRIPTS/wordpress_update.sh ];
                then
                rm $SCRIPTS/wordpress_update.sh
                wget -q $STATIC/wordpress_update.sh -P $SCRIPTS
                else
        	wget -q $STATIC/wordpress_update.sh -P $SCRIPTS
	fi
# Sets static IP to UNIX
        if [ -f $SCRIPTS/ip.sh ];
                then
                rm $SCRIPTS/ip.sh
                wget -q $STATIC/ip.sh -P $SCRIPTS
                else
      		wget -q $STATIC/ip.sh -P $SCRIPTS
	fi
# Tests connection after static IP is set
        if [ -f $SCRIPTS/test_connection.sh ];
                then
                rm $SCRIPTS/test_connection.sh
                wget -q $STATIC/test_connection.sh -P $SCRIPTS
                else
        	wget -q $STATIC/test_connection.sh -P $SCRIPTS
	fi
# Sets secure permissions after upgrade
        if [ -f $SCRIPTS/wp-permissions.sh ];
                then
                rm $SCRIPTS/wp-permissions.sh
                wget -q $STATIC/wp-permissions.sh
                else
        	wget -q $STATIC/wp-permissions.sh -P $SCRIPTS
	fi
# Get figlet Tech and Me
	if [ -f $SCRIPTS/techandme.sh ];
                then
                rm $SCRIPTS/techandme.sh
                wget -q $STATIC/techandme.sh
                else
        	wget -q $STATIC/techandme.sh -P $SCRIPTS
	fi

# Get the Welcome Screen when http://$address
        if [ -f $SCRIPTS/index.php ];
                then
                rm $SCRIPTS/index.php
                wget -q $STATIC/index.php -P $SCRIPTS
                else
        	wget -q $STATIC/index.php -P $SCRIPTS
	fi
mv $SCRIPTS/index.php $WWW_ROOT/index.php && rm -f $WWW_ROOT/index.html
chmod 750 $WWW_ROOT/index.php && chown www-data:www-data $WWW_ROOT/index.php

# Change 000-default to $WEB_ROOT
sed -i "s|DocumentRoot /var/www/html|DocumentRoot $WWW_ROOT|g" /etc/apache2/sites-available/000-default.conf

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
|    ################# Tech and Me - 2016 #################	|
+---------------------------------------------------------------+
EOMSTART
echo -e "\e[32m"
read -p "Press any key to start the script..." -n1 -s
echo -e "\e[0m"

# Get new server keys
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Generate new MySQL password
echo
bash $SCRIPTS/change_mysql_pass.sh
rm $SCRIPTS/change_mysql_pass.sh

# Install phpMyadmin
bash $SCRIPTS/phpmyadmin_install_ubuntu16.sh
rm $SCRIPTS/phpmyadmin_install_ubuntu16.sh

# Set keyboard layout
echo "Current keyboard layout is Swedish"
echo "You must change keyboard layout to your language"
echo -e "\e[32m"
read -p "Press any key to change keyboard layout... " -n1 -s
echo -e "\e[0m"
dpkg-reconfigure keyboard-configuration
echo
clear

# Change Timezone
echo "Current Timezone is Swedish"
echo "You must change timezone to your timezone"
echo -e "\e[32m"
read -p "Press any key to change timezone... " -n1 -s
echo -e "\e[0m"
dpkg-reconfigure tzdata
echo
sleep 3
clear

# Change IP
echo -e "\e[0m"
echo "The script will now configure your IP to be static."
echo -e "\e[36m"
echo -e "\e[1m"
echo "Your internal IP is: $ADDRESS"
echo -e "\e[0m"
echo -e "Write this down, you will need it to set static IP"
echo -e "in your router later. It's included in this guide:"
echo -e "https://www.techandme.se/open-port-80-443/ (step 1 - 5)"
echo -e "\e[32m"
read -p "Press any key to set static IP..." -n1 -s
clear
echo -e "\e[0m"
ifdown $IFACE
sleep 2
ifup $IFACE
sleep 2
bash $SCRIPTS/ip.sh
ifdown $IFACE
sleep 2
ifup $IFACE
sleep 2
echo
echo "Testing if network is OK..."
echo
bash $SCRIPTS/test_connection.sh
sleep 2
echo
echo -e "\e[0mIf the output is \e[32mConnected! \o/\e[0m everything is working."
echo -e "\e[0mIf the output is \e[31mNot Connected!\e[0m you should change\nyour settings manually in the next step."
echo -e "\e[32m"
read -p "Press any key to open /etc/network/interfaces..." -n1 -s
echo -e "\e[0m"
nano /etc/network/interfaces
clear
echo "Testing if network is OK..."
ifdown $IFACE
sleep 2
ifup $IFACE
sleep 2
echo
bash $SCRIPTS/test_connection.sh

# Update WP SiteURL
grep "address" /etc/network/interfaces > ip.txt
sed -i "s|                address ||g" ip.txt
NEWADDRESS=$(grep "." ip.txt)
echo "http://$NEWADDRESS/wordpress" > ip.txt
wp option update siteurl < ip.txt --allow-root --path=$WPATH
rm ip.txt
sleep 2
clear

# Change password
echo -e "\e[0m"
echo "For better security, change the Linux password for user [wordpress]"
echo "The current password is [wordpress]"
echo -e "\e[32m"
read -p "Press any key to change password for Linux... " -n1 -s
echo -e "\e[0m"
sudo passwd wordpress
if [[ $? > 0 ]]
then
    sudo passwd wordpress
else
    sleep 2
fi
clear

# Create new WP user
cat << ENTERNEW
+-----------------------------------------------+
|    Please create a new user for Wordpress:	|
+-----------------------------------------------+
ENTERNEW

echo
echo "Enter username:"
read USER
echo
echo "Enter password:"
read NEWWPADMINPASS
echo
echo "Enter email address:"
read EMAIL

	function ask_yes_or_no() {
    	read -p "$1 ([y]es or [N]o): "
    	case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    	esac
}
echo
if [[ "no" == $(ask_yes_or_no "Is this correct? User: $USER Password: $NEWWPADMINPASS Email: $EMAIL") ]]
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
echo
echo "Enter username:"
read USER
echo
echo "Enter password:"
read NEWWPADMINPASS
echo
echo "Enter email address:"
read EMAIL
fi
wp user create $USER $EMAIL --role=administrator --user_pass=$NEWWPADMINPASS --path=$WPATH --allow-root
wp user delete 1 --allow-root --reassign=$USER --path=$WPATH
echo "WP USER: $USER" > /var/adminpass.txt
echo "WP PASS: $NEWWPADMINPASS" >> /var/adminpass.txt

# Show current administrators
echo
echo "This is the current administrator(s):"
wp user list --role=administrator --path=$WPATH --allow-root
    echo -e "\e[32m"
    read -p "Press any key to continue... " -n1 -s
    echo -e "\e[0m"
clear

# Upgrade system
clear
echo System will now upgrade...
sleep 2
echo
echo
bash $SCRIPTS/wordpress_update.sh

# Cleanup 1
apt-get autoremove -y
apt-get autoclean
echo "$CLEARBOOT"
clear

# Success!
echo -e "\e[32m"
echo    "+--------------------------------------------------------------------+"
echo    "| You have sucessfully installed Wordpress! System will now reboot...|"
echo    "|                                                                    |"
echo -e "|         \e[0mLogin to Wordpress in your browser:\e[36m" $ADDRESS"\e[32m          |"
echo    "|                                                                    |"
echo -e "|         \e[0mPublish your server online! \e[36mhttps://goo.gl/iUGE2U\e[32m          |"
echo    "|                                                                    |"
echo -e "|      \e[0mYour MySQL password is stored in: \e[36m$PW_FILE\e[32m     |"
echo    "|                                                                    |"
echo -e "|    \e[91m#################### Tech and Me - 2016 ####################\e[32m    |"
echo    "+--------------------------------------------------------------------+"
echo
read -p "Press any key to continue..." -n1 -s
echo -e "\e[0m"
echo

# Cleanup 2
rm $SCRIPTS/wordpress-startup-script.sh
rm $SCRIPTS/ip.sh
rm $SCRIPTS/test_connection.sh
rm $SCRIPTS/instruction.sh
rm $WPATH/wp-cli.yml
sed -i "s|instruction.sh|techandme.sh|g" /home/wordpress/.bash_profile
cat /dev/null > ~/.bash_history
cat /dev/null > /var/spool/mail/root
cat /dev/null > /var/spool/mail/wordpress
cat /dev/null > /var/log/apache2/access.log
cat /dev/null > /var/log/apache2/error.log
cat /dev/null > /var/log/cronjobs_success.log
sed -i "s|sudo -i||g" /home/wordpress/.bash_profile
cat /dev/null > /etc/rc.local
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
echo
echo
cat << LETSENC
+-----------------------------------------------+
|  Ok, now the last part - a proper SSL cert.   |
|                                               |
|  The following script will install a trusted  |
|  SSL certificate through Let's Encrypt.       |
+-----------------------------------------------+
LETSENC
# Let's Encrypt
function ask_yes_or_no() {
    read -p "$1 ([y]es or [N]o): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}
if [[ "yes" == $(ask_yes_or_no "Do you want to install SSL?") ]]
then
        bash $SCRIPTS/activate-ssl.sh
else
echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/activate-ssl.sh"
    echo -e "\e[32m"
    read -p "Press any key to continue... " -n1 -s
    echo -e "\e[0m"
fi

## Reboot
reboot

exit 0
