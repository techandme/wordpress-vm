#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# Prefer IPv4 for apt
echo 'Acquire::ForceIPv4 "true";' >> /etc/apt/apt.conf.d/99force-ipv4

# Install curl if not existing
if [ "$(dpkg-query -W -f='${Status}' "curl" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    echo "curl OK"
else
    apt update -q4
    apt install curl -y
fi

# shellcheck disable=2034,2059
true
SCRIPT_NAME="Wordpress Install Script"
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/20.04_testing/lib.sh)

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# Install lshw if not existing
if [ "$(dpkg-query -W -f='${Status}' "lshw" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    print_text_in_color "$IGreen" "lshw OK"
else
    apt update -q4 & spinner_loading
    apt install lshw -y
fi

# Install net-tools if not existing
if [ "$(dpkg-query -W -f='${Status}' "net-tools" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    print_text_in_color "$IGreen" "net-tools OK"
else
    apt update -q4 & spinner_loading
    apt install net-tools -y
fi

# Install whiptail if not existing
if [ "$(dpkg-query -W -f='${Status}' "whiptail" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    print_text_in_color "$IGreen" "whiptail OK"
else
    apt update -q4 & spinner_loading
    apt install whiptail -y
fi

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/20.04_testing/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Test RAM size (2GB min) + CPUs (min 1)
ram_check 2 Wordpress
cpu_check 1 Wordpress

# Download needed libraries before execution of the first script
mkdir -p "$SCRIPTS"
download_script GITHUB_REPO lib
download_script STATIC fetch_lib

# Set locales
run_script ADDONS locales

# Create new current user
download_script STATIC adduser
bash $SCRIPTS/adduser.sh "wordpress_install.sh"
rm -f $SCRIPTS/adduser.sh

# Check distribution and version
if ! version 20.04 "$DISTRO" 20.04.6
then
    msg_box "This script can only be run on Ubuntu 20.04 (server)."
    exit 1
fi
# Use this when Ubuntu 18.04 is deprecated from the function:
#check_distro_version
check_universe
check_multiverse

# Fix LVM on BASE image
if grep -q "LVM" /etc/fstab
then
    if yesno_box_yes "Do you want to make all free space available to your root partition?"
    then
    # Resize LVM (live installer is &%¤%/!
    # VM
    print_text_in_color "$ICyan" "Extending LVM, this may take a long time..."
    lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

    # Run it again manually just to be sure it's done
    while :
    do
        lvdisplay | grep "Size" | awk '{print $3}'
        if ! lvextend -L +10G /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
        then
            if ! lvextend -L +1G /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
            then
                if ! lvextend -L +100M /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
                then
                    if ! lvextend -L +1M /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
                    then
                        resize2fs /dev/ubuntu-vg/ubuntu-lv
                        break
                    fi
                fi
            fi
        fi
    done
    fi
fi

# Check if it's a clean server
stop_if_installed postgresql
stop_if_installed apache2
stop_if_installed nginx
stop_if_installed php
stop_if_installed php-fpm
stop_if_installed php"$PHPVER"-fpm
stop_if_installed php7.0-fpm
stop_if_installed php7.1-fpm
stop_if_installed php7.2-fpm
stop_if_installed php7.3-fpm
stop_if_installed mysql-common
stop_if_installed mariadb-server

# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi

# Create $VMLOGS dir
if [ ! -d "$VMLOGS" ]
then
    mkdir -p "$VMLOGS"
fi

# Install needed network
install_if_not netplan.io

# Install build-essentials to get make
install_if_not build-essential

# Set DNS resolver
# https://unix.stackexchange.com/questions/442598/how-to-configure-systemd-resolved-and-systemd-networkd-to-use-local-dns-server-f    
while :
do
choice=$(whiptail --title "$TITLE - Set DNS Resolver" --menu \
"Which DNS provider should this Wordpress server use?
$MENU_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Quad9" "(https://www.quad9.net/)" \
"Cloudflare" "(https://www.cloudflare.com/dns/)" \
"Local" "($GATEWAY) - DNS on gateway" 3>&1 1>&2 2>&3)

    case "$choice" in
        "Quad9")
            sed -i "s|^#\?DNS=.*$|DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9|g" /etc/systemd/resolved.conf
        ;;
        "Cloudflare")
            sed -i "s|^#\?DNS=.*$|DNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001|g" /etc/systemd/resolved.conf
        ;;
        "Local")
            sed -i "s|^#\?DNS=.*$|DNS=$GATEWAY|g" /etc/systemd/resolved.conf
            if network_ok
            then
                break
            else
                msg_box "Could not validate the local DNS server. Pick an Internet DNS server and try again."
                continue
            fi
        ;;
        *)
        ;;
    esac
    if test_connection
    then
        break
    else
        msg_box "Could not validate the DNS server. Please try again."
    fi
