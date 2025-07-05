#!/bin/bash

# X-UI Uninstallation Script

echo "🗑️  X-UI Uninstallation Script"
echo "============================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Confirm uninstallation
echo "⚠️  This will completely remove X-UI from your system."
read -p "Are you sure you want to continue? [y/N]: " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "❌ Uninstallation cancelled"
    exit 1
fi

echo ""
echo "🗑️  Uninstalling X-UI..."

# Use X-UI's built-in uninstall function
if command -v x-ui &> /dev/null; then
    echo "📋 Using X-UI built-in uninstaller..."
    /usr/bin/x-ui <<EOF
5
y
EOF
else
    echo "⚠️  X-UI command not found, performing manual cleanup..."
    
    # Stop and disable service
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    
    # Remove service file
    rm -f /etc/systemd/system/x-ui.service
    
    # Remove X-UI files
    rm -rf /usr/local/x-ui
    rm -f /usr/bin/x-ui
    rm -f /usr/local/x-ui-linux-amd64.tar.gz
    
    # Reload systemd
    systemctl daemon-reload
    
    echo "✅ Manual cleanup completed"
fi

echo ""
echo "🎉 X-UI has been successfully uninstalled!"
echo "🔄 You may want to reboot your system to ensure all changes take effect." 