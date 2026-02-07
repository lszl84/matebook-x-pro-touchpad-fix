#!/bin/bash
#
# Touchpad Resume Fix for Huawei MateBook (Goodix GXTP7863)
# Unbinds and rebinds the I2C HID driver after suspend to fix erratic behavior
#
# Install to: /usr/local/bin/touchpad-fix-resume.sh
#

TOUCHPAD_I2C_DEVICE="i2c-GXTP7863:00"
DRIVER_PATH="/sys/bus/i2c/drivers/i2c_hid_acpi"
LOG_TAG="touchpad-fix"

log() {
    logger -t "$LOG_TAG" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Check if device exists
if [ ! -d "/sys/bus/i2c/devices/$TOUCHPAD_I2C_DEVICE" ]; then
    log "ERROR: Touchpad device $TOUCHPAD_I2C_DEVICE not found"
    exit 1
fi

log "Starting touchpad reset for $TOUCHPAD_I2C_DEVICE"

# Small delay to let the system stabilize after resume
sleep 1

# Unbind
if [ -e "$DRIVER_PATH/unbind" ]; then
    log "Unbinding touchpad driver..."
    echo "$TOUCHPAD_I2C_DEVICE" > "$DRIVER_PATH/unbind" 2>/dev/null
    if [ $? -eq 0 ]; then
        log "Unbind successful"
    else
        log "Unbind may have failed (device might already be unbound)"
    fi
else
    log "ERROR: Driver unbind path not found"
    exit 1
fi

# Wait for device to fully disconnect
sleep 2

# Rebind
if [ -e "$DRIVER_PATH/bind" ]; then
    log "Rebinding touchpad driver..."
    echo "$TOUCHPAD_I2C_DEVICE" > "$DRIVER_PATH/bind" 2>/dev/null
    if [ $? -eq 0 ]; then
        log "Rebind successful"
    else
        log "ERROR: Rebind failed"
        exit 1
    fi
else
    log "ERROR: Driver bind path not found"
    exit 1
fi

# Wait for device to initialize
sleep 1

log "Touchpad reset complete"
exit 0
