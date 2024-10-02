#!/bin/bash
# shellcheck disable=2034,2059
true
SCRIPT_NAME="Activate TLS"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# T&M Hansson IT AB © - 2024, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Information
# Information
msg_box "Before we begin the installation of your TLS certificate you need to:

1. Have a domain like: wordpress.example.com
If you want to get a domain at a fair price, please check this out: https://store.binero.se/?lang=en-US

2. Open port 80 and 443 against this servers IP address: $ADDRESS.
Here is a guide: https://www.techandme.se/open-port-80-443
It's also possible to automatically open ports with UPNP, if you have that enabled in your firewall/router.

PLEASE NOTE:
This script can be run again by executing: sudo bash $SCRIPTS/menu.sh, and choose 'Server Configuration' --> 'Activate TLS'"

if ! yesno_box_yes "Are you sure you want to continue?"
then
    msg_box "OK, but if you want to run this script later, just execute this in your CLI: sudo \
bash /var/scripts/menu.sh and choose 'Server Configuration' --> 'Activate TLS'"
    exit
fi

if ! yesno_box_yes "Have you opened port 80 and 443 in your router, or are you using UPNP?"
then
    msg_box "OK, but if you want to run this script later, just execute this in your CLI: sudo \
bash /var/scripts/menu.sh and choose 'Server Configuration' --> 'Activate TLS'"
    exit
fi

if ! yesno_box_yes "Do you have a domain that you will use?"
then
    msg_box "OK, but if you want to run this script later, just execute this in your CLI: sudo \
bash /var/scripts/menu.sh and choose 'Server Configuration' --> 'Activate TLS'"
    exit
fi

# Wordpress Main Domain (activate-tls.sh)
TLSDOMAIN=$(input_box_flow "Please enter the domain name you will use for Wordpress.
Make sure it looks like this:\nyourdomain.com, or www.yourdomain.com")

msg_box "Before continuing, please make sure that you have you have edited the DNS settings for $TLSDOMAIN, \
and opened port 80 and 443 directly to this servers IP. A full exstensive guide can be found here:
https://www.techandme.se/open-port-80-443

This can be done automatically if you have UNNP enabled in your firewall/router. \
You will be offered to use UNNP in the next step."

if yesno_box_no "Do you want to use UPNP to open port 80 and 443?"
then
    unset FAIL
    open_port 80 TCP
    open_port 443 TCP
    cleanup_open_port
fi

# Curl the lib another time to get the correct https_conf
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/w0.04_testing/lib.sh)

# Check if $TLSDOMAIN exists and is reachable
echo
print_text_in_color "$ICyan" "Checking if $TLSDOMAIN exists and is reachable..."
domain_check_200 "$TLSDOMAIN"

# Check if port is open with NMAP
sed -i "s|127.0.1.1.*|127.0.1.1       $TLSDOMAIN wordpress|g" /etc/hosts
network_ok
check_open_port 80 "$TLSDOMAIN"
check_open_port 443 "$TLSDOMAIN"

# Fetch latest version of test-new-config.sh
check_command download_script LETS_ENC test-new-config

# Install certbot (Let's Encrypt)
install_certbot

#Fix issue #28
tls_conf="$SITES_AVAILABLE/$TLSDOMAIN.conf"

# Check if "$tls.conf" exists, and if, then delete
if [ -f "$tls_conf" ]
then
    rm -f "$tls_conf"
fi

# Check current PHP version --> PHPVER
# To get the correct version for the Nginx conf file
check_php

# Check Brotli support
if is_this_installed libnginx-mod-brotli
then
    BROTLI_ON="brotli on;"
fi

# Generate wordpress_tls_domain.conf
if [ ! -f "$tls_conf" ]
then
    touch "$tls_conf"
    print_text_in_color "$IGreen" "$tls_conf was successfully created."
    sleep 2
    cat << TLS_CREATE > "$tls_conf"
server {
    listen 80;
    listen [::]:80;
    server_name $TLSDOMAIN;
    return 301 https://$TLSDOMAIN\$request_uri;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    $BROTLI_ON

    ## Your website name goes here.
    server_name $TLSDOMAIN;
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
    ssl_certificate $CERTFILES/$TLSDOMAIN/fullchain.pem;
    ssl_certificate_key $CERTFILES/$TLSDOMAIN/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions
    ssl_session_tickets off;
    # Diffie-Hellman parameter for DHE ciphersuites, recommended 4096 bits
    ssl_dhparam $DHPARAMS_TLS;
    # intermediate configuration. tweak to your needs.
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    # HSTS (ngx_http_headers_module is required) (63072000 seconds)
    add_header Strict-Transport-Security "max-age=63072000" always;
    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
            # https://veerasundar.com/blog/2014/09/setting-expires-header-for-assets-nginx/
            if (\$request_uri ~* ".(ico|css|js|gif|jpe?g|png)$") {
                expires 15d;
                access_log off;
                add_header Pragma public;
                add_header Cache-Control "public";
                break;
            }
    }
    location /.well-known {
        root /usr/share/nginx/html;
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
    location = /xmlrpc.php {
                allow 122.248.245.244/32;
                allow 54.217.201.243/32;
                allow 54.232.116.4/32;
                allow 192.0.80.0/20;
                allow 192.0.96.0/20;
                allow 192.0.112.0/20;
                allow 195.234.108.0/22;
                deny all;
                access_log off;
                log_not_found off;
    }
    location ~* \.php$ {
        location ~ \wp-login.php$ {
                    allow $GATEWAY/24;
		    # allow $ADDRESS;
		    # allow $WAN4IP;
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
fi

# Check if PHP-FPM is installed and if not, then remove PHP-FPM related lines from config
if ! pgrep php-fpm
then
    sed -i "s|<FilesMatch.*|# Removed due to that PHP-FPM $PHPVER is missing|g" "$tls_conf"
    sed -i "s|SetHandler.*|#|g" "$tls_conf"
    sed -i "s|</FilesMatch.*|#|g" "$tls_conf"
fi

#Generate certs and auto-configure if successful
if generate_cert "$TLSDOMAIN"
then
    if [ -d "$CERTFILES" ]
    then
        # Generate DHparams chifer
        if [ ! -f "$DHPARAMS_TLS" ]
        then
            openssl dhparam -dsaparam -out "$DHPARAMS_TLS" 4096
        fi
        # Activate new config
        check_command bash "$SCRIPTS/test-new-config.sh" "$TLSDOMAIN.conf"
        msg_box "Please remember to keep port 80 (and 443) open so that Let's Encrypt can do \
the automatic renewal of the cert. If port 80 is closed the cert will expire in 3 months.

You don't need to worry about security as port 80 is directly forwarded to 443, so \
no traffic will actually be on port 80, except for the forwarding to 443 (HTTPS)."
        exit 0
    fi
else
    last_fail_tls "$SCRIPTS"/activate-tls.sh cleanup
fi

exit
