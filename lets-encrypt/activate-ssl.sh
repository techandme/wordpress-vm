#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Information
msg_box "Important! Please read this:

This script will install SSL from Let's Encrypt.
It's free of charge, and very easy to maintain.

Before we begin the installation you need to have
a domain that the SSL certs will be valid for.
If you don't have a domain yet, get one before
you run this script!

You also have to open port 80+443 against this VMs
IP address: $ADDRESS - do this in your router/FW.
Here is a guide: https://goo.gl/Uyuf65

You can find the script here: $SCRIPTS/activate-ssl.sh 
and you can run it after you got a domain.

Please don't run this script if you don't have
a domain yet. You can get one for a fair price here:
https://store.binero.se/?lang=en-US"

if [[ "no" == $(ask_yes_or_no "Are you sure you want to continue?") ]]
then
msg_box "OK, but if you want to run this script later,
just type: sudo bash $SCRIPTS/activate-ssl.sh"
    exit
fi

if [[ "no" == $(ask_yes_or_no "Have you forwarded port 80+443 in your router?") ]]
then
msg_box "OK, but if you want to run this script later,
just type: sudo bash /var/scripts/activate-ssl.sh"
    exit
fi

if [[ "yes" == $(ask_yes_or_no "Do you have a domain that you will use?") ]]
then
    sleep 1
else
msg_box "OK, but if you want to run this script later, 
just type: sudo bash /var/scripts/activate-ssl.sh"
    exit
fi

echo
while true
do
# Ask for domain name
cat << ENTERDOMAIN
+---------------------------------------------------------------+
|    Please enter the domain name you will use for Wordpress:   |
|    Like this: example.com, or wordpress.example.com           |
+---------------------------------------------------------------+
ENTERDOMAIN
echo
read -r domain
echo
if [[ "yes" == $(ask_yes_or_no "Is this correct? $domain") ]]
then
    break
fi
done

# Check if port is open with NMAP
sed -i "s|127.0.1.1.*|127.0.1.1       $domain wordpress|g" /etc/hosts
network_ok
check_open_port 80 "$domain"
check_open_port 443 "$domain"

# Fetch latest version of test-new-config.sh
check_command download_le_script test-new-config

# Check if $domain exists and is reachable
echo
print_text_in_color "$ICyan" "Checking if $domain exists and is reachable..."
if wget -q -T 10 -t 2 --spider "$domain"; then
    sleep 1
elif wget -q -T 10 -t 2 --spider --no-check-certificate "https://$domain"; then
    sleep 1
elif curl -s -k -m 10 "$domain"; then
    sleep 1
elif curl -s -k -m 10 "https://$domain" -o /dev/null ; then
    sleep 1
else
msg_box "Nope, it's not there. You have to create $domain and point
it to this server before you can run this script."
    exit 1
fi

# Install certbot (Let's Encrypt)
install_certbot

#Fix issue #28
ssl_conf="/etc/nginx/sites-available/"$domain.conf""

# DHPARAM
DHPARAMS="$CERTFILES/$domain/dhparam.pem"

# Check if "$ssl.conf" exists, and if, then delete
if [ -f "$ssl_conf" ]
then
    rm -f "$ssl_conf"
fi

# Generate vhost.conf
if [ ! -f "$ssl_conf" ]
then
    touch "$ssl_conf"
    print_text_in_color "$IGreen" "$ssl_conf was successfully created."
    sleep 2
    cat << SSL_CREATE > "$ssl_conf"
server {
        listen 80;
        server_name $domain;
        return 301 https://$domain\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    ## Your website name goes here.
    server_name $domain;
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
    ssl_certificate $CERTFILES/$domain/fullchain.pem;
    ssl_certificate_key $CERTFILES/$domain/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    # Diffie-Hellman parameter for DHE ciphersuites, recommended 4096 bits
    ssl_dhparam $DHPARAMS;
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
    location ~* \.php$ {
        location ~ \wp-login.php$ {
                    allow $GATEWAY/24;
		    #allow $ADDRESS;
		    #allow $WAN4IP;
                    deny all;
                    include fastcgi.conf;
                    fastcgi_intercept_errors on;
                    fastcgi_pass unix:/var/run/php/php7.2-fpm-wordpress.sock; 
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
SSL_CREATE
fi

# Methods
# https://certbot.eff.org/docs/using.html#certbot-command-line-options
default_le="--rsa-key-size 4096 --renew-by-default --no-eff-email --agree-tos --uir --hsts --server https://acme-v02.api.letsencrypt.org/directory -d $domain"

standalone() {
# Generate certs
if eval "certbot certonly --standalone --pre-hook 'service nginx stop' --post-hook 'service nginx start' $default_le"
then
    echo "success" > /tmp/le_test
else
    echo "fail" > /tmp/le_test
fi
}
tls-alpn-01() {
if eval "certbot certonly --preferred-challenges tls-alpn-01 $default_le"
then
    echo "success" > /tmp/le_test
else
    echo "fail" > /tmp/le_test
fi
}
dns() {
if eval "certbot certonly --manual --manual-public-ip-logging-ok --preferred-challenges dns $default_le"
then
    echo "success" > /tmp/le_test
else
    echo "fail" > /tmp/le_test
fi
}

methods=(standalone dns)

create_config() {
# $1 = method
local method="$1"
# Check if $CERTFILES exists
if [ -d "$CERTFILES" ]
 then
    # Generate DHparams chifer
    if [ ! -f "$DHPARAMS" ]
    then
        openssl dhparam -dsaparam -out "$DHPARAMS" 4096
    fi
    # Activate new config
    check_command bash "$SCRIPTS/test-new-config.sh" "$domain.conf"
    exit
fi
}

attempts_left() {
local method="$1"
if [ "$method" == "standalone" ]
then
    printf "%b" "${ICyan}It seems like no certs were generated, we will do 1 more try.\n${Color_Off}"
    any_key "Press any key to continue..."
#elif [ "$method" == "tls-alpn-01" ]
#then
#    printf "%b" "${ICyan}It seems like no certs were generated, we will do 1 more try.\n${Color_Off}"
#    any_key "Press any key to continue..."
elif [ "$method" == "dns" ]
then
    printf "%b" "${IRed}It seems like no certs were generated, please check your DNS and try again.\n${Color_Off}"
    any_key "Press any key to continue..."
fi
}

# Generate the cert
for f in "${methods[@]}"; do "$f"
if [ "$(grep 'success' /tmp/le_test)" == 'success' ]; then
    rm -f /tmp/le_test
    create_config "$f"
else
    rm -f /tmp/le_test
    attempts_left "$f"
fi
done

# Failed
msg_box "Sorry, last try failed as well. :/

The script is located in $SCRIPTS/activate-ssl.sh
Please try to run it again some other time with other settings.

There are different configs you can try in Let's Encrypt's user guide:
https://letsencrypt.readthedocs.org/en/latest/index.html
Please check the guide for further information on how to enable SSL.

This script is developed on GitHub, feel free to contribute:
https://github.com/techandme/wordpress-vm

The script will now do some cleanup and revert the settings."

# Cleanup
apt remove certbot -y
apt autoremove -y
clear
