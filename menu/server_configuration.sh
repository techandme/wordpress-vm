#!/bin/bash

# T&M Hansson IT AB © - 2024, https://www.hanssonit.se/

# shellcheck disable=2034,2059
true
SCRIPT_NAME="Server Configuration Menu"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Set the correct switch for activate_tls
if [ -f "$SCRIPTS"/activate-tls.sh ]
then
    ACTIVATE_TLS_SWITCH="ON"
else
    ACTIVATE_TLS_SWITCH="OFF"
fi

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
    msg_box "In the next step, you will be offered to easily install different configurations that are made to enhance your server and experiance.
We have pre-selected some choices that we recommend for any installation.

PLEASE NOTE: For stability reasons you should *not* select everything just for the sake of it.
It's better to run: sudo bash $SCRIPTS/menu.sh when the first setup is complete, and after you've made a snapshot/backup of the server."
fi

# Server configurations
choice=$(whiptail --title "$TITLE" --checklist \
"Choose what you want to configure
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Static IP" "(Set static IP in Ubuntu with netplan.io)" OFF \
"DDclient Configuration" "(Use ddclient for automatic DDNS updates)" OFF \
"Activate TLS" "(Enable HTTPS with Let's Encrypt)" "$ACTIVATE_TLS_SWITCH" \
"Automatic updates" "(Automatically update your server every week on Sundays)" OFF \
"SMTP Mail" "(Enable beeing notified by mail from your server)" OFF 3>&1 1>&2 2>&3)

case "$choice" in
    *"Static IP"*)
        print_text_in_color "$ICyan" "Downloading the Static IP script..."
        run_script NETWORK static_ip
    ;;&
    *"DDclient Configuration"*)
        print_text_in_color "$ICyan" "Downloading the DDclient Configuration script..."
        run_script NETWORK ddclient-configuration
    ;;&
    *"Activate TLS"*)
        SUBTITLE="Activate TLS"
        msg_box "The following script will install a trusted
TLS certificate through Let's Encrypt.
It's recommended to use TLS (https) together with Wordpress.
Please open port 80 and 443 to this servers IP before you continue.
More information can be found here:
https://www.techandme.se/open-port-80-443/" "$SUBTITLE"

        if yesno_box_yes "Do you want to install TLS?" "$SUBTITLE"
        then
            if [ -f $SCRIPTS/activate-tls.sh ]
            then
                bash $SCRIPTS/activate-tls.sh
            else
                print_text_in_color "$ICyan" "Downloading the Let's Encrypt script..."
                download_script LETS_ENC activate-tls
                bash $SCRIPTS/activate-tls.sh
            fi
        else
            msg_box "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/activate-tls.sh" "$SUBTITLE"
        fi
        # Just make sure it is gone
        rm -f "$SCRIPTS/test-new-config.sh"
    ;;&
    *"Automatic updates"*)
        print_text_in_color "$ICyan" "Downloading the Automatic Updates script..."
        run_script ADDONS automatic_updates
    ;;&
    *"SMTP Mail"*)
        print_text_in_color "$ICyan" "Downloading the SMTP Mail script..."
        run_script ADDONS smtp-mail
    ;;&
    *)
    ;;
esac
exit
