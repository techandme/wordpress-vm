#!/bin/bash
# shellcheck disable=2034,2059
true
# see https://github.com/koalaman/shellcheck/wiki/Directive

## variables
# Dirs
SCRIPTS=/var/scripts
WWW_ROOT=/var/www/html
WPATH=$WWW_ROOT/wordpress
GPGDIR=/tmp/gpg

# Ubuntu OS
DISTRO=$(lsb_release -sd | cut -d ' ' -f 2)
OS=$(grep -ic "Ubuntu" /etc/issue.net)

# Network
[ -n "$FIRST_IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
IFACE2=$(ip -o link show | awk '{print $2,$9}' | grep 'UP' | cut -d ':' -f 1)
[ -n "$CHECK_CURRENT_REPO" ] && REPO=$(apt-get update | grep -m 1 Hit | awk '{ print $2}')
ADDRESS=$(hostname -I | cut -d ' ' -f 1)
WGET="/usr/bin/wget"
WANIP4=$(curl -s -m 5 ipinfo.io/ip)
[ -n "$LOAD_IP6" ] && WANIP6=$(curl -s -k -m 7 https://6.ifcfg.me)
IFCONFIG="/sbin/ifconfig"
INTERFACES="/etc/netplan/01-netcfg.yaml"
NETMASK=$($IFCONFIG | grep -w inet |grep -v 127.0.0.1| awk '{print $4}' | cut -d ":" -f 2)
GATEWAY=$(route -n|grep "UG"|grep -v "UGH"|cut -f 10 -d " ")
DNS1="9.9.9.9"
DNS2="149.112.112.112"

# Repo
GITHUB_REPO="https://raw.githubusercontent.com/techandme/wordpress-vm/master"
STATIC="$GITHUB_REPO/static"
LETS_ENC="$GITHUB_REPO/lets-encrypt"
ISSUES="https://github.com/techandme/wordpress-vm/issues"
APP="$GITHUB_REPO/apps"

# User information
WPDBNAME=wordpress_by_www_hanssonit_se
WPADMINUSER=change_this_user
UNIXUSER=$SUDO_USER
UNIXUSER_PROFILE="/home/$UNIXUSER/.bash_profile"
ROOT_PROFILE="/root/.bash_profile"

# PHP-FPM
PHPVER=7.2
PHP_INI=/etc/php/"$PHPVER"/fpm/php.ini
PHP_POOL_DIR=/etc/php/"$PHPVER"/fpm/pool.d
PHP_FPM_SOCK=/var/run/php"$PHPVER"-fpm-wordpress.sock

# MARIADB
SHUF=$(shuf -i 25-29 -n 1)
MARIADB_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
WPDBPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
NEWMARIADBPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
WPDBUSER=wordpress_user
WPADMINPASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$SHUF" | head -n 1)
[ -n "$WPDB" ] && WPCONFIGDB=$(grep "DB_PASSWORD" /var/www/html/wordpress/wp-config.php | awk '{print $3}' | cut -d "'" -f2)
MYCNF=/root/.my.cnf
[ -n "$MYCNFPW" ] && MARIADBMYCNFPASS=$(grep "password" $MYCNF | sed -n "/password/s/^password='\(.*\)'$/\1/p")
# Path to specific files
SECURE="$SCRIPTS/wp-permissions.sh"
SSL_CONF="/etc/nginx/sites-available/wordpress_port_443.conf"
HTTP_CONF="/etc/nginx/sites-available/wordpress_port_80.conf"
ETCMYCNF="/etc/mysql/my.cnf"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_DEF="/etc/nginx/sites-available/default"

# Letsencrypt
LETSENCRYPTPATH="/etc/letsencrypt"
CERTFILES="$LETSENCRYPTPATH/live"
DHPARAMS="$CERTFILES/$SUBDOMAIN/dhparam.pem"

# Adminer
ADMINERDIR=/usr/share/adminer
ADMINER_CONF=/etc/nginx/sites-available/adminer.conf

# Redis
REDIS_CONF=/etc/redis/redis.conf
REDIS_SOCK=/var/run/redis/redis-server.sock
RSHUF=$(shuf -i 30-35 -n 1)
REDIS_PASS=$(tr -dc "a-zA-Z0-9@#*=" < /dev/urandom | fold -w "$RSHUF" | head -n 1)
REDISPTXT=/tmp/redispasstxt

# Extra security
SPAMHAUS=/etc/spamhaus.wl
ENVASIVE=/etc/apache2/mods-available/mod-evasive.load
APACHE2=/etc/apache2/apache2.conf

## functions

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
   b) :~# $SCRIPTS/name-of-script.sh
In both cases above you can leave out $SCRIPTS/ if the script
is directly in your PATH.
More information can be found here: https://unix.stackexchange.com/a/3064"
    exit 1
fi
}

