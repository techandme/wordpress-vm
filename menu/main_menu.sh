#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# shellcheck disable=2034,2059,1091
true
SCRIPT_NAME="Main Menu"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

##################################################################

# Main menu
choice=$(whiptail --title "$TITLE" --menu \
"Choose what you want to do.
$MENU_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Additional Apps" "(Choose which apps to install)" \
"Startup Configuration" "(Choose between available startup configurations)" \
"Server Configuration" "(Choose between available server configurations)" \
"Update Wordpress" "(Update Wordpress to the latest release)" 3>&1 1>&2 2>&3)

case "$choice" in
    "Additional Apps")
        print_text_in_color "$ICyan" "Downloading the Additional Apps Menu..."
        run_script MENU additional_apps
    ;;
    "Startup Configuration")
        print_text_in_color "$ICyan" "Downloading the Startup Configuration Menu..."
        run_script MENU startup_configuration
    ;;
    "Server Configuration")
        print_text_in_color "$ICyan" "Downloading the Server Configuration Menu..."
        run_script MENU server_configuration
    ;;
    "Update Wordpress")
        if [ -f "$SCRIPTS"/update.sh ]
        then
            bash "$SCRIPTS"/update.sh
        else
            print_text_in_color "$ICyan" "Downloading the Update script..."
            download_script STATIC update
            chmod +x "$SCRIPTS"/update.sh
            bash "$SCRIPTS"/update.sh
        fi
    ;;
    *)
    ;;
esac
exit
