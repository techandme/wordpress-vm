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
add-apt-repository ppa:ondrej/nginx
apt update -q4 && spinner_loading
apt-get update nginx -y
ppa-purge nginx/stable
rm -f /etc/apt/sources.list.d/nginx*
apt-get autoremove -y

# Enable Brotli
install_of_not sponge
install_if_not libnginx-mod-brotli
{
echo "# https://docs.nginx.com/nginx/admin-guide/dynamic-modules/brotli/"
echo "load_module modules/ngx_http_brotli_filter_module.so; # for compressing responses on-the-fly"
echo "load_module modules/ngx_http_brotli_static_module.so; # for serving pre-compressed files"
} | cat - "$NGINX_CONF" | sponge "$NGINX_CONF"
apt-get purge sponge -y

if nginx -t
then
    systemctl restart nginx
fi
