#!/bin/bash
#
# Touchpad Resume Fix for Huawei MateBook (Goodix GXTP7863)
# Resets the I2C controller and HID driver after suspend to fix erratic behavior
#
# Install to: /usr/local/bin/touchpad-fix-resume.sh
#

TOUCHPAD_I2C_DEVICE="i2c-GXTP7863:00"
I2C_CONTROLLER="i2c_designware.0"
HID_DRIVER_PATH="/sys/bus/i2c/drivers/i2c_hid_acpi"
CONTROLLER_DRIVER_PATH="/sys/bus/platform/drivers/i2c_designware"
LOG_TAG="touchpad-fix"
LOCK_FILE="/run/touchpad-fix.lock"
MAX_RETRIES=3

log() {
    logger -t "$LOG_TAG" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Prevent concurrent runs
if [ -e "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        log "Another instance (PID $LOCK_PID) is already running, exiting"
        exit 0
    fi
    log "Stale lock file found, removing"
    rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"

# Snapshot dmesg line count so we can check only new messages later
DMESG_BASELINE=0
mark_dmesg() {
    DMESG_BASELINE=$(dmesg | wc -l)
}

# Only "lost arbitration" after our baseline means the bus is actually wedged
check_i2c_healthy() {
    sleep 0.5
    local errors
    errors=$(dmesg | tail -n +"$((DMESG_BASELINE + 1))" | grep -c "lost arbitration" || true)
    [ "$errors" -eq 0 ]
}

# Wait for device sysfs entry to appear
wait_for_device() {
    local timeout=$1
    local i=0
    while [ $i -lt "$timeout" ]; do
        if [ -d "/sys/bus/i2c/devices/$TOUCHPAD_I2C_DEVICE" ]; then
            return 0
        fi
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}

log "Starting touchpad reset for $TOUCHPAD_I2C_DEVICE"

reset_touchpad() {
    local attempt=$1
    log "Reset attempt $attempt/$MAX_RETRIES"
    mark_dmesg

    # Step 1: Unbind the HID device from its driver
    if [ -e "$HID_DRIVER_PATH/$TOUCHPAD_I2C_DEVICE" ]; then
        log "Unbinding HID driver..."
        echo "$TOUCHPAD_I2C_DEVICE" > "$HID_DRIVER_PATH/unbind" 2>/dev/null || true
    fi

    # Step 2: Reset the I2C controller itself to clear bus errors
    log "Resetting I2C controller ($I2C_CONTROLLER)..."
    if [ -e "$CONTROLLER_DRIVER_PATH/$I2C_CONTROLLER" ]; then
        echo "$I2C_CONTROLLER" > "$CONTROLLER_DRIVER_PATH/unbind" 2>/dev/null
        sleep 0.5
        echo "$I2C_CONTROLLER" > "$CONTROLLER_DRIVER_PATH/bind" 2>/dev/null
        if [ $? -ne 0 ]; then
            log "ERROR: Failed to rebind I2C controller"
            return 1
        fi
        log "I2C controller reset done"
    else
        log "WARNING: I2C controller not bound, rebinding..."
        echo "$I2C_CONTROLLER" > "$CONTROLLER_DRIVER_PATH/bind" 2>/dev/null || true
    fi

    # Step 3: Wait for the touchpad device to reappear (poll fast, up to 5s)
    log "Waiting for touchpad device..."
    if ! wait_for_device 25; then
        log "ERROR: Touchpad device did not reappear after controller reset"
        return 1
    fi
    log "Touchpad device found"

    # Step 4: Make sure the HID driver binds to it
    if [ ! -e "$HID_DRIVER_PATH/$TOUCHPAD_I2C_DEVICE" ]; then
        log "HID driver not auto-bound, binding manually..."
        echo "$TOUCHPAD_I2C_DEVICE" > "$HID_DRIVER_PATH/bind" 2>/dev/null || true
    fi

    # Step 5: Verify no bus arbitration errors
    log "Verifying touchpad health..."
    if check_i2c_healthy; then
        log "Touchpad is healthy"
        return 0
    else
        log "Touchpad still has I2C bus errors"
        return 1
    fi
}

# Try the reset, retrying if needed
success=false
for attempt in $(seq 1 $MAX_RETRIES); do
    if reset_touchpad "$attempt"; then
        success=true
        break
    fi
    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        log "Retrying in 1 second..."
        sleep 1
    fi
done

if $success; then
    log "Touchpad reset complete"
    exit 0
else
    # Last resort: reload the kernel modules entirely
    log "All retries failed, reloading I2C HID modules..."
    mark_dmesg
    modprobe -r i2c_hid_acpi i2c_hid 2>/dev/null || true
    sleep 1
    modprobe i2c_hid_acpi 2>/dev/null || true

    if wait_for_device 25 && check_i2c_healthy; then
        log "Module reload fixed the touchpad"
        exit 0
    fi

    log "ERROR: Could not recover touchpad after all attempts"
    exit 1
fi