wp_cli_cmd() {
export WP_CLI_CACHE_DIR=$WPATH/.wp-cli/cache
check_command sudo -u www-data /usr/local/bin/wp "$@";
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
            print_text_in_color "$ICyan" "${PROCESS} is running. Waiting for it to stop..."
            sleep 10
    fi
done
}

debug_mode() {
if [ "$DEBUG" -eq 1 ]
then
    set -ex
fi
}

ask_yes_or_no() {
    read -r -p "$1 ([y]es or [N]o): "
    case ${REPLY,,} in
        y|yes)
            echo "yes"
        ;;
        *)
            echo "no"
        ;;
    esac
}

restart_webserver() {
check_command systemctl restart nginx
if php"$PHPVER"-fpm -v > /dev/null
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
    certbot --version
else
    print_text_in_color "$ICyan" "Installing certbot (Let's Encrypt)..."
    apt update -q4 & spinner_loading
    apt install software-properties-common
    add-apt-repository ppa:certbot/certbot -y
    apt update -q4 & spinner_loading
    apt install certbot -y -q
    apt update -q4 & spinner_loading
    apt dist-upgrade -y
fi
}

# Check if port is open # check_open_port 443 domain.example.com
check_open_port() {
print_text_in_color "${ICyan}" "Checking if port ${1} is open with https://ports.yougetsignal.com..."
install_if_not curl
# WAN Adress
if check_command curl -s -H 'Cache-Control: no-cache' 'https://ports.yougetsignal.com/check-port.php' --data "remoteAddress=${WANIP4}&portNumber=${1}" | grep -q "is open on"
then
    print_text_in_color "${IGreen}" "Port ${1} is open on ${WANIP4}!"
# Domain name
elif check_command curl -s -H 'Cache-Control: no-cache' 'https://ports.yougetsignal.com/check-port.php' --data "remoteAddress=${2}&portNumber=${1}" | grep -q "is open on"
then
    print_text_in_color "${IGreen}" "Port ${1} is open on ${2}!"
else
    msg_box "Port $1 is not open on either ${WANIP4} or ${2}.\n\nPlease follow this guide to open ports in your router or firewall:\nhttps://www.techandme.se/open-port-80-443/"
    any_key "Press any key to exit..."
    exit 1
fi
}

msg_box() {
local PROMPT="$1"
    whiptail --msgbox "${PROMPT}" "$WT_HEIGHT" "$WT_WIDTH"
}

