#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
MYCNFPW=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
unset MYCNFPW

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

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
