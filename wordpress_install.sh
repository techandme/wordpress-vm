#!/bin/bash

# T&M Hansson IT AB © - 2018, https://www.hanssonit.se/

# Prefer IPv4
sed -i "s|#precedence ::ffff:0:0/96  100|precedence ::ffff:0:0/96  100|g" /etc/gai.conf

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
FIRST_IFACE=1 && CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
unset FIRST_IFACE
unset CHECK_CURRENT_REPO

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
if ! is_root
then
    printf "\n${Red}Sorry, you are not root.\n${Color_Off}You must type: ${Cyan}sudo ${Color_Off}bash %s/wordpress_install.sh\n" "$SCRIPTS"
    exit 1
fi

# Test RAM size (2GB min) + CPUs (min 1)
ram_check 1 Wordpress
cpu_check 1 Wordpress

# Set locales
apt install language-pack-en-base -y
sudo locale-gen "sv_SE.UTF-8" && sudo dpkg-reconfigure --frontend=noninteractive locales

# Show current user
echo
echo "Current user with sudo permissions is: $UNIXUSER".
echo "This script will set up everything with that user."
echo "If the field after ':' is blank you are probably running as a pure root user."
echo "It's possible to install with root, but there will be minor errors."
echo
echo "Please create a user with sudo permissions if you want an optimal installation."
run_static_script adduser

# Check Ubuntu version
echo "Checking server OS and version..."
if [ "$OS" != 1 ]
then
    echo "Ubuntu Server is required to run this script."
    echo "Please install that distro and try again."
    exit 1
fi


if ! version 18.04 "$DISTRO" 18.04.4; then
    echo "Ubuntu version $DISTRO must be between 18.04 - 18.04.4"
    exit
fi

# Check if it's a clean server
is_this_installed postgresql
is_this_installed apache2
is_this_installed nginx
is_this_installed php
is_this_installed mysql-common
is_this_installed mariadb-server

# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi

# Change DNS
install_if_not resolvconf
yes | dpkg-reconfigure --frontend=noninteractive resolvconf
echo "nameserver 9.9.9.9" > /etc/resolvconf/resolv.conf.d/base
echo "nameserver 149.112.112.112" >> /etc/resolvconf/resolv.conf.d/base

# Check network
test_connection

# Check where the best mirrors are and update
echo
printf "Your current server repository is:  ${Cyan}%s${Color_Off}\n" "$REPO"
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

# Update system
apt update -q4 & spinner_loading

# Write MARIADB pass to file and keep it safe
{
echo "[client]"
echo "password='$MARIADB_PASS'"
} > "$MYCNF"
chmod 0600 $MYCNF
chown root:root $MYCNF

# Install MARIADB
apt install software-properties-common -y
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
sudo add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://ftp.ddg.lth.se/mariadb/repo/10.2/ubuntu xenial main'
sudo debconf-set-selections <<< "mariadb-server-10.2 mysql-server/root_password password $MARIADB_PASS"
sudo debconf-set-selections <<< "mariadb-server-10.2 mysql-server/root_password_again password $MARIADB_PASS"
apt update -q4 & spinner_loading
check_command apt install mariadb-server-10.2 -y

# Prepare for Wordpress installation
# https://blog.v-gar.de/2017/02/en-solved-error-1698-28000-in-mysqlmariadb/
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET plugin='' WHERE user='root';"
mysql -u root mysql -p"$MARIADB_PASS" -e "UPDATE user SET password=PASSWORD('$MARIADB_PASS') WHERE user='root';"
mysql -u root -p"$MARIADB_PASS" -e "flush privileges;"

# mysql_secure_installation
apt -y install expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MARIADB_PASS\r\"
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
run_static_script new_etc_mycnf

# Install VM-tools
apt install open-vm-tools -y

# Install Nginx
apt update -q4 && spinner_loading
check_command apt install nginx -y
sudo systemctl stop nginx.service
sudo systemctl start nginx.service
sudo systemctl enable nginx.service

# Install PHP 7.2
apt install -y \
        php \
	php7.2-fpm \
	php7.2-common \
	php7.2-mbstring \
	php7.2-xmlrpc \
	php7.2-gd \
	php7.2-xml \
	php7.2-mysql \
	php7.2-cli \
	php7.2-zip \
	php7.2-curl
	