done

# Install dependencies for GEO-block in Nginx
# TODO: https://linuxhint.com/nginx_block_geo_location/
#install_if_not geoip-database
#install_if_not libgeoip1

# Write MARIADB pass to file and keep it safe
{
echo "[client]"
echo "password='$MARIADB_PASS'"
} > "$MYCNF"
chmod 0600 $MYCNF
chown root:root $MYCNF

# Install MARIADB
install_if_not software-properties-common
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-10.5" --skip-maxscale
sudo debconf-set-selections <<< "mariadb-server-10.5 mysql-server/root_password password $MARIADB_PASS"
sudo debconf-set-selections <<< "mariadb-server-10.5 mysql-server/root_password_again password $MARIADB_PASS"
apt update -q4 & spinner_loading
install_if_not mariadb-server-10.5

# Prepare for Wordpress installation
# https://blog.v-gar.de/2017/02/en-solved-error-1698-28000-in-mysqlmariadb/
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET plugin='' WHERE user='root';"
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET password=PASSWORD('$MARIADB_PASS') WHERE user='root';"
mysql -u root -p"$MARIADB_PASS" -e "flush privileges;"

# mysql_secure_installation
install_if_not expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MARIADB_PASS\r\"
expect \"Switch to unix_socket authentication?\"
send \"y\r\"
expect \"Change the root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"
apt -y purge expect

# Write a new MariaDB config
run_script STATIC new_etc_mycnf

# Install VM-tools
install_if_not open-vm-tools

# Install Nginx
check_command yes | add-apt-repository ppa:nginx/stable
apt update -q4 && spinner_loading
install_if_not nginx
sudo systemctl stop nginx.service
sudo systemctl start nginx.service
sudo systemctl enable nginx.service

# Download TLSv 1.3 modified nginx.conf
rm -f /etc/nginx/nginx.conf
curl_to_dir $STATIC nginx.conf /etc/nginx/

# Install PHP 7.4
apt install -y \
        php \
	php"$PHPVER"-fpm \
	php"$PHPVER"-common \
	php"$PHPVER"-mbstring \
	php"$PHPVER"-xmlrpc \
	php"$PHPVER"-gd \
	php"$PHPVER"-xml \
	php"$PHPVER"-mysql \
	php"$PHPVER"-cli \
	php"$PHPVER"-zip \
	php"$PHPVER"-curl

# Configure PHP
sed -i "s|allow_url_fopen =.*|allow_url_fopen = On|g" "$PHP_INI"
sed -i "s|max_execution_time =.*|max_execution_time = 360|g" "$PHP_INI"
sed -i "s|file_uploads =.*|file_uploads = On|g" "$PHP_INI"
sed -i "s|upload_max_filesize =.*|upload_max_filesize = 100M|g" "$PHP_INI"
sed -i "s|memory_limit =.*|memory_limit = 256M|g" "$PHP_INI"
sed -i "s|post_max_size =.*|post_max_size = 110M|g" "$PHP_INI"
sed -i "s|cgi.fix_pathinfo =.*|cgi.fix_pathinfo=0|g" "$PHP_INI"
sed -i "s|date.timezone =.*|date.timezone = Europe/Stockholm|g" "$PHP_INI"

