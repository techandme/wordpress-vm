#!/bin/bash
# shellcheck disable=2034,2059
true
SCRIPT_NAME="Change Database Password"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# T&M Hansson IT AB © - 2024, https://www.hanssonit.se/

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Change MARIADB Password
if mysqladmin -u root password "$NEWMARIADBPASS" > /dev/null 2>&1
then
    msg_box "Your new MariaDB root password is: $NEWMARIADBPASS
Please keep it somewhere safe.

To login to MariaDB, simply type 'mysql -u root' from your CLI.
Authentication happens with the UNIX socket. In other words,
no password is needed as long as you have access to the root account."
    exit 0
else
    print_text_in_color "$IRed" "Changing MARIADB root password failed."
    print_text_in_color "$ICyan" "Your old password is: $MARIADBMYCNFPASS"
    exit 1
fi