# Configure PHP
sed -i "s|allow_url_fopen =.*|allow_url_fopen = On|g" /etc/php/7.2/fpm/php.ini
sed -i "s|max_execution_time =.*|max_execution_time = 360|g" /etc/php/7.2/fpm/php.ini
sed -i "s|file_uploads =.*|file_uploads = On|g" /etc/php/7.2/fpm/php.ini
sed -i "s|upload_max_filesize =.*|upload_max_filesize = 100M|g" /etc/php/7.2/fpm/php.ini
sed -i "s|memory_limit =.*|memory_limit = 256M|g" /etc/php/7.2/fpm/php.ini
sed -i "s|post_max_size =.*|post_max_size = 110M|g" /etc/php/7.2/fpm/php.ini
sed -i "s|cgi.fix_pathinfo =.*|cgi.fix_pathinfo=0|g" /etc/php/7.2/fpm/php.ini
sed -i "s|date.timezone =.*|date.timezone = Europe/Stockholm|g" /etc/php/7.2/fpm/php.ini

# Download wp-cli.phar to be able to install Wordpress
check_command curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Create dir
mkdir $WPATH

# Create wp-cli.yml
touch $WPATH/wp-cli.yml
cat << YML_CREATE > "$WPATH/wp-cli.yml"
nginx_modules:
  - mod_rewrite
YML_CREATE

# Show info about wp-cli
wp --info --allow-root

# Download Wordpress
cd "$WPATH"
check_command wp core download --allow-root --force --debug --path="$WPATH"

# Populate DB
mysql -uroot -p"$MARIADB_PASS" <<MYSQL_SCRIPT
CREATE DATABASE $WPDBNAME;
CREATE USER '$WPDBUSER'@'localhost' IDENTIFIED BY '$WPDBPASS';
GRANT ALL PRIVILEGES ON $WPDBNAME.* TO '$WPDBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
wp core config --allow-root --dbname=$WPDBNAME --dbuser=$WPDBUSER --dbpass="$WPDBPASS" --dbhost=localhost --extra-php <<PHP
define( 'WP_DEBUG', false );
define( 'WP_CACHE_KEY_SALT', 'wpredis_' );
define( 'WP_REDIS_MAXTTL', 9600);
define( 'WP_REDIS_SCHEME', 'unix' );
define( 'WP_REDIS_PATH', '$REDIS_SOCK' );
define( 'WP_REDIS_PASSWORD', '$REDIS_PASS' );
define( 'WP_AUTO_UPDATE_CORE', true );
PHP

# Make sure the passwords are the same, this file will be deleted when Redis is run.
echo "$REDIS_PASS" > /tmp/redis_pass.txt

# Install Wordpress
check_command wp core install --allow-root --url=http://"$ADDRESS"/ --title=Wordpress --admin_user=$WPADMINUSER --admin_password="$WPADMINPASS" --admin_email=no-reply@techandme.se --skip-email
echo "WP PASS: $WPADMINPASS" > /var/adminpass.txt
chown wordpress:wordpress /var/adminpass.txt

# Create welcome post
check_command wget -q $STATIC/welcome.txt
sed -i "s|wordpress_user_login|$WPADMINUSER|g" welcome.txt
sed -i "s|wordpress_password_login|$WPADMINPASS|g" welcome.txt
wp post create ./welcome.txt --post_title='T&M Hansson IT AB - Welcome' --post_status=publish --path=$WPATH --allow-root
rm -f welcome.txt
wp post delete 1 --force --allow-root

# Show version
wp core version --allow-root
sleep 3

# Install Apps
wp plugin install --allow-root twitter-tweets --activate
wp plugin install --allow-root social-pug --activate
wp plugin install --allow-root wp-mail-smtp --activate
wp plugin install --allow-root google-captcha --activate
wp plugin install --allow-root redis-cache --activate

# set pretty urls
wp rewrite structure '/%postname%/' --hard --allow-root
wp rewrite flush --hard --allow-root

# delete akismet and hello dolly
wp plugin delete akismet --allow-root
wp plugin delete hello --allow-root

# Secure permissions
run_static_script wp-permissions

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

# Set up a php-fpm pool with a unixsocket
cat << POOL_CONF > "$PHP_POOL_DIR/www_wordpress.conf"
[www_wordpress]
user = www-data
group = www-data
listen = $PHP_FPM_SOCK
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 17
pm.start_servers = 5
pm.min_spare_servers = 2
pm.max_spare_servers = 10
pm.max_requests = 500
env[HOSTNAME] = $(hostname -f)
env[PATH] = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
security.limit_extensions = .php
php_admin_value [cgi.fix_pathinfo] = 1
POOL_CONF

