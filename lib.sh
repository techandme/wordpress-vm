#!/bin/bash
# shellcheck disable=2034,2059
true
# see https://github.com/koalaman/shellcheck/wiki/Directive

## VARIABLES

# Dirs
SCRIPTS=/var/scripts
WWW_ROOT=/var/www/html
WPATH=$WWW_ROOT/wordpress
GPGDIR=/tmp/gpg
VMLOGS=/var/log/wordpress

# Helper function for generating random passwords
gen_passwd() {
    local length=$1
    local charset="$2"
    local password=""
    while [ ${#password} -lt "$length" ]
    do
        password=$(echo "$password""$(head -c 100 /dev/urandom | LC_ALL=C tr -dc "$charset")" | fold -w "$length" | head -n 1)
    done
    echo "$password"
}

# Ubuntu OS
DISTRO=$(lsb_release -sr)
KEYBOARD_LAYOUT=$(localectl status | grep "Layout" | awk '{print $3}')

# Hypervisor
# HYPERVISOR=$(dmesg --notime | grep -i hypervisor | cut -d ':' -f2 | head -1 | tr -d ' ') TODO
SYSVENDOR=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
# Network
IFACE=$(ip r | grep "default via" | awk '{print $5}')
IFACE2=$(ip -o link show | awk '{print $2,$9}' | grep 'UP' | cut -d ':' -f 1)
REPO=$(grep deb-src /etc/apt/sources.list | grep http | awk '{print $3}' | head -1)
ADDRESS=$(hostname -I | cut -d ' ' -f 1)

# WANIP4=$(dig +short myip.opendns.com @resolver1.opendns.com) # as an alternative
WANIP4=$(curl -s -k -m 5 https://ipv4bot.whatismyipaddress.com)
INTERFACES="/etc/netplan/01-netcfg.yaml"
GATEWAY=$(ip route | grep default | awk '{print $3}')

# Internet DNS
INTERNET_DNS="9.9.9.9"

# Default Quad9 DNS servers, overwritten by the systemd global DNS defined servers, if set
DNS1="9.9.9.9"
DNS2="149.112.112.112"
use_global_systemd_dns() {
if [ -f "/etc/systemd/resolved.conf" ]
then
    local resolvedDns1
    resolvedDns1=$(grep -m 1 -E "^DNS=.+" /etc/systemd/resolved.conf | sed s/^DNS=// | awk '{print $1}')
    if [ -n "$resolvedDns1" ]
    then
        DNS1="$resolvedDns1"

        local resolvedDns2
        resolvedDns2=$(grep -m 1 -E "^DNS=.+" /etc/systemd/resolved.conf | sed s/^DNS=// | awk '{print $2}')
        if [ -n "$resolvedDns2" ]
        then
            DNS2="$resolvedDns2"
        else
            DNS2=
        fi
    fi
fi
}
use_global_systemd_dns

# Whiptails
TITLE="Wordpress VM - $(date +%Y)"
[ -n "$SCRIPT_NAME" ] && TITLE+=" - $SCRIPT_NAME"
CHECKLIST_GUIDE="Navigate with the [ARROW] keys and (de)select with the [SPACE] key. \
Confirm by pressing [ENTER]. Cancel by pressing [ESC]."
MENU_GUIDE="Navigate with the [ARROW] keys and confirm by pressing [ENTER]. Cancel by pressing [ESC]."
RUN_LATER_GUIDE="You can view this script later by running 'sudo bash $SCRIPTS/menu.sh'."

# Repo
GITHUB_REPO="https://raw.githubusercontent.com/techandme/wordpress-vm/master"
STATIC="$GITHUB_REPO/static"
LETS_ENC="$GITHUB_REPO/lets-encrypt"
APP="$GITHUB_REPO/apps"
OLD="$GITHUB_REPO/old"
ADDONS="$GITHUB_REPO/addons"
MENU="$GITHUB_REPO/menu"
DISK="$GITHUB_REPO/disk"
NETWORK="$GITHUB_REPO/network"
ISSUES="https://github.com/techandme/wordpress-vm/vm/issues"

# User information
WPPASS=wordpress
WPUSER=wordpress
UNIXUSER=$SUDO_USER
UNIXUSER_PROFILE="/home/$UNIXUSER/.bash_profile"
ROOT_PROFILE="/root/.bash_profile"

# Database
SHUF=$(shuf -i 25-29 -n 1)
WPDBNAME=wordpress_by_www_hanssonit_se
WPADMINUSER=wordpress_gui_admin_user
MARIADB_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
WPDBPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
NEWMARIADBPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
WPDBUSER=wordpress_db_user
WPADMINPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)

# Set the hour for automatic updates. This would be 18:00 as only the hour is configurable.
AUT_UPDATES_TIME="18"

# Keys
OpenPGP_fingerprint='28806A878AE423A28372792ED75899B9A724937A'

# Letsencrypt
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
LETSENCRYPTPATH="/etc/letsencrypt"
CERTFILES="$LETSENCRYPTPATH/live"
DHPARAMS_TLS="$CERTFILES/$TLSDOMAIN/dhparam.pem"
DHPARAMS_SUB="$CERTFILES/$SUBDOMAIN/dhparam.pem"
TLS_CONF="wordpress_tls_domain_self_signed.conf"
HTTP_CONF="wordpress_http_domain_self_signed.conf"

# Path to specific files
SECURE="$SCRIPTS/wp-permissions.sh"
ETCMYCNF="/etc/mysql/my.cnf"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_DEF="$SITES_AVAILABLE/default"

# PHP-FPM
PHPVER=7.4
PHP_FPM_DIR=/etc/php/$PHPVER/fpm
PHP_INI=$PHP_FPM_DIR/php.ini
PHP_POOL_DIR=$PHP_FPM_DIR/pool.d
PHP_MODS_DIR=/etc/php/"$PHPVER"/mods-available
PHP_FPM_SOCK=/var/run/php"$PHPVER"-fpm-wordpress.sock

# Adminer
ADMINERDIR=/usr/share/adminer
ADMINER_CONF="$SITES_ENABLED/adminer.conf"

# Redis
REDIS_CONF=/etc/redis/redis.conf
REDIS_SOCK=/var/run/redis/redis-server.sock
RSHUF=$(shuf -i 30-35 -n 1)
REDIS_PASS=$(gen_passwd "$SHUF" "a-zA-Z0-9@#*=")
REDISPTXT=/tmp/redispasstxt

## FUNCTIONS

# If script is running as root?
#
# Example:
# if is_root
# then
#     # do stuff
# else
#     print_text_in_color "$IRed" "You are not root..."
#     exit 1
# fi
#
is_root() {
    if [[ "$EUID" -ne 0 ]]
    then
        return 1
    else
        return 0
    fi
}

# Check if root
root_check() {
if ! is_root
then
    msg_box "Sorry, you are not root. You now have two options:

1. With SUDO directly:
   a) :~$ sudo bash $SCRIPTS/name-of-script.sh

2. Become ROOT and then type your command:
   a) :~$ sudo -i
   b) :~# bash $SCRIPTS/name-of-script.sh

In both cases above you can leave out $SCRIPTS/ if the script
is directly in your PATH.

More information can be found here: https://unix.stackexchange.com/a/3064"
    exit 1
fi
}

debug_mode() {
if [ "$DEBUG" -eq 1 ]
then
    set -ex
fi
}

msg_box() {
    [ -n "$2" ] && local SUBTITLE=" - $2"
    whiptail --title "$TITLE$SUBTITLE" --msgbox "$1" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3
}

yesno_box_yes() {
    [ -n "$2" ] && local SUBTITLE=" - $2"
    if (whiptail --title "$TITLE$SUBTITLE" --yesno "$1" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3)
    then
        return 0
    else
        return 1
    fi
}

yesno_box_no() {
    [ -n "$2" ] && local SUBTITLE=" - $2"
    if (whiptail --title "$TITLE$SUBTITLE" --defaultno --yesno "$1" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3)
    then
        return 0
    else
        return 1
    fi
}

input_box() {
    [ -n "$2" ] && local SUBTITLE=" - $2"
    local RESULT && RESULT=$(whiptail --title "$TITLE$SUBTITLE" --nocancel --inputbox "$1" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3)
    echo "$RESULT"
}

input_box_flow() {
    local RESULT
    while :
    do
        RESULT=$(input_box "$1" "$2")
        if [ -z "$RESULT" ]
        then
            msg_box "Input is empty, please try again." "$2"
        elif ! yesno_box_yes "Is this correct? $RESULT" "$2"
        then
            msg_box "OK, please try again." "$2"
        else
            break
        fi
    done
    echo "$RESULT"
}

install_popup() {
    msg_box "$SCRIPT_EXPLAINER"
    if yesno_box_yes "Do you want to install $1?"
    then
        print_text_in_color "$ICyan" "Installing $1..."
    else
        if [ -z "$2" ] || [ "$2" = "exit" ]
        then
            exit 1
        elif [ "$2" = "sleep" ]
        then
            sleep 1
        elif [ "$2" = "return" ]
        then
            return 1
        else
            exit 1
        fi
    fi
}

reinstall_remove_menu() {
    REINSTALL_REMOVE=$(whiptail --title "$TITLE" --menu \
"It seems like $1 is already installed.\nChoose what you want to do.
$MENU_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Reinstall" " $1" \
"Uninstall" " $1" 3>&1 1>&2 2>&3)
    if [ "$REINSTALL_REMOVE" = "Reinstall" ]
    then
        print_text_in_color "$ICyan" "Reinstalling $1..."
    elif [ "$REINSTALL_REMOVE" = "Uninstall" ]
    then
        print_text_in_color "$ICyan" "Uninstalling $1..."
    elif [ -z "$REINSTALL_REMOVE" ]
    then
        if [ -z "$2" ] || [ "$2" = "exit" ]
        then
            exit 1
        elif [ "$2" = "sleep" ]
        then
            sleep 1
        elif [ "$2" = "return" ]
        then
            return 1
        else
            exit 1
        fi
    fi
}

removal_popup() {
    if [ "$REINSTALL_REMOVE" = "Uninstall" ]
    then
        msg_box "$1 was successfully uninstalled."
        if [ -z "$2" ] || [ "$2" = "exit" ]
        then
            exit 1
        elif [ "$2" = "sleep" ]
        then
            sleep 1
        elif [ "$2" = "return" ]
        then
            return 1
        else
            exit 1
        fi
    elif [ "$REINSTALL_REMOVE" = "Reinstall" ]
    then
        print_text_in_color "$ICyan" "Reinstalling $1..."
    else
        msg_box "It seems like neither Uninstall nor Reinstall is chosen, \
something is wrong here. Please report this to $ISSUES"
        exit 1
    fi
}

wp_cli_cmd() {
# Check if Wordpress is installed in the regular path or try to find it
if [ ! -d "$WPATH" ]
then
    WPATH="/var/www/$(find /var/www/* -type d | grep wp | head -1 | cut -d "/" -f4)"
    export WPATH
    if [ ! -d "$WPATH"/wp-admin ]
    then
        WPATH="/var/www/$(find /var/www/* -type d | grep wp | tail -1 | cut -d "/" -f4)"
        export WPATH
        if [ ! -d "$WPATH"/wp-admin ]
        then
            WPATH="/var/www/html/$(find /var/www/html/* -type d | grep wp | head -1 | cut -d "/" -f5)"
            export WPATH
            if [ ! -d "$WPATH"/wp-admin ]
            then
                WPATH="/var/www/html/$(find /var/www/html/* -type d | grep wp | tail -1 | cut -d "/" -f5)"
                export WPATH
                if [ ! -d "$WPATH"/wp-admin ]
                then
                    msg_box "Wordpress doesn't seem to be installed in the regular path. We tried to find it, but didn't succeed.

The script will now exit."
                    exit 1
                fi
            fi
        fi
    fi
fi
# If everytthing seems OK, then run wp cli
cd "$WPATH"
export WP_CLI_CACHE_DIR="$WPATH/.wp-cli/cache"
check_command sudo -u www-data /usr/local/bin/wp --path="$WPATH" "$@";
# Go back to user dir
cd
}

# Check if process is runnnig: is_process_running dpkg
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

# Checks if site is reachable with a HTTP 200 status
site_200() {
print_text_in_color "$ICyan" "Checking connection..."
        CURL_STATUS="$(curl -LI "${1}" -o /dev/null -w '%{http_code}\n' -s)"
        if [[ "$CURL_STATUS" = "200" ]]
        then
            return 0
        else
            print_text_in_color "$IRed" "curl didn't produce a 200 status, is ${1} reachable?"
            return 1
        fi
}

# Do a DNS lookup and compare the WAN address with the A record
domain_check_200() {
    print_text_in_color "$ICyan" "Doing a DNS lookup for ${1}..."
    install_if_not dnsutils

    # Try to resolve the domain with nslookup using $DNS as resolver
    if nslookup "${1}" "$INTERNET_DNS" >/dev/null 2>&1
    then
        print_text_in_color "$IGreen" "DNS seems correct when checking with nslookup!"
    else
        print_text_in_color "$IRed" "DNS lookup failed with nslookup."
        print_text_in_color "$IRed" "Please check your DNS settings! Maybe the domain isn't propagated?"
        print_text_in_color "$ICyan" "Please check https://www.whatsmydns.net/#A/${1} if the IP seems correct."
        nslookup "${1}" "$INTERNET_DNS"
        return 1
    fi

    # Is the DNS record same as the external IP address of the server?
    if dig +short "${1}" @resolver1.opendns.com | grep -q "$WANIP4"
    then
        print_text_in_color "$IGreen" "DNS seems correct when checking with dig!"
    else
    msg_box "DNS lookup failed with dig. The external IP ($WANIP4) \
address of this server is not the same as the A-record ($DIG).
Please check your DNS settings! Maybe the domain isn't propagated?
Please check https://www.whatsmydns.net/#A/${1} if the IP seems correct."

    msg_box "As you noticed your WAN IP and DNS record doesn't match. \
This can happen when using DDNS for example, or in some edge cases.
If you feel brave, or are sure that everything is setup correctly, \
then you can choose to skip this test in the next step.

You can always contact us for further support if you wish: \
https://shop.hanssonit.se/product/premium-support-per-30-minutes/"
        if ! yesno_box_no "Do you feel brave and want to continue?"
            then
            exit
        fi
    fi
}

# A function to set the systemd-resolved default DNS servers based on the
# current Internet facing interface. This is needed for docker interfaces
# that might not use the same DNS servers otherwise.
set_systemd_resolved_dns() {
local iface="$1"
local pattern="$iface(?:.|\n)*?DNS Servers: ((?:[0-9a-f.: ]|\n)*?)\s*(?=\n\S|\n.+: |$)"
local dnss
dnss=$( systemd-resolve --status | perl -0777 -ne "if ((\$v) = (/$pattern/)) {\$v=~s/(?:\s|\n)+/ /g;print \"\$v\n\";}" )
if [ -n "$dnss" ]
then
    sed -i "s/^#\?DNS=.*$/DNS=${dnss}/" /etc/systemd/resolved.conf
    systemctl restart systemd-resolved &>/dev/null
    sleep 1
fi
}

# A function to fetch a file with curl to a directory
# 1 = https://example.com
# 2 = name of file
# 3 = directory that the file should end up in
curl_to_dir() {
if [ ! -d "$3" ]
then
    mkdir -p "$3"
fi
    rm -f "$3"/"$2"
    curl -sfL "$1"/"$2" -o "$3"/"$2"
}

start_if_stopped() {
if ! pgrep "$1"
then
    print_text_in_color "$ICyan" "Starting $1..."
    systemctl start "$1".service
fi
}

# Compatibility with older VMs
calculate_max_children() {
    calculate_php_fpm
}

test_connection() {
version(){
    local h t v

    [[ $2 = "$1" || $2 = "$3" ]] && return 0

    v=$(printf '%s\n' "$@" | sort -V)
    h=$(head -n1 <<<"$v")
    t=$(tail -n1 <<<"$v")

    [[ $2 != "$h" && $2 != "$t" ]]
}
if ! version 18.04 "$DISTRO" 20.04.6
then
    print_text_in_color "$IRed" "Your current Ubuntu version is $DISTRO but must be between \
18.04 - 20.04.4 to run this script."
    print_text_in_color "$ICyan" "Please contact us to get support for upgrading your server:"
    print_text_in_color "$ICyan" "https://www.hanssonit.se/#contact"
    print_text_in_color "$ICyan" "https://shop.hanssonit.se/"
    sleep 300
fi

# Install dnsutils if not existing
if ! dpkg-query -W -f='${Status}' "dnsutils" | grep -q "ok installed"
then
    apt update -q4 & spinner_loading && apt install dnsutils -y
fi
# Install net-tools if not existing
if ! dpkg-query -W -f='${Status}' "net-tools" | grep -q "ok installed"
then
    apt update -q4 & spinner_loading && apt install net-tools -y
fi
# After applying Netplan settings, try a DNS lookup.
# Restart systemd-networkd if this fails and try again.
# If this second check also fails, consider this a problem.
print_text_in_color "$ICyan" "Checking connection..."
netplan apply
sleep 2
if ! nslookup github.com
then
    print_text_in_color "$ICyan" "Trying to restart netplan service..."
    check_command systemctl restart systemd-networkd && sleep 2
    if ! nslookup github.com
    then
        msg_box "Network NOT OK. You must have a working network connection to run this script.
If you think that this is a bug, please report it to https://github.com/techandme/wordpress-vm/issues."
        return 1
    fi
fi
print_text_in_color "$IGreen" "Online!"
return 0
}


# Check that the script can see the external IP (nginx fails otherwise), used e.g. in the adminer app script.
check_external_ip() {
if [ -z "$WANIP4" ]
then
    print_text_in_color "$IRed" "WANIP4 is an emtpy value, Nginx will fail on reboot due to this. \
Please check your network and try again."
    sleep 3
    exit 1
fi
}

restart_webserver() {
check_command systemctl restart nginx.service
if is_this_installed php"$PHPVER"-fpm
then
    check_command systemctl restart php"$PHPVER"-fpm.service
fi

}

# Install certbot (Let's Encrypt)
install_certbot() {
certbot --version 2> /dev/null
LE_IS_AVAILABLE=$?
if [ $LE_IS_AVAILABLE -eq 0 ]
then
    certbot --version 2> /dev/null
else
    print_text_in_color "$ICyan" "Installing certbot (Let's Encrypt)..."
    install_if_not snapd
    snap install certbot --classic
    # Update $PATH in current session (login and logout is required otherwise)
    check_command hash -r
fi
}

# Generate certs and configure it automatically
# https://certbot.eff.org/docs/using.html#certbot-command-line-options
generate_cert() {
uir_hsts=""
if [ -z "$SUBDOMAIN" ]
then
    uir_hsts="--uir --hsts"
fi
rm -f "$SITES_ENABLED"/default.conf
rm -f "$SITES_ENABLED"/default
systemctl reload nginx.service
default_le="--rsa-key-size 4096 --renew-by-default --no-eff-email --agree-tos $uir_hsts --server https://acme-v02.api.letsencrypt.org/directory -d $1"
#http-01
local  standalone="certbot certonly --standalone --pre-hook \"systemctl stop nginx.service\" --post-hook \"systemctl start nginx.service\" $default_le"
#tls-alpn-01
local  tls_alpn_01="certbot certonly --preferred-challenges tls-alpn-01 $default_le"
#dns
local  dns="certbot certonly --manual --manual-public-ip-logging-ok --preferred-challenges dns $default_le"
local  methods=(standalone dns)

for f in ${methods[*]}
do
    print_text_in_color "${ICyan}" "Trying to generate certs and validate them with $f method."
    current_method=""
    eval current_method="\$$f"
    if eval "$current_method"
    then
        return 0
    elif [ "$f" != "${methods[$((${#methods[*]} - 1))]}" ]
    then
        msg_box "It seems like no certs were generated when trying \
to validate them with the $f method. We will do more tries."
    else
        msg_box "It seems like no certs were generated when trying \
to validate them with the $f method. We have tried all the methods. Please check your DNS and try again."
        return 1;
    fi
done
}

# Last message depending on with script that is being run when using the generate_cert() function
last_fail_tls() {
    msg_box "All methods failed. :/

You can run the script again by executing: sudo bash $SCRIPTS/menu.sh
Please try to run it again some other time with other settings.

There are different configs you can try in Let's Encrypt's user guide:
https://letsencrypt.readthedocs.org/en/latest/index.html
Please check the guide for further information on how to enable TLS.

This script is developed on GitHub, feel free to contribute:
https://github.com/techandme/wordpress-vm"

if [ -n "$2" ]
then
    msg_box "The script will now do some cleanup and revert the settings."
    # Cleanup
    snap remove certbot
    rm -f "$SCRIPTS"/test-new-config.sh
fi

# Restart webserver services
restart_webserver
}

# Use like this: open_port 443 TCP
# or e.g. open_port 3478 UDP
open_port() {
    install_if_not miniupnpc
    print_text_in_color "$ICyan" "Trying to open port $1 automatically..."
    if ! upnpc -a "$ADDRESS" "$1" "$1" "$2" &>/dev/null
    then
        msg_box "Failed to open port $1 $2 automatically. You have to do this manually."
        FAIL=1
    fi
}

cleanup_open_port() {
    if [ -n "$FAIL" ]
    then
        apt-get purge miniupnpc -y
        apt autoremove -y
    fi
}

# Check if port is open # check_open_port 443 domain.example.com
check_open_port() {
print_text_in_color "$ICyan" "Checking if port ${1} is open with https://www.networkappers.com/tools/open-port-checker..."
install_if_not curl
# WAN Adress
if check_command curl -s -H 'Cache-Control: no-cache' -H 'Referer: https://www.networkappers.com/tools/open-port-checker' "https://networkappers.com/api/port.php?ip=${WANIP4}&port=${1}" | grep -q "open"
then
    print_text_in_color "$IGreen" "Port ${1} is open on ${WANIP4}!"
# Domain name
elif check_command curl -s -H 'Cache-Control: no-cache' -H 'Referer: https://www.networkappers.com/tools/open-port-checker' "https://www.networkappers.com/api/port.php?ip=${2}&port=${1}" | grep -q "open"
then
    print_text_in_color "$IGreen" "Port ${1} is open on ${2}!"
else
    msg_box "It seems like the port ${1} is closed. This could happend when your
ISP has blocked the port, or that the port isn't open.

If you are 100% sure the port ${1} is open you can now choose to
continue. There are no guarantees that it will work anyway though,
since the service depend on that the port ${1} is open and
accessible from outside your network."
    if ! yesno_box_no "Are you 100% sure the port ${1} is open?"
    then
        msg_box "Port $1 is not open on either ${WANIP4} or ${2}.
        
Please follow this guide to open ports in your router or firewall:\nhttps://www.techandme.se/open-port-80-443/"
        any_key "Press any key to exit..."
        exit 1
    fi
fi
}

check_distro_version() {
# Check Ubuntu version
if lsb_release -sc | grep -ic "bionic" &> /dev/null || lsb_release -sc | grep -ic "focal" &> /dev/null
then
    OS=1
elif lsb_release -i | grep -ic "Ubuntu" &> /dev/null
then
    OS=1
elif uname -a | grep -ic "bionic" &> /dev/null || uname -a | grep -ic "focal" &> /dev/null
then
    OS=1
elif uname -v | grep -ic "Ubuntu" &> /dev/null
then
    OS=1
fi

if [ "$OS" != 1 ]
then
    msg_box "Ubuntu Server is required to run this script.
Please install that distro and try again.

You can find the download link here: https://www.ubuntu.com/download/server"
    exit 1
fi

if ! version 18.04 "$DISTRO" 20.04.4; then
    msg_box "Your current Ubuntu version is $DISTRO but must be between 18.04 - 20.04.4 to run this script."
    msg_box "Please contact us to get support for upgrading your server:
https://www.hanssonit.se/#contact
https://shop.hanssonit.se/"
    exit 1
fi
}

# Check if program is installed (stop_if_installed nginx)
stop_if_installed() {
if [ "$(dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    print_text_in_color "$IRed" "${1} is installed, it must be a clean server."
    exit 1
fi
}

# Check if program is installed (is_this_installed nginx)
is_this_installed() {
if dpkg-query -W -f='${Status}' "${1}" | grep -q "ok installed"
then
    return 0
else
    return 1
fi
}

# Install_if_not program
install_if_not() {
if ! dpkg-query -W -f='${Status}' "${1}" | grep -q "ok installed"
then
    apt update -q4 & spinner_loading && RUNLEVEL=1 apt install "${1}" -y
fi
}

# Test RAM size
# Call it like this: ram_check [amount of min RAM in GB] [for which program]
# Example: ram_check 2 Wordpress
ram_check() {
install_if_not bc
mem_available="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
mem_available_gb="$(LC_NUMERIC="en_US.UTF-8" printf '%0.2f\n' "$(echo "scale=3; $mem_available/(1024*1024)" | bc)")"
mem_required="$((${1}*(924*1024)))" # 100MiB/GiB margin and allow 90% to be able to run on physical machines
if [ "${mem_available}" -lt "${mem_required}" ]
then
    print_text_in_color "$IRed" "Error: ${1} GB RAM required to install ${2}!" >&2
    print_text_in_color "$IRed" "Current RAM is: ($mem_available_gb GB)" >&2
    sleep 3
    msg_box "** Error: insufficient memory. ${mem_available_gb}GB RAM installed, ${1}GB required.

Please shutdown the server, raise your RAM and then try again"
    exit 1
else
    print_text_in_color "$IGreen" "RAM for ${2} OK! ($mem_available_gb GB)"
fi
}

# Test number of CPU
# Call it like this: cpu_check [amount of min CPU] [for which program]
# Example: cpu_check 2 Wordpress
cpu_check() {
nr_cpu="$(nproc)"
if [ "${nr_cpu}" -lt "${1}" ]
then
    print_text_in_color "$IRed" "Error: ${1} CPU required to install ${2}!" >&2
    print_text_in_color "$IRed" "Current CPU: ($((nr_cpu)))" >&2
    sleep 3
    exit 1
else
    print_text_in_color "$IGreen" "CPU for ${2} OK! ($((nr_cpu)))"
fi
}

check_command() {
if ! "$@";
then
    print_text_in_color "$ICyan" "Sorry but something went wrong. Please report \
this issue to $ISSUES and include the output of the error message. Thank you!"
    print_text_in_color "$IRed" "$* failed"
    exit 1
fi
}

network_ok() {
version(){
    local h t v

    [[ $2 = "$1" || $2 = "$3" ]] && return 0

    v=$(printf '%s\n' "$@" | sort -V)
    h=$(head -n1 <<<"$v")
    t=$(tail -n1 <<<"$v")

    [[ $2 != "$h" && $2 != "$t" ]]
}
if version 18.04 "$DISTRO" 20.04.6
then
    print_text_in_color "$ICyan" "Testing if network is OK..."
    if ! netplan apply
    then
        systemctl restart systemd-networkd > /dev/null
    fi
    # Check the connention
    countdown 'Waiting for network to restart...' 3
    if ! site_200 github.com
    then
        # sleep 10 seconds so that some slow networks have time to restart
        countdown 'Not online yet, waiting a bit more...' 10
        if ! site_200 github.com
        then
            # sleep 30 seconds so that some REALLY slow networks have time to restart
            countdown 'Not online yet, waiting a bit more (last try)...' 30
            site_200 github.com
        fi
    fi
else
    msg_box "Your current Ubuntu version is $DISTRO but must be between 18.04 - 20.04.6 to run this script."
    msg_box "Please contact us to get support for upgrading your server:
https://www.hanssonit.se/#contact
https://shop.hanssonit.se/"
    msg_box "We will now pause for 60 seconds. Please press CTRL+C when prompted to do so."
    countdown "Please press CTRL+C to abort..." 60
fi
}

# Whiptail auto-size
calc_wt_size() {
    WT_HEIGHT=17
    WT_WIDTH=$(tput cols)

    if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
        WT_WIDTH=80
    fi
    if [ "$WT_WIDTH" -gt 178 ]; then
        WT_WIDTH=120
    fi
    WT_MENU_HEIGHT=$((WT_HEIGHT-7))
    export WT_MENU_HEIGHT
}

# call like: download_script folder_variable name_of_script
# e.g. download_script MENU additional_apps
# Use it for functions like download_static_script
download_script() {
    rm -f "${SCRIPTS}/${2}.sh" "${SCRIPTS}/${2}.php" "${SCRIPTS}/${2}.py"
    if ! { curl_to_dir "${!1}" "${2}.sh" "$SCRIPTS" || curl_to_dir "${!1}" "${2}.php" "$SCRIPTS" || curl_to_dir "${!1}" "${2}.py" "$SCRIPTS"; }
    then
        print_text_in_color "$IRed" "{$2} failed to download."
        sleep 2
        if ! yesno_box_yes "Are you running the first setup of this server?"
        then
            msg_box "Please run sudo bash '$SCRIPTS/update.sh' \
from your CLI to get the latest scripts from Github, needed for a successful run."
        else
            msg_box "If you get this error when running the first setup script, \
then just re-run it with: 'sudo bash $SCRIPTS/wordpress-startup-script.sh' \
from your CLI, and all the scripts will be downloaded again.

If it still fails, please report this issue to: $ISSUES."
        fi
        exit 1
    fi
}

# call like: run_script folder_variable name_of_script
# e.g. run_script MENU additional_apps
# Use it for functions like run_script STATIC
run_script() {
    rm -f "${SCRIPTS}/${2}.sh" "${SCRIPTS}/${2}.php" "${SCRIPTS}/${2}.py"
    if download_script "${1}" "${2}"
    then
        if [ -f "${SCRIPTS}/${2}".sh ]
        then
            bash "${SCRIPTS}/${2}.sh"
            rm -f "${SCRIPTS}/${2}.sh"
        elif [ -f "${SCRIPTS}/${2}".php ]
        then
            php "${SCRIPTS}/${2}.php"
            rm -f "${SCRIPTS}/${2}.php"
        elif [ -f "${SCRIPTS}/${2}".py ]
        then
            install_if_not python3
            python3 "${SCRIPTS}/${2}.py"
            rm -f "${SCRIPTS}/${2}.py"
        fi
    else
        print_text_in_color "$IRed" "Running ${2} failed"
        print_text_in_color "$ICyan" "Script failed to execute. Please run: \
'sudo curl -sLO ${!1}/${2}.sh|php|py' and try again."
        exit 1
    fi
}

# Run any script in ../master
# call like: run_main_script name_of_script
run_main_script() {
run_script GITHUB_REPO "${1}"
}

# Backwards compatibility (2020-10-25)
run_static_script() {
run_script STATIC "${1}"
}

version(){
    local h t v

    [[ $2 = "$1" || $2 = "$3" ]] && return 0

    v=$(printf '%s\n' "$@" | sort -V)
    h=$(head -n1 <<<"$v")
    t=$(tail -n1 <<<"$v")

    [[ $2 != "$h" && $2 != "$t" ]]
}

version_gt() {
    local v1 v2 IFS=.
    read -ra v1 <<< "$1"
    read -ra v2 <<< "$2"
    printf -v v1 %03d "${v1[@]}"
    printf -v v2 %03d "${v2[@]}"
    [[ $v1 > $v2 ]]
}

spinner_loading() {
    pid=$!
    spin='-\|/'
    i=0
    while kill -0 $pid 2>/dev/null
    do
        i=$(( (i+1) %4 ))
        printf "\r[${spin:$i:1}] " # Add text here, something like "Please be paitent..." maybe?
        sleep .1
    done
}

any_key() {
    local PROMPT="$1"
    read -r -sn 1 -p "$(printf "%b" "${IGreen}${PROMPT}${Color_Off}")";echo
}

# Check universe reposiroty
check_universe() {
UNIV=$(apt-cache policy | grep http | awk '{print $3}' | grep universe | head -n 1 | cut -d "/" -f 2)
if [ "$UNIV" != "universe" ]
then
    print_text_in_color "$ICyan" "Adding required repo (universe)."
    add-apt-repository universe
fi
}

# Check universe reposiroty
check_multiverse() {
MULTIV=$(apt-cache policy | grep http | awk '{print $3}' | grep multiverse | head -n 1 | cut -d "/" -f 2)
if [ "$MULTIV" != "multiverse" ]
then
    print_text_in_color "$ICyan" "Adding required repo (multiverse)."
    add-apt-repository multiverse
fi
}

# countdown 'message looks like this' 10
countdown() {
print_text_in_color "$ICyan" "$1"
secs="$(($2))"
while [ $secs -gt 0 ]; do
   echo -ne "$secs\033[0K\r"
   sleep 1
   : $((secs--))
done
}

print_text_in_color() {
printf "%b%s%b\n" "$1" "$2" "$Color_Off"
}


# Check if the value is a number
# EXAMPLE: https://github.com/nextcloud/vm/pull/1012
check_if_number() {
case "${1}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
esac
}

# Use this to send system mails
# e.g.: send_mail "subject" "text"
send_mail() {
    local RECIPIENT
    if [ -f /etc/msmtprc ]
    then
        RECIPIENT=$(grep "recipient=" /etc/msmtprc)
        RECIPIENT="${RECIPIENT##*recipient=}"
        if [ -n "$RECIPIENT" ]
        then
            print_text_in_color "$ICyan" "Sending '$1' to $RECIPIENT"
            echo -e "$2" | mail --subject "NcVM - $1" "$RECIPIENT"
        fi
    fi
}

check_php() {
print_text_in_color "$ICyan" "Getting current PHP-version..."
GETPHP="$(php -v | grep -m 1 PHP | awk '{print $2}' | cut -d '-' -f1)"

if [ -z "$GETPHP" ]
then
    print_text_in_color "$IRed" "Can't find proper PHP version, aborting..."
    exit 1
fi

if grep 7.0 <<< "$GETPHP" >/dev/null 2>&1
then
   export PHPVER=7.0
elif grep 7.1 <<< "$GETPHP" >/dev/null 2>&1
then
   export PHPVER=7.1
elif grep 7.2 <<< "$GETPHP" >/dev/null 2>&1
then
   export PHPVER=7.2
elif grep 7.3 <<< "$GETPHP" >/dev/null 2>&1
then
   export PHPVER=7.3
elif grep 7.4 <<< "$GETPHP" >/dev/null 2>&1
then
   export PHPVER=7.4
elif grep 8.0 <<< "$GETPHP" >/dev/null 2>&1
then
#   export PHPVER=8.0
    msg_box "Sorry, but PHP 8 is not supported yet."
    exit 1
fi

export PHP_INI=/etc/php/"$PHPVER"/fpm/php.ini
export PHP_POOL_DIR=/etc/php/"$PHPVER"/fpm/pool.d

print_text_in_color "$IGreen" PHPVER="$PHPVER"
}

## bash colors
# Reset
Color_Off='\e[0m'       # Text Reset

# Regular Colors
Black='\e[0;30m'        # Black
Red='\e[0;31m'          # Red
Green='\e[0;32m'        # Green
Yellow='\e[0;33m'       # Yellow
Blue='\e[0;34m'         # Blue
Purple='\e[0;35m'       # Purple
Cyan='\e[0;36m'         # Cyan
White='\e[0;37m'        # White

# Bold
BBlack='\e[1;30m'       # Black
BRed='\e[1;31m'         # Red
BGreen='\e[1;32m'       # Green
BYellow='\e[1;33m'      # Yellow
BBlue='\e[1;34m'        # Blue
BPurple='\e[1;35m'      # Purple
BCyan='\e[1;36m'        # Cyan
BWhite='\e[1;37m'       # White

# Underline
UBlack='\e[4;30m'       # Black
URed='\e[4;31m'         # Red
UGreen='\e[4;32m'       # Green
UYellow='\e[4;33m'      # Yellow
UBlue='\e[4;34m'        # Blue
UPurple='\e[4;35m'      # Purple
UCyan='\e[4;36m'        # Cyan
UWhite='\e[4;37m'       # White

# Background
On_Black='\e[40m'       # Black
On_Red='\e[41m'         # Red
On_Green='\e[42m'       # Green
On_Yellow='\e[43m'      # Yellow
On_Blue='\e[44m'        # Blue
On_Purple='\e[45m'      # Purple
On_Cyan='\e[46m'        # Cyan
On_White='\e[47m'       # White

# High Intensity
IBlack='\e[0;90m'       # Black
IRed='\e[0;91m'         # Red
IGreen='\e[0;92m'       # Green
IYellow='\e[0;93m'      # Yellow
IBlue='\e[0;94m'        # Blue
IPurple='\e[0;95m'      # Purple
ICyan='\e[0;96m'        # Cyan
IWhite='\e[0;97m'       # White

# Bold High Intensity
BIBlack='\e[1;90m'      # Black
BIRed='\e[1;91m'        # Red
BIGreen='\e[1;92m'      # Green
BIYellow='\e[1;93m'     # Yellow
BIBlue='\e[1;94m'       # Blue
BIPurple='\e[1;95m'     # Purple
BICyan='\e[1;96m'       # Cyan
BIWhite='\e[1;97m'      # White

# High Intensity backgrounds
On_IBlack='\e[0;100m'   # Black
On_IRed='\e[0;101m'     # Red
On_IGreen='\e[0;102m'   # Green
On_IYellow='\e[0;103m'  # Yellow
On_IBlue='\e[0;104m'    # Blue
On_IPurple='\e[0;105m'  # Purple
On_ICyan='\e[0;106m'    # Cyan
On_IWhite='\e[0;107m'   # White
