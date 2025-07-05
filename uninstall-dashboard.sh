#!/bin/bash

# Dashboard Uninstallation Script

echo "🗑️  Uninstalling Network Infrastructure Dashboard..."
echo "=================================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Confirm uninstallation
echo "⚠️  This will remove the dashboard service and files."
read -p "Are you sure you want to continue? [y/N]: " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "❌ Uninstallation cancelled"
    exit 1
fi

echo ""
echo "🗑️  Removing dashboard..."

# Stop and disable service
echo "🛑 Stopping dashboard service..."
systemctl stop dashboard.service 2>/dev/null
systemctl disable dashboard.service 2>/dev/null

# Remove service file
echo "📁 Removing service file..."
rm -f /etc/systemd/system/dashboard.service

# Remove dashboard script
echo "📁 Removing dashboard script..."
rm -f /root/dashboard.py

# Reload systemd
echo "🔄 Reloading systemd..."
systemctl daemon-reload

echo ""
echo "✅ Dashboard has been successfully uninstalled!"
echo "🔄 The dashboard service has been stopped and removed." 