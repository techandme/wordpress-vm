#!/bin/bash

# T&M Hansson IT AB © - 2024, https://www.hanssonit.se/
# Copyright © 2024 Simon Lindner (https://github.com/szaimen)

# shellcheck disable=2034,2059
true
SCRIPT_NAME="Nginx Brotli"
SCRIPT_EXPLAINER="Enables Brotli compression support for Nginx"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Replace old Nginx with new
install_if_not ppa-purge
ppa-purge nginx/stable
rm -f /etc/apt/sources.list.d/nginx*
check_command yes | add-apt-repository ppa:ondrej/nginx
apt update -q4 && spinner_loading
install_if_not nginx
systemctl stop nginx
systemctl start nginx
systemctl enable nginx
apt-get purge ppa-purge -y
apt-get autoremove -y

# Enable Brotli
install_if_not libnginx-mod-brotli
if ! [ -f /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf ]
then
    echo "load_module modules/ngx_http_brotli_filter_module.so;" > /etc/nginx/modules-enabled/50-mod-http-brotli-filter.conf
fi

# Enable Brotli in config
rm -f /etc/nginx/nginx.conf
curl_to_dir "$STATIC" nginx.conf /etc/nginx/

# Restart Nginx
if nginx -t
then
    systemctl restart nginx
fi
