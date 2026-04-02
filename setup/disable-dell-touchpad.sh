#!/bin/bash
# Disable the Dell touchpad at the kernel level via udev rule.
# The touchpad is identified by: DLL07D1:01 044E:120B

RULE='ACTION=="add|change", KERNEL=="input*", ATTRS{name}=="DLL07D1:01 044E:120B", ATTR{inhibited}="1"'
RULE_FILE="/etc/udev/rules.d/99-disable-touchpad.rules"

echo "This will create $RULE_FILE to disable the Dell touchpad."
sudo tee "$RULE_FILE" <<< "$RULE" > /dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "Done. Touchpad disabled."
