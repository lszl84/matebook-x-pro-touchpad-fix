#!/bin/bash
#
# Touchpad Resume Fix for Huawei MateBook (Goodix GXTP7863)
# Reloads the I2C HID kernel module after suspend and reapplies libinput settings.
#
# Install to: /usr/local/bin/touchpad-fix-resume.sh
#

LOG_TAG="touchpad-fix"
TOUCHPAD_SYSFS="/sys/bus/i2c/devices/i2c-GXTP7863:00"

log() { logger -t "$LOG_TAG" "$1"; }

# Step 1: Reload the kernel module
log "Reloading i2c_hid_acpi module"
modprobe -r i2c_hid_acpi i2c_hid 2>/dev/null || true
sleep 0.5
modprobe i2c_hid_acpi

# Step 2: Wait for touchpad to appear in sysfs (up to 5s)
for _ in $(seq 1 25); do
    [ -d "$TOUCHPAD_SYSFS" ] && break
    sleep 0.2
done

if [ ! -d "$TOUCHPAD_SYSFS" ]; then
    log "ERROR: Touchpad device did not appear"
    exit 1
fi
log "Touchpad device ready"

# Step 3: Apply libinput settings in the active X session
# This runs sequentially after the device is confirmed present, avoiding race conditions.
xuser=$(who 2>/dev/null | awk '/\(:[0-9]/{print $1; exit}')
[ -z "$xuser" ] && xuser=$(stat -c '%U' /tmp/.X11-unix/X0 2>/dev/null)

if [ -n "$xuser" ] && [ "$xuser" != "root" ]; then
    xhome=$(eval echo "~$xuser")
    export DISPLAY=:0 XAUTHORITY="$xhome/.Xauthority"

    # Wait for touchpad to register in xinput (up to 5s)
    for _ in $(seq 1 25); do
        sudo -u "$xuser" DISPLAY=:0 XAUTHORITY="$xhome/.Xauthority" \
            xinput list 2>/dev/null | grep -qi touchpad && break
        sleep 0.2
    done

    log "Applying libinput settings for $xuser"
    sudo -u "$xuser" DISPLAY=:0 XAUTHORITY="$xhome/.Xauthority" bash -c '
        for id in $(xinput list --id-only 2>/dev/null); do
            xinput set-prop "$id" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
            xinput set-prop "$id" "libinput Tapping Enabled" 1 2>/dev/null || true
            xinput set-prop "$id" "libinput Click Method Enabled" 0 1 2>/dev/null || true
        done
    '
else
    log "No active X session found, skipping libinput settings"
fi

log "Done"