# Enable OPCache for PHP
phpenmod opcache
{
echo "# OPcache settings for Wordpress"
echo "opcache.enable=1"
echo "opcache.enable_cli=1"
echo "opcache.interned_strings_buffer=8"
echo "opcache.max_accelerated_files=10000"
echo "opcache.memory_consumption=256"
echo "opcache.save_comments=1"
echo "opcache.revalidate_freq=1"
echo "opcache.validate_timestamps=1"
} >> "$PHP_INI"

# PHP-FPM optimization
# https://geekflare.com/php-fpm-optimization/
sed -i "s|;emergency_restart_threshold.*|emergency_restart_threshold = 10|g" /etc/php/"$PHPVER"/fpm/php-fpm.conf
sed -i "s|;emergency_restart_interval.*|emergency_restart_interval = 1m|g" /etc/php/"$PHPVER"/fpm/php-fpm.conf
sed -i "s|;process_control_timeout.*|process_control_timeout = 10|g" /etc/php/"$PHPVER"/fpm/php-fpm.conf

# Make sure the passwords are the same, this file will be deleted when redis is run.
check_command echo "$REDIS_PASS" > $REDISPTXT

# Install Redis (distrubuted cache)
run_script ADDONS redis-server-ubuntu

# Enable igbinary for PHP
# https://github.com/igbinary/igbinary
if is_this_installed "php$PHPVER"-dev
then
    if ! yes no | pecl install -Z igbinary
    then
        msg_box "igbinary PHP module installation failed"
        exit
    else
        print_text_in_color "$IGreen" "igbinary PHP module installation OK!"
    fi
{
echo "# igbinary for PHP"
echo "extension=igbinary.so"
echo "session.serialize_handler=igbinary"
echo "igbinary.compact_strings=On"
} >> "$PHP_INI"
restart_webserver
fi

# APCu (local cache)
if is_this_installed "php$PHPVER"-dev
then
    if ! yes no | pecl install -Z apcu
    then
        msg_box "APCu PHP module installation failed"
        exit
    else
        print_text_in_color "$IGreen" "APCu PHP module installation OK!"
    fi
{
echo "# APCu settings for Wordpress"
echo "extension=apcu.so"
echo "apc.enabled=1"
echo "apc.max_file_size=5M"
echo "apc.shm_segments=1"
echo "apc.shm_size=128M"
echo "apc.entries_hint=4096"
echo "apc.ttl=3600"
echo "apc.gc_ttl=7200"
echo "apc.mmap_file_mask=NULL"
echo "apc.slam_defense=1"
echo "apc.enable_cli=1"
echo "apc.use_request_time=1"
echo "apc.serializer=igbinary"
echo "apc.coredump_unmap=0"
echo "apc.preload_path"
} >> "$PHP_INI"
restart_webserver
fi

# Download wp-cli.phar to be able to install Wordpress
check_command curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Add www-data in sudoers
{
echo "# WP-CLI" 
echo "$UNIXUSER ALL=(www-data) NOPASSWD: /usr/local/bin/wp"
echo "root ALL=(www-data) NOPASSWD: /usr/local/bin/wp"
} >> /etc/sudoers

# Create dir
mkdir -p "$WPATH"
chown -R www-data:www-data "$WPATH"
if [ ! -d /home/"$UNIXUSER"/.wp-cli ]
then
    mkdir -p /home/"$UNIXUSER"/.wp-cli/
    chown -R www-data:www-data /home/"$UNIXUSER"/.wp-cli/
fi

# Create wp-cli.yml
touch $WPATH/wp-cli.yml
cat << YML_CREATE > "$WPATH/wp-cli.yml"
nginx_modules:
  - mod_rewrite
YML_CREATE

# Show info about wp-cli
wp_cli_cmd --info

# Download Wordpress
cd "$WPATH"
check_command wp_cli_cmd core download --force --debug --path="$WPATH"

