#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
SCRIPT_NAME="Additional Apps Menu"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/20.04_testing/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Set the startup switch
if [ -f "$SCRIPTS/wordpress-startup-script.sh" ]
then
    STARTUP_SWITCH="ON"
else
    STARTUP_SWITCH="OFF"
fi

# Show a msg_box during the startup script
if [ -f "$SCRIPTS/wordpress-startup-script.sh" ]
then
    msg_box "In the next step, you will be offered to easily install apps that are made to enhance your server and experiance.
We have pre-selected apps that we recommend for any installation.

PLEASE NOTE: For stability reasons you should *not* select apps just for the sake of it.
It's better to run: sudo bash $SCRIPTS/menu.sh when the first setup is complete, and after you've made a snapshot/backup of the server."
fi

# Install Apps
choice=$(whiptail --title "$TITLE" --checklist \
"Which apps do you want to install?\n\nAutomatically configure and install selected apps
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Fail2ban  " "(Extra Bruteforce protection)" "$STARTUP_SWITCH" \
"Adminer" "(Database Administraton GUI)" OFF \
"Netdata" "(Real-time server monitoring in Web GUI)" OFF \
"BPYTOP" "(Real-time server monitoring in CLI)" OFF \
"Midnight Commander" "(CLI file manager)" OFF \
"Webmin" "(Server GUI like Cpanel)" "$STARTUP_SWITCH" 3>&1 1>&2 2>&3)
case "$choice" in
    *"Fail2ban  "*)
        print_text_in_color "$ICyan" "Downloading the Fail2ban Menu..."
        run_script MENU fail2ban_menu
    ;;&
    *"Adminer"*)
        print_text_in_color "$ICyan" "Downloading the Adminer script..."
        run_script APP adminer
    ;;&
    *"Netdata"*)
        print_text_in_color "$ICyan" "Downloading the Netdata script..."
        run_script APP netdata
    ;;&
    *"BPYTOP"*)
        print_text_in_color "$ICyan" "Downloading the BPYTOP script..."
        run_script APP bpytop
    ;;&
    *"Midnight Commander"*)
        print_text_in_color "$ICyan" "Downloading the Midnight Commander script..."
        run_script APP midnight-commander
    ;;&
    *"Webmin"*)
        print_text_in_color "$ICyan" "Downloading the Webmin script..."
        run_script APP webmin
    ;;&
    *)
    ;;
esac
exit
