#!/bin/bash

# T&M Hansson IT AB © - 2019, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
. <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
if ! is_root
then
    print_text_in_color "$IRed" "Must be root to run script, in Ubuntu type: sudo -i"
    exit 1
fi

mkdir -p "$SCRIPTS"

# Delete, download, run
run_static_script wordpress_update

exit