# Populate DB
mysql -uroot -p"$MARIADB_PASS" <<MYSQL_SCRIPT
CREATE DATABASE $WPDBNAME;
CREATE USER '$WPDBUSER'@'localhost' IDENTIFIED BY '$WPDBPASS';
GRANT ALL PRIVILEGES ON $WPDBNAME.* TO '$WPDBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
wp_cli_cmd core config --dbname=$WPDBNAME --dbuser=$WPDBUSER --dbpass="$WPDBPASS" --dbhost=localhost --extra-php <<PHP
/** REDIS PASSWORD */
define( 'WP_REDIS_PASSWORD', '$REDIS_PASS' );
/** REDIS CLIENT */
define( 'WP_REDIS_CLIENT', 'phpredis' );
/** REDIS SOCKET */
define( 'WP_REDIS_SCHEME', 'unix' );
/** REDIS PATH TO SOCKET */
define( 'WP_REDIS_PATH', '$REDIS_SOCK' );
/** REDIS TTL */
define('WP_REDIS_MAXTTL', 9600 );
/** REDIS SALT */
define('WP_REDIS_PREFIX', '$(gen_passwd "$SHUF" "a-zA-Z0-9@#*=")' );

/** AUTO UPDATE */
define( 'WP_AUTO_UPDATE_CORE', true );

/** WP DEBUG? */
define( 'WP_DEBUG', false );

/** WP MEMORY SETTINGS*/
define( 'WP_MEMORY_LIMIT', '128M' );
PHP

# Install Wordpress
check_command wp_cli_cmd core install --url=http://"$ADDRESS"/ --title=Wordpress --admin_user=$WPADMINUSER --admin_password="$WPADMINPASS" --admin_email=no-reply@hanssonit.se --skip-email
echo "WP PASS: $WPADMINPASS" > /var/adminpass.txt
chown wordpress:wordpress /var/adminpass.txt

# Create welcome post
curl_to_dir "$STATIC" welcome.txt "$SCRIPTS"
sed -i "s|wordpress_user_login|$WPADMINUSER|g" "$SCRIPTS"/welcome.txt
sed -i "s|wordpress_password_login|$WPADMINPASS|g" "$SCRIPTS"/welcome.txt
wp_cli_cmd post create ./welcome.txt --post_title='T&M Hansson IT AB - Welcome' --post_status=publish --path=$WPATH
rm -f "$SCRIPTS"/welcome.txt
wp_cli_cmd post delete 1 --force

# Show version
wp_cli_cmd core version
sleep 3

# Install Apps
wp_cli_cmd plugin install twitter-tweets --activate
wp_cli_cmd plugin install social-pug --activate
wp_cli_cmd plugin install wp-mail-smtp --activate
wp_cli_cmd plugin install google-captcha --activate
wp_cli_cmd plugin install redis-cache --activate

# set pretty urls
wp_cli_cmd rewrite structure '/%postname%/' --hard
wp_cli_cmd rewrite flush --hard

# delete akismet and hello dolly
wp_cli_cmd plugin delete akismet
wp_cli_cmd plugin delete hello

# Secure permissions
run_script STATIC wp-permissions

# Hardening security
# create .htaccess to protect uploads directory
cat > $WPATH/wp-content/uploads/.htaccess <<'EOL'
# Protect this file
<Files .htaccess>
Order Deny,Allow
Deny from All
</Files>
# whitelist file extensions to prevent executables being
# accessed if they get uploaded
order deny,allow
deny from all
<Files ~ ".(docx?|xlsx?|pptx?|txt|pdf|xml|css|jpe?g|png|gif)$">
allow from all
</Files>
EOL

# Secure wp-includes
# https://wordpress.org/support/article/hardening-wordpress/#securing-wp-includes
{
echo "# Block wp-includes folder and files"
echo "<IfModule mod_rewrite.c>"
echo "RewriteEngine On"
echo "RewriteBase /"
echo "RewriteRule ^wp-admin/includes/ - [F,L]"
echo "RewriteRule !^wp-includes/ - [S=3]"
echo "RewriteRule ^wp-includes/[^/]+\.php$ - [F,L]"
echo "RewriteRule ^wp-includes/js/tinymce/langs/.+\.php - [F,L]"
echo "RewriteRule ^wp-includes/theme-compat/ - [F,L]"
echo "# RewriteRule ^wp-includes/* - [F,L]" # Block EVERYTHING
echo "</IfModule>"
} >> $WPATH/.htaccess

