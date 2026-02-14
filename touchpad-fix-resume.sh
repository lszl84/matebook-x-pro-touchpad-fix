#!/bin/bash
#
# Touchpad Resume Fix for Huawei MateBook (Goodix GXTP7863)
# Reloads the I2C HID kernel module after suspend so the touchpad reappears.
# libinput settings (tap-to-click, etc.) are handled by xorg.conf.d.
#
# Install to: /usr/local/bin/touchpad-fix-resume.sh
#

LOG_TAG="touchpad-fix"
TOUCHPAD_SYSFS="/sys/bus/i2c/devices/i2c-GXTP7863:00"

log() { logger -t "$LOG_TAG" "$1"; }

log "Reloading i2c_hid_acpi module"
modprobe -r i2c_hid_acpi i2c_hid 2>/dev/null || true
sleep 0.5
modprobe i2c_hid_acpi

# Wait for touchpad to appear in sysfs (up to 5s)
for _ in $(seq 1 25); do
    [ -d "$TOUCHPAD_SYSFS" ] && break
    sleep 0.2
done

if [ -d "$TOUCHPAD_SYSFS" ]; then
    log "Touchpad device ready"
else
    log "ERROR: Touchpad device did not appear"
    exit 1
fi
