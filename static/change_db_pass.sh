#!/bin/bash
# shellcheck disable=2034,2059
true
SCRIPT_NAME="Change Database Password"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/20.04_testing/lib.sh)

# Get all needed variables from the library
wpdb
mycnfpw

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Change MARIADB Password
if mysqladmin -u root -p"$MARIADBMYCNFPASS" password "$NEWMARIADBPASS" > /dev/null 2>&1
then
    print_text_in_color "$IGreen" "Your new MARIADB root password is: $NEWMARIADBPASS"
    cat << LOGIN > "$MYCNF"
[client]
password='$NEWMARIADBPASS'
LOGIN
    chmod 0600 $MYCNF
    exit 0
else
    print_text_in_color "$IRed" "Changing MARIADB root password failed."
    print_text_in_color "$ICyan" "Your old password is: $MARIADBMYCNFPASS"
    exit 1
fi