# Set up a php-fpm pool with a unixsocket
cat << POOL_CONF > "$PHP_POOL_DIR"/wordpress.conf
[Wordpress]
user = www-data
group = www-data
listen = $PHP_FPM_SOCK
listen.owner = www-data
listen.group = www-data
pm = dynamic
; max_children is set dynamically with calculate_php_fpm()
pm.max_children = 22
pm.start_servers = 9
pm.min_spare_servers = 2
pm.max_spare_servers = 11
env[HOSTNAME] = $(hostname -f)
env[PATH] = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
security.limit_extensions = .php
php_admin_value [cgi.fix_pathinfo] = 1

; Optional
; pm.max_requests = 2000
POOL_CONF

# Disable the idling example pool.
mv "$PHP_POOL_DIR"/www.conf "$PHP_POOL_DIR"/www.conf.backup

# Enable the new php-fpm config
restart_webserver

# Force wp-cron.php (updates WooCommerce Services and run Scheluded Tasks)
if [ -f $WPATH/wp-cron.php ]
then
    chmod +x $WPATH/wp-cron.php
    crontab -u www-data -l | { cat; echo "14 */1 * * * php -f $WPATH/wp-cron.php > /dev/null 2>&1"; } | crontab -u www-data -
fi

# Install Figlet
install_if_not figlet

# Generate $SSL_CONF
install_if_not ssl-cert
systemctl stop nginx.service && wait
if [ ! -f $SITES_AVAILABLE/$TLS_CONF ]
then
    touch "$SITES_AVAILABLE/$TLS_CONF"
    cat << TLS_CREATE > "$SITES_AVAILABLE/$TLS_CONF"
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    ## Your website name goes here.
    # server_name example.com;
    ## Your only path reference.
    root $WPATH;
    ## This should be in your http block and if it is, it's not needed here.
    index index.php;

    resolver $GATEWAY;

     ## Show real IP behind proxy (change to the proxy IP)
#    set_real_ip_from  $GATEWAY/24;
#    set_real_ip_from  $GATEWAY;
#    set_real_ip_from  2001:0db8::/32;
#    real_ip_header    X-Forwarded-For;
#    real_ip_recursive on;

    # certs sent to the client in SERVER HELLO are concatenated in ssl_certificate
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Diffie-Hellman parameter for DHE ciphersuites, recommended 4096 bits
    # ssl_dhparam /path/to/dhparam.pem;

    # intermediate configuration. tweak to your needs.
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
    ssl_prefer_server_ciphers on;

    # HSTS (ngx_http_headers_module is required) (15768000 seconds = 6 months)
    add_header Strict-Transport-Security max-age=15768000;

    # OCSP Stapling ---
    # fetch OCSP records from URL in ssl_certificate and cache them
    ssl_stapling on;
    ssl_stapling_verify on;

    ## verify chain of trust of OCSP response using Root CA and Intermediate certs
    # ssl_trusted_certificate /path/to/root_CA_cert_plus_intermediates;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ /\\. {
        access_log off;
        log_not_found off;
        deny all;
    }

    location = /favicon.ico {
                log_not_found off;
                access_log off;
    }

    location = /robots.txt {
                allow all;
                log_not_found off;
                access_log off;
    }

    location ~* \.php$ {
        location ~ \wp-login.php$ {
                    allow $GATEWAY/24;
		    #allow $ADDRESS;
		    #allow $WAN4IP;
                    deny all;
                    include fastcgi.conf;
                    fastcgi_intercept_errors on;
                    fastcgi_pass unix:$PHP_FPM_SOCK;
        }
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                try_files \$uri =404;
                fastcgi_index index.php;
                include fastcgi.conf;
                include fastcgi_params;
                fastcgi_intercept_errors on;
                fastcgi_pass unix:$PHP_FPM_SOCK;
                fastcgi_buffers 16 16k;
                fastcgi_buffer_size 32k;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
     }

     location ~* \\.(js|css|png|jpg|jpeg|gif|ico)$ {
                expires max;
                log_not_found off;
     }
}
TLS_CREATE
print_text_in_color "$IGreen" "$TLS_CONF was successfully created"
sleep 1
fi

