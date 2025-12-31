#!/usr/bin/env bash
#
# Reset the Intel USB controller to recover Bluetooth after firmware upload failure
#

CONTROLLER="0000:00:14.0"
DRIVER_PATH="/sys/bus/pci/drivers/xhci_hcd"

if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges"
    exec sudo "$0" "$@"
fi

echo "Unbinding USB controller $CONTROLLER..."
echo "$CONTROLLER" > "$DRIVER_PATH/unbind" 2>/dev/null || {
    echo "Failed to unbind controller"
    exit 1
}

sleep 2

echo "Rebinding USB controller $CONTROLLER..."
echo "$CONTROLLER" > "$DRIVER_PATH/bind" 2>/dev/null || {
    echo "Failed to rebind controller"
    exit 1
}

echo "USB controller reset complete"