# Disable regular pool
mv $PHP_POOL_DIR/www.conf $PHP_POOL_DIR/default_www.config

# Install Figlet
apt install figlet -y

# Generate $SSL_CONF
install_if_not ssl-cert
systemctl stop nginx.service && wait
if [ ! -f $SSL_CONF ];
        then
        touch $SSL_CONF
        cat << SSL_CREATE > $SSL_CONF
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

    location ~* \\.php$ {
                #NOTE: You should have "cgi.fix_pathinfo = 0;" in php.ini
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
SSL_CREATE
echo "$SSL_CONF was successfully created"
sleep 1
fi

# Generate $HTTP_CONF
if [ ! -f $HTTP_CONF ];
        then
        touch $HTTP_CONF
        cat << HTTP_CREATE > $HTTP_CONF
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

    location ~* \\.php$ {
                #NOTE: You should have "cgi.fix_pathinfo = 0;" in php.ini
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
echo "$HTTP_CONF was successfully created"
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
        server unix:/run/php/php7.2-fpm.sock;
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
echo "$NGINX_CONF was successfully created"
sleep 1
fi

# Generate $NGINX_CONF
if [ -f "$NGINX_DEF" ];
then
    rm -f $NGINX_DEF
    rm -f /etc/nginx/sites-enabled/default
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
echo "$NGINX_DEF was successfully created"
sleep 1
fi

# Enable new config
ln -s "$NGINX_DEF" /etc/nginx/sites-enabled/
ln -s "$SSL_CONF" /etc/nginx/sites-enabled/
ln -s "$HTTP_CONF" /etc/nginx/sites-enabled/
systemctl restart nginx.service

# Enable UTF8mb4 (4-byte support)
databases=$(mysql -u root -p"$MARIADB_PASS" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
for db in $databases; do
    if [[ "$db" != "performance_schema" ]] && [[ "$db" != _* ]] && [[ "$db" != "information_schema" ]];
    then
        echo "Changing to UTF8mb4 on: $db"
        mysql -u root -p"$MARIADB_PASS" -e "ALTER DATABASE $db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    fi
done

# Enable OPCache for PHP
phpenmod opcache
{
echo "# OPcache settings for Wordpress"
echo "opcache.enable=1"
echo "opcache.enable_cli=1"
echo "opcache.interned_strings_buffer=8"
echo "opcache.max_accelerated_files=10000"
echo "opcache.memory_consumption=128"
echo "opcache.save_comments=1"
echo "opcache.revalidate_freq=1"
echo "opcache.validate_timestamps=1"
} >> /etc/php/7.2/fpm/php.ini

# Install Redis
run_static_script redis-server-ubuntu

# Set secure permissions final
run_static_script wp-permissions

# Prepare for first mount
download_static_script instruction
download_static_script history
run_static_script change-root-profile
run_static_script change-wordpress-profile
if [ ! -f "$SCRIPTS"/wordpress-startup-script.sh ]
then
check_command wget -q "$GITHUB_REPO"/wordpress-startup-script.sh -P "$SCRIPTS"
fi

# Make $SCRIPTS excutable
chmod +x -R "$SCRIPTS"
chown root:root -R "$SCRIPTS"

# Allow wordpress to run theese scripts
chown wordpress:wordpress "$SCRIPTS/instruction.sh"
chown wordpress:wordpress "$SCRIPTS/history.sh"

# Upgrade
apt dist-upgrade -y

# Remove LXD (always shows up as failed during boot)
apt purge lxd -y

# Cleanup
apt autoremove -y
apt autoclean
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete

# Install virtual kernels for Hyper-V
# Kernel 4.15
apt install -y --install-recommends \
linux-virtual \
linux-tools-virtual \
linux-cloud-tools-virtual \
linux-image-virtual \
linux-image-extra-virtual

# Force MOTD to show correct number of updates
sudo /usr/lib/update-notifier/update-motd-updates-available --force

# Prefer IPv6
sed -i "s|precedence ::ffff:0:0/96  100|#precedence ::ffff:0:0/96  100|g" /etc/gai.conf

# Reboot
echo "Installation done, system will now reboot..."
reboot