# Generate $HTTP_CONF
if [ ! -f $SITES_AVAILABLE/$HTTP_CONF ]
then
    touch "$SITES_AVAILABLE/$HTTP_CONF"
    cat << HTTP_CREATE > "$SITES_AVAILABLE/$HTTP_CONF"
server {
    listen 80;
    listen [::]:80;

    ## Your website name goes here.
    # server_name example.com;
    ## Your only path reference.
    root $WPATH;
    ## This should be in your http block and if it is, it's not needed here.
    index index.php;

    resolver $GATEWAY;

    ## Show real IP behind proxy (change to the proxy IP)
#    set_real_ip_from  $GATEWAY/24;
#    set_real_ip_from  $GATEWAY;
#    set_real_ip_from  2001:0db8::/32;
#    real_ip_header    X-Forwarded-For;
#    real_ip_recursive on;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ /\\. {
        access_log off;
        log_not_found off;
        deny all;
    }

    location = /favicon.ico {
                log_not_found off;
                access_log off;
    }

    location = /robots.txt {
                allow all;
                log_not_found off;
                access_log off;
    }

    location ~* \.php$ {
        location ~ \wp-login.php$ {
                    allow $GATEWAY/24;
		    #allow $ADDRESS;
		    #allow $WAN4IP;
                    deny all;
                    include fastcgi.conf;
                    fastcgi_intercept_errors on;
                    fastcgi_pass unix:$PHP_FPM_SOCK;
        }
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                try_files \$uri =404;
                fastcgi_index index.php;
                include fastcgi.conf;
                include fastcgi_params;
                fastcgi_intercept_errors on;
                fastcgi_pass unix:$PHP_FPM_SOCK;
                fastcgi_buffers 16 16k;
                fastcgi_buffer_size 32k;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
     }

     location ~* \\.(js|css|png|jpg|jpeg|gif|ico)$ {
                expires max;
                log_not_found off;
     }
}
HTTP_CREATE
print_text_in_color "$IGreen" "$HTTP_CONF was successfully created"
sleep 1
fi

# Generate $NGINX_CONF
if [ -f $NGINX_CONF ];
        then
        rm $NGINX_CONF
	touch $NGINX_CONF
        cat << NGINX_CREATE > $NGINX_CONF
user www-data;
worker_processes 2;
pid /run/nginx.pid;

	worker_rlimit_nofile 10240;

events {
	worker_connections 10240;
	multi_accept on;
	use epoll;
}

http {

	##
	# Basic Settings
	##

	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	server_tokens off;
	client_body_timeout   10;
	client_header_timeout 10;
	client_header_buffer_size 128;
        client_max_body_size 10M;
	# server_names_hash_bucket_size 64;
	# server_name_in_redirect off;

	include /etc/nginx/mime.types;
	default_type application/octet-stream;

	##
	# SSL Settings
	##

	ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
	ssl_prefer_server_ciphers on;

	##
	# Logging Settings
	##

	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;

	##
	# Gzip Settings
	##

	gzip on;
	gzip_disable "msie6";

	# gzip_vary on;
	# gzip_proxied any;
	# gzip_comp_level 6;
	  gzip_buffers 16 4k;
	# gzip_http_version 1.1;
	# gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

	##
	# Virtual Host Configs
	##

	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;

	upstream php {
        server unix:/run/php/php"$PHPVER"-fpm.sock;
        }
}

#mail {
#	# See sample authentication script at:
#	# http://wiki.nginx.org/ImapAuthenticateWithApachePhpScript
#
#	# auth_http localhost/auth.php;
#	# pop3_capabilities "TOP" "USER";
#	# imap_capabilities "IMAP4rev1" "UIDPLUS";
#
#	server {
#		listen     localhost:110;
#		protocol   pop3;
#		proxy      on;
#	}
#
#	server {
#		listen     localhost:143;
#		protocol   imap;
#		proxy      on;
#	}
#}
NGINX_CREATE
print_text_in_color "$IGreen" "$NGINX_CONF was successfully created"
sleep 1
fi