# Check if program is installed (stop_if_installed apache2)
stop_if_installed() {
if [ "$(dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    print_text_in_color "$IRed" "${1} is installed, it must be a clean server."
    exit 1
fi
}

# Check if program is installed (is_this_installed apache2)
is_this_installed() {
if dpkg-query -W -f='${Status}' "${1}" | grep -q "ok installed"
then
    return 0
else
    return 1
fi
}

# Install_if_not program
install_if_not () {
if [[ "$(stop_if_installed "${1}")" != "${1} is installed, it must be a clean server." ]]
then
    apt update -q4 & spinner_loading && apt install "${1}" -y
fi
}

test_connection() {
install_if_not dnsutils
install_if_not network-manager
check_command service network-manager restart
ip link set "$IFACE" down
wait
ip link set "$IFACE" up
wait
check_command service network-manager restart
print_text_in_color "$ICyan" "Checking connection..."
sleep 3
if ! nslookup github.com
then
msg_box "Network NOT OK. You must have a working network connection to run this script
If you think that this is a bug, please report it to https://github.com/nextcloud/vm/issues."
    exit 1
fi
}

# Test RAM size
# Call it like this: ram_check [amount of min RAM in GB] [for which program]
# Example: ram_check 2 Wordpress
ram_check() {
mem_available="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
if [ "${mem_available}" -lt "$((${1}*1002400))" ]
then
    print_text_in_color "${Red}" "Error: ${1} GB RAM required to install ${2}!" >&2
    print_text_in_color "${Red}" "Current RAM is: ("$((mem_available/1002400))" GB)" >&2
    sleep 3
    msg_box "If you want to bypass this check you could do so by commenting out (# before the line) 'ram_check X' in the script that you are trying to run.
    In nextcloud_install_production.sh you can find the check somewhere around line #34.
    Please notice that things may be veery slow and not work as expeced. YOU HAVE BEEN WARNED!"
    exit 1
else
    print_text_in_color "${IGreen}" "RAM for ${2} OK! ($((mem_available/1002400)) GB)"
fi
}

# Test number of CPU
# Call it like this: cpu_check [amount of min CPU] [for which program]
# Example: cpu_check 2 Wordpress
cpu_check() {
nr_cpu="$(nproc)"
if [ "${nr_cpu}" -lt "${1}" ]
then
    print_text_in_color "${Red}" "Error: ${1} CPU required to install ${2}!" >&2
    print_text_in_color "${Red}" "Current CPU: ($((nr_cpu)))" >&2
    sleep 3
    exit 1
else
    print_text_in_color "${IGreen}" "CPU for ${2} OK! ($((nr_cpu)))"
fi
}

check_command() {
  if ! "$@";
  then
     print_text_in_color "${Red}" "Sorry but something went wrong. Please report this issue to $ISSUES and include the output of the error message. Thank you!"
     print_text_in_color "$IRed" "$* failed"
    exit 1
  fi
}

network_ok() {
    print_text_in_color "$ICyan" "Testing if network is OK..."
    install_if_not network-manager
    if ! service network-manager restart > /dev/null
    then
        service networking restart > /dev/null
    fi
    sleep 2
    if wget -q -T 20 -t 2 http://github.com -O /dev/null & spinner_loading
    then
        return 0
    else
        return 1
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

# Initial download of script in ../static
# call like: download_static_script name_of_script
download_static_script() {
    # Get ${1} script
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if ! { wget -q "${STATIC}/${1}.sh" -P "$SCRIPTS" || wget -q "${STATIC}/${1}.php" -P "$SCRIPTS" || wget -q "${STATIC}/${1}.py" -P "$SCRIPTS"; }
    then
        print_text_in_color "$IRed" "{$1} failed to download. Please run: 'sudo wget ${STATIC}/${1}.sh|.php|.py' again."
        print_text_in_color "$IRed" "If you get this error when running the wordpress-startup-script then just re-run it with:"
        print_text_in_color "$IRed" "'sudo bash $SCRIPTS/wordpress-startup-script.sh' and all the scripts will be downloaded again"
        exit 1
    fi
}

# Initial download of script in ../lets-encrypt
# call like: download_le_script name_of_script
download_le_script() {
    # Get ${1} script
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if ! { wget -q "${LETS_ENC}/${1}.sh" -P "$SCRIPTS" || wget -q "${LETS_ENC}/${1}.php" -P "$SCRIPTS" || wget -q "${LETS_ENC}/${1}.py" -P "$SCRIPTS"; }
    then
        print_text_in_color "$IRed" "{$1} failed to download. Please run: 'sudo wget ${STATIC}/${1}.sh|.php|.py' again."
        print_text_in_color "$IRed" "If you get this error when running the wordpress-startup-script then just re-run it with:"
        print_text_in_color "$IRed" "'sudo bash $SCRIPTS/wordpress-startup-script.sh' and all the scripts will be downloaded again"
        exit 1
    fi
}

# Run any script in ../master
# call like: run_main_script name_of_script
run_main_script() {
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if wget -q "${GITHUB_REPO}/${1}.sh" -P "$SCRIPTS"
    then
        bash "${SCRIPTS}/${1}.sh"
        rm -f "${SCRIPTS}/${1}.sh"
    elif wget -q "${GITHUB_REPO}/${1}.php" -P "$SCRIPTS"
    then
        php "${SCRIPTS}/${1}.php"
        rm -f "${SCRIPTS}/${1}.php"
    elif wget -q "${GITHUB_REPO}/${1}.py" -P "$SCRIPTS"
    then
        python "${SCRIPTS}/${1}.py"
        rm -f "${SCRIPTS}/${1}.py"
    else
        print_text_in_color "$IRed" "Downloading ${1} failed"
        print_text_in_color "$IRed" "Script failed to download. Please run: 'sudo wget ${GITHUB_REPO}/${1}.sh|php|py' again."
        sleep 3
    fi
}

# Run any script in ../static
# call like: run_static_script name_of_script
run_static_script() {
    # Get ${1} script
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if wget -q "${STATIC}/${1}.sh" -P "$SCRIPTS"
    then
        bash "${SCRIPTS}/${1}.sh"
        rm -f "${SCRIPTS}/${1}.sh"
    elif wget -q "${STATIC}/${1}.php" -P "$SCRIPTS"
    then
        php "${SCRIPTS}/${1}.php"
        rm -f "${SCRIPTS}/${1}.php"
    elif wget -q "${STATIC}/${1}.py" -P "$SCRIPTS"
    then
        python "${SCRIPTS}/${1}.py"
        rm -f "${SCRIPTS}/${1}.py"
    else
        print_text_in_color "$IRed" "Downloading ${1} failed"
        print_text_in_color "$IRed" "Script failed to download. Please run: 'sudo wget ${STATIC}/${1}.sh|php|py' again."
        sleep 3
    fi
}

# Run any script in ../apps
# call like: run_app_script collabora|nextant|passman|spreedme|contacts|calendar|webmin|previewgenerator
run_app_script() {
    rm -f "${SCRIPTS}/${1}.sh" "${SCRIPTS}/${1}.php" "${SCRIPTS}/${1}.py"
    if wget -q "${APP}/${1}.sh" -P "$SCRIPTS"
    then
        bash "${SCRIPTS}/${1}.sh"
        rm -f "${SCRIPTS}/${1}.sh"
    elif wget -q "${APP}/${1}.php" -P "$SCRIPTS"
    then
        php "${SCRIPTS}/${1}.php"
        rm -f "${SCRIPTS}/${1}.php"
    elif wget -q "${APP}/${1}.py" -P "$SCRIPTS"
    then
        python "${SCRIPTS}/${1}.py"
        rm -f "${SCRIPTS}/${1}.py"
    else
        print_text_in_color "$IRed" "Downloading ${1} failed"
        print_text_in_color "$IRed" "Script failed to download. Please run: 'sudo wget ${APP}/${1}.sh|php|py' again."
        sleep 3
    fi
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
    read -r -p "$(printf "${Green}${PROMPT}${Color_Off}")" -n1 -s
    echo
}

print_text_in_color() {
	printf "%b%s%b\n" "$1" "$2" "$Color_Off"
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
