#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
SCRIPT_NAME="Adminer"
SCRIPT_EXPLAINER="Adminer is a full-featured database management tool written in PHP."
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Check if adminer is already installed
if ! is_this_installed adminer
then
    # Ask for installing
    install_popup "$SCRIPT_NAME"
else
    # Ask for removal or reinstallation
    reinstall_remove_menu "$SCRIPT_NAME"
    # Removal
    check_command apt-get purge adminer -y
    rm -f $ADMINER_CONF
    rm -rf $ADMINERDIR
    restart_webserver
    # Show successful uninstall if applicable
    removal_popup "$SCRIPT_NAME"
fi

# Check that the script can see the external IP (apache fails otherwise)
check_external_ip

# Check distrobution and version
check_distro_version

# Install Adminer
apt update -q4 & spinner_loading
install_if_not adminer
curl_to_dir "http://www.adminer.org" "latest.php" "$ADMINERDIR"
curl_to_dir "https://raw.githubusercontent.com/Niyko/Hydra-Dark-Theme-for-Adminer/master" "adminer.css" "$ADMINERDIR"
check_command mv "$ADMINERDIR"/latest.php "$ADMINERDIR"/adminer.php

# Only add TLS 1.3 on Ubuntu later than 20.04
if version 20.04 "$DISTRO" 20.04.10
then
    TLS13="+TLSv1.3"
fi

cat << ADMINER_CREATE > "$ADMINER_CONF"
server {
    listen 444 ssl http2;
    listen [::]:444 ssl http2;

    ## Your website name goes here.
    # server_name example.com;
    ## Your only path reference.
    root /usr/share/adminer/adminer;
    ## This should be in your http block and if it is, it's not needed here.
    index adminer.php;
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
           index   index.php;
           allow   $GATEWAY/24;
           deny    all;
       }
    location ~* ^/adminer/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
                root /usr/share/adminer/;
       }

    location ~ /\.ht {
           deny  all;
       }
    location ~ /(libraries|setup/frames|setup/libs) {
           deny all;
           return 404;
       }
    # Pass the PHP scripts to FastCGI server
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
}
ADMINER_CREATE

if ! systemctl restart nginx.service
then
msg_box "Nginx could not restart...
The script will exit."
    exit 1
else
msg_box "Adminer was sucessfully installed and can be reached here:
http://$ADDRESS:81
You can download more plugins and get more information here:
https://www.adminer.org
Your MariaDB connection information can be found in $WPATH/wp-config.php
In case you try to access Adminer and get 'Forbidden' you need to change the IP in:
$ADMINER_CONF"
fi

exit
