#!/bin/bash

# Tech and Me - ©2017, https://www.techandme.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0

WWW_ROOT=/var/www/html
WPATH=$WWW_ROOT/wordpress
SCRIPTS=/var/scripts
PW_FILE=/var/mysql_password.txt # Keep in sync with wordpress_install.sh
IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
CLEARBOOT=$(dpkg -l linux-* | awk '/^ii/{ print $2}' | grep -v -e `uname -r | cut -f1,2 -d"-"` | grep -e [0-9] | xargs sudo apt -y purge)
WANIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
PHPMYADMIN_CONF="/etc/apache2/conf-available/phpmyadmin.conf"
STATIC="https://raw.githubusercontent.com/techandme/wordpress-vm/master/static"
LETS_ENC="https://raw.githubusercontent.com/techandme/wordpress-vm/master/lets-encrypt"

# DEBUG mode
if [ $DEBUG -eq 1 ]
then
    set -e
    set -x
else
    sleep 1
fi

# Check if root
if [ "$(whoami)" != "root" ]
then
    echo
    echo -e "\e[31mSorry, you are not root.\n\e[0mYou must type: \e[36msudo \e[0mbash $SCRIPTS/wordpress-startup-script.sh"
    echo
    exit 1
fi

# Check network
echo "Testing if network is OK..."
service networking restart
    curl -s http://github.com > /dev/null
if [ $? -eq 0 ]
then
    echo -e "\e[32mOnline!\e[0m"
else
echo "Setting correct interface..."
# Set correct interface
{ sed '/# The primary network interface/q' /etc/network/interfaces; printf 'auto %s\niface %s inet dhcp\n# This is an autoconfigured IPv6 interface\niface %s inet6 auto\n' "$IFACE" "$IFACE" "$IFACE"; } > /etc/network/interfaces.new
mv /etc/network/interfaces.new /etc/network/interfaces
service networking restart
fi

# Check network
echo "Testing if network is OK..."
service networking restart
    curl -s http://github.com > /dev/null
if [ $? -eq 0 ]
then
    echo -e "\e[32mOnline!\e[0m"
else
    echo
    echo "Network NOT OK. You must have a working Network connection to run this script."
    echo "Please report this issue here: https://github.com/techandme/wordpress-vm/issues/new"
    exit 1
fi

# Get the best mirrors for Ubuntu based on location
echo "Locating the best mirrors..."
apt-select
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup && \
if [ -f sources.list ]
then
sudo mv sources.list /etc/apt/
fi

ADDRESS=$(hostname -I | cut -d ' ' -f 1)

echo "Getting scripts from GitHub to be able to run the first setup..."

# Get security script
        if [ -f $SCRIPTS/security.sh ];
                then
                rm $SCRIPTS/security.sh
                wget -q $STATIC/security.sh -P $SCRIPTS
                else
        wget -q $STATIC/security.sh -P $SCRIPTS
	fi

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
                wget -q $LETS_ENC/activate-ssl-wp.sh -P $SCRIPTS
                else
        	wget -q $LETS_ENC/activate-ssl-wp.sh -P $SCRIPTS
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
echo -e "\e[32m"
read -p "Press any key to start the script..." -n1 -s
echo -e "\e[0m"
clear

# Set hostname and ServerName
echo "Setting hostname..."
FQN=$(host -TtA $(hostname -s)|grep "has address"|awk '{print $1}') ; \
if [[ "$FQN" == "" ]]
then
    FQN=$(hostname -s)
fi
sudo sh -c "echo 'ServerName $FQN' >> /etc/apache2/apache2.conf"
sudo hostnamectl set-hostname $FQN
service apache2 restart
cat << ETCHOSTS > "/etc/hosts"
127.0.1.1 $FQN.localdomain $FQN
127.0.0.1 localhost

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ETCHOSTS