# Generate $NGINX_CONF
if [ -f "$NGINX_DEF" ];
then
    rm -f $NGINX_DEF
    rm -f "$SITES_ENABLED"/default
    touch $NGINX_DEF
    cat << NGINX_DEFAULT > "$NGINX_DEF"
##
# You should look at the following URL's in order to grasp a solid understanding
# of Nginx configuration files in order to fully unleash the power of Nginx.
# http://wiki.nginx.org/Pitfalls
# http://wiki.nginx.org/QuickStart
# http://wiki.nginx.org/Configuration
#
# Generally, you will want to move this file somewhere, and start with a clean
# file but keep this around for reference. Or just disable in sites-enabled.
#
# Please see /usr/share/doc/nginx-doc/examples/ for more detailed examples.
##

# Default server configuration
#
server {
	listen 80 default_server;
	listen [::]:80 default_server;


# Let's Encrypt
        location ~ /.well-known {
	root /usr/share/nginx/html;

	        allow all;
	}

	# SSL configuration
	#
	# listen 443 ssl default_server;
	# listen [::]:443 ssl default_server;
	#
	# Note: You should disable gzip for SSL traffic.
	# See: https://bugs.debian.org/773332
	#
	# Read up on ssl_ciphers to ensure a secure configuration.
	# See: https://bugs.debian.org/765782
	#
	# Self signed certs generated by the ssl-cert package
	# Don't use them in a production server!
	#
	# include snippets/snakeoil.conf;

	root $WWW_ROOT;

	# Add index.php to the list if you are using PHP
	index index.html index.htm index.nginx-debian.html;

	server_name _;

	location / {
		# First attempt to serve request as file, then
		# as directory, then fall back to displaying a 404.
		try_files \$uri \$uri/ =404;
	}
}
NGINX_DEFAULT
print_text_in_color "$IGreen" "$NGINX_DEF was successfully created"
sleep 1
fi

# Enable new config
ln -s "$NGINX_DEF" "$SITES_ENABLED"/default
ln -s "$SITES_AVAILABLE"/"$TLS_CONF" "$SITES_ENABLED"/"$TLS_CONF"
ln -s "$SITES_AVAILABLE"/"$HTTP_CONF" "$SITES_ENABLED"/"$HTTP_CONF"
restart_webserver

# Enable UTF8mb4 (4-byte support)
databases=$(mysql -u root -p"$MARIADB_PASS" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in $databases; do
    if [[ "$db" != "performance_schema" ]] && [[ "$db" != _* ]] && [[ "$db" != "information_schema" ]];
    then
        print_text_in_color "$ICyan" "Changing to UTF8mb4 on: $db"
        mysql -u root -p"$MARIADB_PASS" -e "ALTER DATABASE $db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    fi
done

# Put IP adress in /etc/issue (shown before the login)
if [ -f /etc/issue ]
then
    echo "\4" >> /etc/issue
fi

# Force MOTD to show correct number of updates
if is_this_installed update-notifier-common
then
    sudo /usr/lib/update-notifier/update-motd-updates-available --force
fi

# It has to be this order:
# Download scripts
# chmod +x
# Set permissions for ncadmin in the change scripts

# Get needed scripts for first bootup
download_script GITHUB_REPO wordpress-startup-script
download_script STATIC instruction
download_script STATIC history
download_script NETWORK static_ip

# Make $SCRIPTS excutable
chmod +x -R "$SCRIPTS"
chown root:root -R "$SCRIPTS"

# Prepare first bootup
run_script STATIC change-wordpress-profile
run_script STATIC change-root-profile

# Disable hibernation
print_text_in_color "$ICyan" "Disable hibernation..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Reboot
msg_box "Installation almost done, system will reboot when you hit OK. 

Please log in again once rebooted to run the setup script."
reboot