# VPS?
function ask_yes_or_no() {
    read -p "$1 ([y]es or [N]o): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

if [[ "no" == $(ask_yes_or_no "Do you run this script on a *remote* VPS like DigitalOcean, HostGator or similar?") ]]
then
    # Change IP
    echo -e "\e[0m"
    echo "OK, we assume you run this locally and we will now configure your IP to be static."
    echo -e "\e[1m"
    echo "Your internal IP is: $ADDRESS"
    echo -e "\e[0m"
    echo -e "Write this down, you will need it to set static IP"
    echo -e "in your router later. It's included in this guide:"
    echo -e "https://www.techandme.se/open-port-80-443/ (step 1 - 5)"
    echo -e "\e[32m"
    read -p "Press any key to set static IP..." -n1 -s
    echo -e "\e[0m"
    ifdown $IFACE
    sleep 1
    ifup $IFACE
    sleep 1
    bash $SCRIPTS/ip.sh
    if [ "$IFACE" = "" ]
    then
        echo "IFACE is an emtpy value. Trying to set IFACE with another method..."
        wget -q $STATIC/ip2.sh -P $SCRIPTS
        bash $SCRIPTS/ip2.sh
        rm $SCRIPTS/ip2.sh
    fi
    ifdown $IFACE
    sleep 1
    ifup $IFACE
    sleep 1
    echo
    echo "Testing if network is OK..."
    sleep 1
    echo
    CONTEST=$(bash $SCRIPTS/test_connection.sh)
    if [ "$CONTEST" == "Connected!" ]
    then
        # Connected!
        echo -e "\e[32mConnected!\e[0m"
        echo
        echo -e "We will use the DHCP IP: \e[32m$ADDRESS\e[0m. If you want to change it later then just edit the interfaces file:"
        echo "sudo nano /etc/network/interfaces"
        echo
        echo "If you experience any bugs, please report it here:"
        echo "https://github.com/techandme/wordpress-vm/issues/new"
        echo -e "\e[32m"
        read -p "Press any key to continue..." -n1 -s
        echo -e "\e[0m"
    else
        # Not connected!
        echo -e "\e[31mNot Connected\e[0m\nYou should change your settings manually in the next step."
        echo -e "\e[32m"
        read -p "Press any key to open /etc/network/interfaces..." -n1 -s
        echo -e "\e[0m"
        nano /etc/network/interfaces
        service networking restart
        clear
        echo "Testing if network is OK..."
        ifdown $IFACE
        sleep 1
        ifup $IFACE
        sleep 1
        bash $SCRIPTS/test_connection.sh
        sleep 1
    fi 
else
    echo "OK, then we will not set a static IP as your VPS provider already have setup the network for you..."
    sleep 5
fi
clear

# Set keyboard layout
echo "Current keyboard layout is $(localectl status | grep "Layout" | awk '{print $3}')"
echo "You must change keyboard layout to your language"
echo -e "\e[32m"
read -p "Press any key to change keyboard layout... " -n1 -s
echo -e "\e[0m"
dpkg-reconfigure keyboard-configuration
echo
clear

# Get new server keys
echo "Adding new SSH keys..."
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Generate new MySQL password
echo
bash $SCRIPTS/change_mysql_pass.sh
rm $SCRIPTS/change_mysql_pass.sh

# Install phpMyadmin
bash $SCRIPTS/phpmyadmin_install_ubuntu16.sh
rm $SCRIPTS/phpmyadmin_install_ubuntu16.sh
clear

# Add extra security
function ask_yes_or_no() {
    read -p "$1 ([y]es or [N]o): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}
if [[ "yes" == $(ask_yes_or_no "Do you want to add extra security, based on this: http://goo.gl/gEJHi7 ?") ]]
then
	bash $SCRIPTS/security.sh
	rm $SCRIPTS/security.sh
else
echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/security.sh"
    echo -e "\e[32m"
    read -p "Press any key to continue... " -n1 -s
    echo -e "\e[0m"
fi
clear

# Set keyboard layout
echo "Current keyboard layout is $(localectl status | grep "Layout" | awk '{print $3}')"
echo "You must change keyboard layout to your language"
echo -e "\e[32m"
read -p "Press any key to change keyboard layout... " -n1 -s
echo -e "\e[0m"
dpkg-reconfigure keyboard-configuration
echo
clear

# Change Timezone
echo "Current timezone is $(cat /etc/timezone)"
echo "You must change timezone to your timezone"
echo -e "\e[32m"
read -p "Press any key to change timezone... " -n1 -s
echo -e "\e[0m"
dpkg-reconfigure tzdata
echo
sleep 3
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

echo "Enter FQDN (http://yourdomain.com):"
read FQDN
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
echo
echo "Enter FQDN (http://yourdomain.com):"
read FQDN
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
clear

echo "$FQDN" > fqdn.txt
wp option update siteurl < fqdn.txt --allow-root --path=$WPATH
rm fqdn.txt

ADDRESS=$(hostname -I | cut -d ' ' -f 1)
wp search-replace http://$ADDRESS $FQDN --precise --all-tables --path=$WPATH --allow-root

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
apt autoremove -y
apt autoclean
echo "$CLEARBOOT"
clear

# Success!
echo -e "\e[32m"
echo    "+--------------------------------------------------------------------+"
echo    "| You have sucessfully installed Wordpress! System will now reboot...|"
echo    "|                                                                    |"
echo -e "|         \e[0mLogin to Wordpress in your browser:\e[36m" $FQDN"\e[32m          |"
echo    "|                                                                    |"
echo -e "|         \e[0mPublish your server online! \e[36mhttps://goo.gl/iUGE2U\e[32m          |"
echo    "|                                                                    |"
echo -e "|      \e[0mYour MySQL password is stored in: \e[36m$PW_FILE\e[32m     |"
echo    "|                                                                    |"
echo -e "|    \e[91m#################### Tech and Me - 2017 ####################\e[32m    |"
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

# Prefer IPv6
sed -i "s|precedence ::ffff:0:0/96  100|#precedence ::ffff:0:0/96  100|g" /etc/gai.conf

## Reboot
echo "Installations finished. System will now reboot..."
reboot

exit 0
